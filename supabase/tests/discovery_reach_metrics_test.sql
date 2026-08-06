-- Testes da migration 20260809120000: alcance na descoberta.
--
-- Este numero vai virar fatura. O que o teste protege, antes de tudo, e que
-- ele nao seja inflavel: quem chama a RPC mil vezes no mesmo dia grava uma
-- linha, e o proprio profissional nao consegue somar alcance olhando o
-- proprio cartao.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(25);

-- O dia de referencia e o de SAO PAULO, o mesmo que a funcao usa. Comparar com
-- o dia UTC funcionaria 21 horas por dia e falharia entre 21h e meia-noite,
-- quando os dois calendarios divergem — o tipo de teste que quebra sozinho de
-- madrugada e some quando alguem vai olhar.

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
   where day = (now() at time zone 'America/Sao_Paulo')::date),
  2,
  'o painel mostra 2 pessoas alcancadas hoje');

select is(
  (select sponsored_reach from public.fetch_professional_reach(
    'lawyer', 'b7000000-0000-0000-0000-000000000001', 30)
   where day = (now() at time zone 'America/Sao_Paulo')::date),
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
-- Conversa iniciada = o CLIENTE escreveu. Abrir o chat nao conta.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'b7000000-0000-0000-0000-000000000002', true);
set local role authenticated;

-- Cliente abre o chat com a advogada e nao escreve nada — que e o que
-- acontece quando alguem toca em "conversar" e desiste.
select public.start_or_get_lawyer_conversation(
  'b7000000-0000-0000-0000-000000000001', '');

reset role;
select set_config('request.jwt.claim.sub', 'b7000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select is(
  (select conversations from public.fetch_professional_reach(
    'lawyer', 'b7000000-0000-0000-0000-000000000001', 30)
   where day = (now() at time zone 'America/Sao_Paulo')::date),
  0,
  'abrir o chat sem escrever NAO conta como conversa iniciada');

-- Agora o cliente escreve de verdade.
reset role;
select set_config('request.jwt.claim.sub', 'b7000000-0000-0000-0000-000000000002', true);
set local role authenticated;

select public.start_or_get_lawyer_conversation(
  'b7000000-0000-0000-0000-000000000001', 'preciso de ajuda');

reset role;
select set_config('request.jwt.claim.sub', 'b7000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select is(
  (select conversations from public.fetch_professional_reach(
    'lawyer', 'b7000000-0000-0000-0000-000000000001', 30)
   where day = (now() at time zone 'America/Sao_Paulo')::date),
  1,
  'a primeira mensagem do cliente e que vira lead');

-- Mensagem do PROFISSIONAL nao cria lead: quando o escritorio sugere um
-- advogado e ele escreve primeiro, ainda nao ha interesse manifestado.
reset role;

insert into public.conversations (id, type, client_id, lawyer_id, title)
values ('b5000000-0000-0000-0000-000000000001', 'client_firm',
        'b7000000-0000-0000-0000-000000000003',
        'b7000000-0000-0000-0000-000000000001', 'Sugerida');

insert into public.messages (conversation_id, sender_id, sender_type, body)
values ('b5000000-0000-0000-0000-000000000001',
        'b7000000-0000-0000-0000-000000000001', 'lawyer', 'ola, posso ajudar?');

select set_config('request.jwt.claim.sub', 'b7000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select is(
  (select conversations from public.fetch_professional_reach(
    'lawyer', 'b7000000-0000-0000-0000-000000000001', 30)
   where day = (now() at time zone 'America/Sao_Paulo')::date),
  1,
  'mensagem do proprio advogado nao vira lead');

-- Canal interno de equipe tem law_firm_id e nunca foi lead do escritorio.
reset role;

insert into public.conversations (id, type, client_id, law_firm_id, title)
values ('b5000000-0000-0000-0000-000000000002', 'firm_internal',
        'b7000000-0000-0000-0000-000000000004',
        'b6000000-0000-0000-0000-000000000001', 'Equipe');

insert into public.messages (conversation_id, sender_id, sender_type, body)
values ('b5000000-0000-0000-0000-000000000002',
        'b7000000-0000-0000-0000-000000000004', 'client', 'reuniao as 15h');

select set_config('request.jwt.claim.sub', 'b7000000-0000-0000-0000-000000000004', true);
set local role authenticated;

select is(
  (select conversations from public.fetch_professional_reach(
    'law_firm', 'b6000000-0000-0000-0000-000000000001', 30)
   where day = (now() at time zone 'America/Sao_Paulo')::date),
  0,
  'chat interno da equipe nao entra no lead do escritorio');

-- ---------------------------------------------------------------------------
-- Vaga paga NAO e a mesma coisa que ter patrocinio ativo
-- ---------------------------------------------------------------------------

reset role;

-- Tres advogadas patrocinadas na mesma area. As vagas sao 2: uma delas
-- aparece organicamente, e essa impressao nao pode ser atribuida a vaga.
insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select
  ('b4000000-0000-0000-0000-00000000000' || n)::uuid,
  'authenticated', 'authenticated', 'paga' || n || '@alcance.test', '',
  now(), '{}'::jsonb,
  ('{"full_name":"Paga ' || n || '"}')::jsonb, now(), now()
from generate_series(1, 3) as n;

update public.profiles set lawyer_status = 'approved'
where id::text like 'b4000000-%';

insert into public.lawyer_profiles (id, oab_number, oab_state, primary_area, practice_areas)
select
  ('b4000000-0000-0000-0000-00000000000' || n)::uuid,
  '90000' || n, 'RS', 'Direito Tributário', array['Direito Tributário']
from generate_series(1, 3) as n;

insert into public.featured_placements (target_type, lawyer_id, starts_at, ends_at)
select 'lawyer', ('b4000000-0000-0000-0000-00000000000' || n)::uuid,
       now() - interval '1 day', now() + interval '30 days'
from generate_series(1, 3) as n;

select set_config('request.jwt.claim.sub', 'b7000000-0000-0000-0000-000000000002', true);
set local role authenticated;

select is(
  (select count(*)::int
   from public.fetch_recommended_lawyers(10, 'tributário', 0)
   where is_featured),
  3,
  'as tres tem selo de patrocinado — o selo nao tem teto');

select is(
  (select count(*)::int
   from public.fetch_recommended_lawyers(10, 'tributário', 0)
   where is_sponsored_slot),
  2,
  'mas so DUAS ocupam vaga paga — e so essas a medicao pode atribuir a vaga');

reset role;

-- ---------------------------------------------------------------------------
-- Escritorio nao infla o proprio alcance navegando na descoberta
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'b7000000-0000-0000-0000-000000000004', true);
set local role authenticated;

select is(
  public.log_discovery_events('impression', 'law_firm',
    array['b6000000-0000-0000-0000-000000000001'::uuid]),
  0,
  'dono navegando na descoberta nao conta alcance do proprio escritorio');

reset role;

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
