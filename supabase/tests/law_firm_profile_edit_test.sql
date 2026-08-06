-- Testes da migration 20260813120000: editar o cadastro do escritorio.
--
-- Antes disto, escritorio aprovado nao corrigia nada: telefone trocado, mudanca
-- de endereco ou erro no nome ficavam para sempre. E o endereco alimenta a
-- ordenacao por distancia da descoberta, entao "nao da para corrigir" tinha
-- efeito em quem o cliente encontra.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(24);

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('e9000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'dono@edita.test', '', now(), '{}'::jsonb,
   '{"full_name":"Dono Edita"}'::jsonb, now(), now()),
  ('e9000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'secretaria@edita.test', '', now(), '{}'::jsonb,
   '{"full_name":"Secretaria Edita"}'::jsonb, now(), now()),
  ('e9000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'estranho@edita.test', '', now(), '{}'::jsonb,
   '{"full_name":"Estranho Edita"}'::jsonb, now(), now());

insert into public.law_firms
  (id, name, initials, specialty, practice_areas, phone, avatar_url, is_active)
values
  ('e8000000-0000-0000-0000-000000000001', 'Firma Antiga', 'FA',
   'Direito Cível', array['Direito Cível'], '5133334444',
   '/storage/v1/object/public/law-firm-avatars/e9000000-0000-0000-0000-000000000001/e7000000-0000-0000-0000-000000000001/antigo.png', true),
  ('e8000000-0000-0000-0000-000000000002', 'Outra Firma', 'OF',
   'Direito Penal', array['Direito Penal'], null, null, true);

insert into public.law_firm_members
  (law_firm_id, profile_id, member_role, roles, status)
values
  ('e8000000-0000-0000-0000-000000000001',
   'e9000000-0000-0000-0000-000000000001', 'owner', array['owner'], 'active'),
  ('e8000000-0000-0000-0000-000000000001',
   'e9000000-0000-0000-0000-000000000002', 'secretary', array['secretary'],
   'active');

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e9000000-0000-0000-0000-000000000001', true);
set local role authenticated;

-- ---------------------------------------------------------------------------
-- O caminho feliz, com normalizacao
-- ---------------------------------------------------------------------------

select results_eq(
  $$select name, initials, specialty, phone, email, cep
    from public.update_law_firm_profile(
      'e8000000-0000-0000-0000-000000000001',
      '  Weber e Silva Advogados  ', '(51) 99999-8888',
      'CONTATO@Weber.com.BR', 'https://weber.com.br', 'Av. Ipiranga, 100',
      '90160-091', -30.03, -51.22, 'Direito Trabalhista',
      array['Direito Trabalhista', 'Direito Cível'])$$,
  $$values ('Weber e Silva Advogados', 'WA', 'Direito Trabalhista',
            '51999998888', 'contato@weber.com.br', '90160091')$$,
  'nome aparado, telefone e cep so com digitos, e-mail em minuscula');

-- As iniciais acompanham o nome: sem isso, corrigir o nome deixaria o avatar
-- de letras com as iniciais antigas para sempre.
select is(
  (select initials from public.law_firms
    where id = 'e8000000-0000-0000-0000-000000000001'),
  'WA',
  'as iniciais sao recalculadas a partir do nome novo');

select is(
  (select array_length(practice_areas, 1) from public.law_firms
    where id = 'e8000000-0000-0000-0000-000000000001'),
  2,
  'as duas areas foram gravadas');

-- Area principal fora da lista entra sozinha, senao o escritorio sumiria da
-- propria busca por area.
select ok(
  (select 'Direito de Família' = any(practice_areas)
   from public.update_law_firm_profile(
     'e8000000-0000-0000-0000-000000000001', 'Weber e Silva Advogados',
     null, null, null, null, null, null, null,
     'Direito de Família', array['Direito Cível'])),
  'a area principal e injetada na lista quando faltava');

-- ---------------------------------------------------------------------------
-- Quem pode editar
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'e9000000-0000-0000-0000-000000000002', true);
set local role authenticated;

select throws_ok(
  $$select public.update_law_firm_profile(
      'e8000000-0000-0000-0000-000000000001', 'Nome da Secretaria')$$,
  'Not allowed',
  'secretaria nao edita o cadastro');

reset role;
select set_config('request.jwt.claim.sub', 'e9000000-0000-0000-0000-000000000003', true);
set local role authenticated;

select throws_ok(
  $$select public.update_law_firm_profile(
      'e8000000-0000-0000-0000-000000000001', 'Sequestro de Marca')$$,
  'Not allowed',
  'quem nao e do escritorio nao edita');

select is(
  (select name from public.law_firms
    where id = 'e8000000-0000-0000-0000-000000000001'),
  'Weber e Silva Advogados',
  'e o nome continua o que o gestor deixou');

-- ---------------------------------------------------------------------------
-- Validacoes
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'e9000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select throws_ok(
  $$select public.update_law_firm_profile(
      'e8000000-0000-0000-0000-000000000001', '   ')$$,
  'Firm name is required',
  'nome vazio e recusado');

select throws_ok(
  $$select public.update_law_firm_profile(
      'e8000000-0000-0000-0000-000000000001', 'Firma', '99999')$$,
  'Invalid phone',
  'telefone sem DDD e recusado');

