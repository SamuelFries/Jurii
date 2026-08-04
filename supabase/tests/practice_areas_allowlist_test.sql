-- Testes da migration 20260805180000.
--
-- Reproduz o STUFFING que existia: `authenticated` tinha UPDATE direto em
-- practice_areas e dava para gravar qualquer string, inclusive inventada,
-- passando a aparecer em toda busca. Agora a coluna só é escrita por RPC com
-- allowlist — e o ranking distingue especialista de generalista, SEM limitar
-- quantas áreas o advogado pode atender.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(15);

-- ---------------------------------------------------------------------------
-- Fixtures: especialista em trabalhista e generalista que também a atende
-- ---------------------------------------------------------------------------

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('e5000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'especialista@area.test', '', now(), '{}'::jsonb,
   '{"full_name":"Especialista Trabalhista"}'::jsonb, now(), now()),
  ('e5000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'generalista@area.test', '', now(), '{}'::jsonb,
   '{"full_name":"Generalista Tudo"}'::jsonb, now(), now()),
  ('e5000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'cliente@area.test', '', now(), '{}'::jsonb,
   '{"full_name":"Cliente Area"}'::jsonb, now(), now());

update public.profiles set lawyer_status = 'approved'
where id in ('e5000000-0000-0000-0000-000000000001',
             'e5000000-0000-0000-0000-000000000002');

-- O generalista foi APROVADO ANTES: sem o critério novo ele ganharia o
-- desempate por approved_at e ficaria na frente do especialista.
insert into public.lawyer_profiles
  (id, oab_number, oab_state, primary_area, practice_areas, approved_at)
values
  ('e5000000-0000-0000-0000-000000000002', '424243', 'RS', 'Direito Cível',
   array['Direito Cível', 'Direito Trabalhista', 'Direito de Família',
         'Direito do Consumidor'], now() - interval '10 days'),
  ('e5000000-0000-0000-0000-000000000001', '424244', 'RS',
   'Direito Trabalhista', array['Direito Trabalhista'],
   now() - interval '1 day');

-- ---------------------------------------------------------------------------
-- Allowlist: a coluna não aceita mais escrita direta nem valor inventado
-- ---------------------------------------------------------------------------

select ok(
  not has_column_privilege('authenticated', 'public.lawyer_profiles',
    'practice_areas', 'update'),
  'authenticated NAO escreve practice_areas direto (so pela RPC)');

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e5000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select throws_ok(
  $$select public.update_lawyer_practice_areas('Direito Trabalhista',
      array['Direito Trabalhista', 'QUALQUER COISA QUE EU QUISER'])$$,
  'Invalid practice area: QUALQUER COISA QUE EU QUISER',
  'area inventada e recusada, nomeando o valor invalido');

select throws_ok(
  $$select public.update_lawyer_practice_areas('Direito Inventado',
      array['Direito Trabalhista'])$$,
  'Invalid practice area: Direito Inventado',
  'area principal invalida tambem e recusada');

select throws_ok(
  $$select public.update_lawyer_practice_areas('  ', array['Direito Cível'])$$,
  'Primary area is required',
  'area principal vazia e recusada');

-- Sem teto de quantidade: generalista de verdade continua podendo marcar
-- muitas áreas (a decisão foi mudar o RANKING, não limitar quem atende).
select lives_ok(
  $$select public.update_lawyer_practice_areas('Direito Trabalhista',
      array['Direito Trabalhista', 'Direito Cível', 'Direito de Família',
            'Direito do Consumidor', 'Direito Previdenciário'])$$,
  'cinco areas validas passam: nao ha teto de quantidade');

select is(
  (select cardinality(practice_areas) from public.lawyer_profiles
    where id = 'e5000000-0000-0000-0000-000000000001'),
  5,
  'as cinco areas foram gravadas');

-- A principal entra na lista sozinha: sem isso o advogado sumiria da
-- própria busca por área.
select is(
  public.update_lawyer_practice_areas('Direito Trabalhista',
    array['Direito Cível']),
  array['Direito Cível', 'Direito Trabalhista'],
  'area principal e injetada na lista quando faltava');

select is(
  public.update_lawyer_practice_areas('Direito Trabalhista',
    array['Direito Trabalhista', '  Direito Trabalhista  ', '']),
  array['Direito Trabalhista'],
  'duplicatas e vazios sao aparados');

reset role;

-- Volta o especialista à configuração enxuta para o teste de ranking.
update public.lawyer_profiles
set practice_areas = array['Direito Trabalhista'],
    primary_area = 'Direito Trabalhista'
where id = 'e5000000-0000-0000-0000-000000000001';

-- ---------------------------------------------------------------------------
-- Ranking: especialista antes do generalista, e generalista segue achável
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'e5000000-0000-0000-0000-000000000003', true);
set local role authenticated;

select results_eq(
  $$select id from public.fetch_recommended_lawyers(10, 'trabalhista', 0)$$,
  $$values ('e5000000-0000-0000-0000-000000000001'::uuid),
           ('e5000000-0000-0000-0000-000000000002'::uuid)$$,
  'especialista vem ANTES do generalista na busca da area dele');

select is(
  (select count(*)::int from public.fetch_recommended_lawyers(10, 'trabalhista', 0)
    where id = 'e5000000-0000-0000-0000-000000000002'),
  1,
  'generalista continua APARECENDO (sem teto, sem exclusao)');

select is(
  (select count(*)::int from public.fetch_recommended_lawyers(10, 'consumidor', 0)
    where id = 'e5000000-0000-0000-0000-000000000001'),
  0,
  'especialista nao aparece em area que nao atende');

reset role;

-- ---------------------------------------------------------------------------
-- A porta da VERIFICACAO tambem valida (fechar so a edicao deixaria o mesmo
-- stuffing entrar pelo cadastro, e approve_* copia as areas para o perfil)
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'e5000000-0000-0000-0000-000000000003', true);
set local role authenticated;

select throws_ok(
  $$select public.submit_lawyer_verification('999999', 'RS',
      'Direito Trabalhista',
      array['Direito Trabalhista', 'Direito Inventado'])$$,
  'Invalid practice area: Direito Inventado',
  'verificacao recusa area fora da allowlist');

select lives_ok(
  $$select public.submit_lawyer_verification('999999', 'RS',
      'Direito Trabalhista', array['Direito Trabalhista'])$$,
  'verificacao com area valida passa normalmente');

reset role;

-- ---------------------------------------------------------------------------
-- Grants da tabela nova
-- ---------------------------------------------------------------------------

select ok(
  has_table_privilege('authenticated', 'public.legal_practice_areas', 'select')
  and not has_table_privilege('anon', 'public.legal_practice_areas', 'select'),
  'authenticated le a lista de areas; anon nao');

select ok(
  has_function_privilege('authenticated',
    'public.update_lawyer_practice_areas(text, text[])', 'execute')
  and not has_function_privilege('anon',
    'public.update_lawyer_practice_areas(text, text[])', 'execute'),
  'so authenticated executa a RPC de areas');

select * from finish();
rollback;
