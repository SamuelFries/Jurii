-- Testes da migration 20260809120000: alcance na descoberta.
--
-- Este numero vai virar fatura. O que o teste protege, antes de tudo, e que
-- ele nao seja inflavel: quem chama a RPC mil vezes no mesmo dia grava uma
-- linha, e o proprio profissional nao consegue somar alcance olhando o
-- proprio cartao.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(18);

-- ---------------------------------------------------------------------------
-- Fixtures: duas advogadas, um cliente e um escritorio
-- ---------------------------------------------------------------------------

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('b7000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'advogada@alcance.test', '', now(), '{}'::jsonb,
   '{"full_name":"Advogada Alcance"}'::jsonb, now(), now()),
  ('b7000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'cliente@alcance.test', '', now(), '{}'::jsonb,
   '{"full_name":"Cliente Alcance"}'::jsonb, now(), now()),
  ('b7000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'outro@alcance.test', '', now(), '{}'::jsonb,
   '{"full_name":"Outro Cliente"}'::jsonb, now(), now()),
  ('b7000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated',
   'dono@alcance.test', '', now(), '{}'::jsonb,
   '{"full_name":"Dono Alcance"}'::jsonb, now(), now());

update public.profiles set lawyer_status = 'approved'
where id = 'b7000000-0000-0000-0000-000000000001';

insert into public.lawyer_profiles (id, oab_number, oab_state, primary_area, practice_areas)
values ('b7000000-0000-0000-0000-000000000001', '131313', 'RS',
        'Direito Cível', array['Direito Cível']);

insert into public.law_firms (id, name, initials, specialty, is_active)
values ('b6000000-0000-0000-0000-000000000001', 'Escritorio Alcance', 'EA',
        'Civil', true);

insert into public.law_firm_members (law_firm_id, profile_id, member_role, roles, status)
values ('b6000000-0000-0000-0000-000000000001',
        'b7000000-0000-0000-0000-000000000004', 'owner', array['owner'], 'active');

-- ---------------------------------------------------------------------------
-- Registro e deduplicacao
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'b7000000-0000-0000-0000-000000000002', true);
set local role authenticated;

select is(
  public.log_discovery_events('impression', 'lawyer',
    array['b7000000-0000-0000-0000-000000000001'::uuid]),
  1,
  'primeira impressao do dia e gravada');

-- O ponto central: chamar de novo NAO soma.
select is(
  public.log_discovery_events('impression', 'lawyer',
    array['b7000000-0000-0000-0000-000000000001'::uuid]),
  1,
  'repetir no mesmo dia atualiza a mesma linha, nao cria outra');

reset role;
select is(
  (select count(*)::int from public.discovery_events
    where target_id = 'b7000000-0000-0000-0000-000000000001'
      and event_type = 'impression'),
  1,
  'uma pessoa por dia = UMA linha, por mais que o app chame');
set local role authenticated;

-- Vaga paga: uma vez pago no dia, o dia conta como pago.
select is(
  public.log_discovery_events('impression', 'lawyer',
    array['b7000000-0000-0000-0000-000000000001'::uuid],
    array['b7000000-0000-0000-0000-000000000001'::uuid]),
  1,
  'a mesma pessoa vendo em vaga paga atualiza a linha');

reset role;
select ok(
  (select sponsored from public.discovery_events
    where target_id = 'b7000000-0000-0000-0000-000000000001'
      and viewer_id = 'b7000000-0000-0000-0000-000000000002'
      and event_type = 'impression'),
  'o dia passa a contar como alcance pago');
set local role authenticated;

-- E nao volta atras: impressao organica depois nao apaga o pago do dia.
select public.log_discovery_events('impression', 'lawyer',
  array['b7000000-0000-0000-0000-000000000001'::uuid]);

reset role;
select ok(
  (select sponsored from public.discovery_events
    where target_id = 'b7000000-0000-0000-0000-000000000001'
      and viewer_id = 'b7000000-0000-0000-0000-000000000002'
      and event_type = 'impression'),
  'impressao organica depois nao apaga o pago do dia');

-- Pessoa diferente = alcance diferente.
reset role;
select set_config('request.jwt.claim.sub', 'b7000000-0000-0000-0000-000000000003', true);
set local role authenticated;

select is(
  public.log_discovery_events('impression', 'lawyer',
    array['b7000000-0000-0000-0000-000000000001'::uuid]),
  1,
  'outra pessoa no mesmo dia soma alcance');

-- ---------------------------------------------------------------------------
-- O proprio profissional nao infla o proprio numero
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'b7000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select is(
  public.log_discovery_events('impression', 'lawyer',
    array['b7000000-0000-0000-0000-000000000001'::uuid]),
  0,
  'a advogada olhando o proprio cartao nao gera alcance');

-- ---------------------------------------------------------------------------
-- Entradas invalidas
-- ---------------------------------------------------------------------------

select throws_ok(
  $$select public.log_discovery_events('clique', 'lawyer',
      array['b7000000-0000-0000-0000-000000000001'::uuid])$$,
  'Invalid event type',
  'tipo de evento fora dos dois e recusado');

select throws_ok(
  $$select public.log_discovery_events('impression', 'pessoa',
      array['b7000000-0000-0000-0000-000000000001'::uuid])$$,
  'Invalid target type',
  'tipo de alvo invalido e recusado');

select throws_ok(
  $$select public.log_discovery_events('impression', 'lawyer',
      (select array_agg(gen_random_uuid()) from generate_series(1, 101)))$$,
  'Too many targets',
  'lista gigante e recusada');

select is(
  public.log_discovery_events('impression', 'lawyer', null),
  0,
  'lista nula nao explode');

-- ---------------------------------------------------------------------------
-- Painel: cada um ve o proprio numero
-- ---------------------------------------------------------------------------

select is(
  (select reach from public.fetch_professional_reach(
    'lawyer', 'b7000000-0000-0000-0000-000000000001', 30)
   where day = (now() at time zone 'utc')::date),
  2,
  'o painel mostra 2 pessoas alcancadas hoje');

select is(
  (select sponsored_reach from public.fetch_professional_reach(
    'lawyer', 'b7000000-0000-0000-0000-000000000001', 30)
   where day = (now() at time zone 'utc')::date),
  1,
  'e separa quantas vieram de vaga paga');

select is(
  (select count(*)::int from public.fetch_professional_reach(
    'lawyer', 'b7000000-0000-0000-0000-000000000001', 30)),
  30,
  'a serie devolve o periodo inteiro, inclusive dias sem nada');

-- Quem nao e o dono do numero nao ve o numero.
reset role;
select set_config('request.jwt.claim.sub', 'b7000000-0000-0000-0000-000000000002', true);
set local role authenticated;

select throws_ok(
  $$select public.fetch_professional_reach(
      'lawyer', 'b7000000-0000-0000-0000-000000000001', 30)$$,
  'Not allowed',
  'cliente nao ve o alcance de advogado nenhum');

select throws_ok(
  $$select public.fetch_professional_reach(
      'law_firm', 'b6000000-0000-0000-0000-000000000001', 30)$$,
  'Not allowed',
  'quem nao fala pelo escritorio nao ve o alcance dele');

-- ---------------------------------------------------------------------------
-- A tabela nao e legivel: ela diz quem olhou quem
-- ---------------------------------------------------------------------------

reset role;

select ok(
  not has_table_privilege('authenticated', 'public.discovery_events', 'select')
  and not has_table_privilege('authenticated', 'public.discovery_events', 'insert'),
  'discovery_events nao e lida nem escrita direto — so pelas RPCs');

select * from finish();
rollback;