select throws_ok(
  $$select public.update_law_firm_profile(
      'e8000000-0000-0000-0000-000000000001', 'Firma', null, 'sem-arroba')$$,
  'Invalid email',
  'e-mail sem formato e recusado');

select throws_ok(
  $$select public.update_law_firm_profile(
      'e8000000-0000-0000-0000-000000000001', 'Firma', null, null, null, null,
      '123')$$,
  'Invalid cep',
  'cep com menos de 8 digitos e recusado');

-- Meia coordenada quebraria a ordenacao por distancia em vez de simplesmente
-- nao ordenar.
select throws_ok(
  $$select public.update_law_firm_profile(
      'e8000000-0000-0000-0000-000000000001', 'Firma', null, null, null, null,
      null, -30.03, null)$$,
  'Coordinates must come in pairs',
  'coordenada solteira e recusada');

select throws_ok(
  $$select public.update_law_firm_profile(
      'e8000000-0000-0000-0000-000000000001', 'Firma', null, null, null, null,
      null, -300.0, -51.22)$$,
  'Coordinates out of range',
  'coordenada fora da faixa e recusada');

select throws_ok(
  $$select public.update_law_firm_profile(
      'e8000000-0000-0000-0000-000000000001', 'Firma', null, null, null, null,
      null, null, null, 'Direito Inventado')$$,
  'Invalid practice area: Direito Inventado',
  'area fora da allowlist e recusada, nomeando o valor');

-- ---------------------------------------------------------------------------
-- Logo
-- ---------------------------------------------------------------------------

select throws_ok(
  $$select public.update_law_firm_profile(
      'e8000000-0000-0000-0000-000000000001', 'Firma', null, null, null, null,
      null, null, null, null, null, 'trocar')$$,
  'Invalid avatar action',
  'acao de avatar fora das tres e recusada');

-- Caminho na pasta de OUTRA firma nao pode virar avatar_url quebrado no
-- cartao de todo mundo.
select throws_ok(
  $$select public.update_law_firm_profile(
      'e8000000-0000-0000-0000-000000000001', 'Firma', null, null, null, null,
      null, null, null, null, null, 'replace',
      'e8000000-0000-0000-0000-000000000002/logo.png')$$,
  'Invalid avatar path',
  'caminho de outra firma e recusado');

select is(
  (select avatar_url from public.update_law_firm_profile(
    'e8000000-0000-0000-0000-000000000001', 'Firma')),
  '/storage/v1/object/public/law-firm-avatars/e9000000-0000-0000-0000-000000000001/e7000000-0000-0000-0000-000000000001/antigo.png',
  'preserve mantem o logo que ja estava la');

select is(
  (select avatar_url from public.update_law_firm_profile(
    'e8000000-0000-0000-0000-000000000001', 'Firma', null, null, null, null,
    null, null, null, null, null, 'remove')),
  null,
  'remove limpa o logo');

-- ---------------------------------------------------------------------------
-- CNPJ: visivel para quem edita, invisivel para o resto
-- ---------------------------------------------------------------------------

reset role;

insert into public.law_firm_verifications
  (id, owner_profile_id, law_firm_id, firm_name, cnpj, phone, email, address,
   practice_areas, status, reviewed_at)
values
  ('e6000000-0000-0000-0000-000000000001',
   'e9000000-0000-0000-0000-000000000001',
   'e8000000-0000-0000-0000-000000000001', 'Weber e Silva',
   '12345678000190', '5133334444', 'c@w.com', 'Rua', array['Direito Cível'],
   'approved', now());

select set_config('request.jwt.claim.sub', 'e9000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select is(
  public.fetch_law_firm_cnpj('e8000000-0000-0000-0000-000000000001'),
  '12345678000190',
  'gestor ve o CNPJ do proprio escritorio');

reset role;
select set_config('request.jwt.claim.sub', 'e9000000-0000-0000-0000-000000000002', true);
set local role authenticated;

-- O CNPJ nao esta em law_firms de proposito: copiar para la o colocaria a um
-- select de distancia de vazar nos RPCs de descoberta.
select is(
  public.fetch_law_firm_cnpj('e8000000-0000-0000-0000-000000000001'),
  null,
  'secretaria nao ve o CNPJ');

reset role;
select set_config('request.jwt.claim.sub', 'e9000000-0000-0000-0000-000000000003', true);
set local role authenticated;

select is(
  public.fetch_law_firm_cnpj('e8000000-0000-0000-0000-000000000001'),
  null,
  'quem nao e do escritorio nao ve o CNPJ');

reset role;

select ok(
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'law_firms'
      and column_name = 'cnpj'
  ),
  'law_firms continua SEM coluna de cnpj — a descoberta nunca o devolve');

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

reset role;

select ok(
  has_function_privilege('authenticated',
    'public.update_law_firm_profile(uuid, text, text, text, text, text, text,'
    || ' double precision, double precision, text, text[], text, text)',
    'execute')
  and not has_function_privilege('anon',
    'public.update_law_firm_profile(uuid, text, text, text, text, text, text,'
    || ' double precision, double precision, text, text[], text, text)',
    'execute'),
  'so authenticated executa a edicao');

select ok(
  not has_table_privilege('authenticated', 'public.law_firms', 'update'),
  'a tabela continua sem UPDATE direto — so pela RPC');

select * from finish();
rollback;
