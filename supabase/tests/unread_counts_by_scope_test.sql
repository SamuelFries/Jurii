-- Testes da migration 20260812120000: contagem de nao lidas por fluxo.
--
-- Este numero alimenta o seletor de modo. O que ele resolve e informacao
-- perdida: hoje quem esta no modo cliente nao fica sabendo que chegou algo no
-- modo advogado. Entao os testes cobrem os dois lados do risco — contar o que
-- e de outra pessoa seria vazamento, e nao contar o que e do usuario seria
-- manter o problema.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(9);

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('c9000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'tresfluxos@escopo.test', '', now(), '{}'::jsonb,
   '{"full_name":"Tres Fluxos"}'::jsonb, now(), now()),
  ('c9000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'outro@escopo.test', '', now(), '{}'::jsonb,
   '{"full_name":"Outro"}'::jsonb, now(), now());

insert into public.law_firms (id, name, initials, specialty, is_active)
values
  ('c8000000-0000-0000-0000-000000000001', 'Firma A', 'FA', 'Civil', true),
  ('c8000000-0000-0000-0000-000000000002', 'Firma B', 'FB', 'Penal', true);

-- ATENCAO ao escolher os tipos: um trigger (notifications_set_scope) DERIVA o
-- escopo a partir do TYPE e sobrescreve o que for passado. Usar 'case_movement'
-- aqui com scope 'client' gravaria escopo 'lawyer' e o teste mediria outra
-- coisa. Por isso cada tipo abaixo e um que infer_notification_scope mapeia
-- para o escopo pretendido.
--
-- Duas nao lidas de cliente, uma de advogado, uma LIDA de advogado, e uma de
-- escritorio em cada firma.
insert into public.notifications
  (recipient_profile_id, scope, type, title, body, law_firm_id, read_at)
values
  ('c9000000-0000-0000-0000-000000000001', 'client', 'case_update',
   'a', 'a', null, null),
  ('c9000000-0000-0000-0000-000000000001', 'client', 'case_closed',
   'b', 'b', null, null),
  ('c9000000-0000-0000-0000-000000000001', 'lawyer', 'team_invite',
   'c', 'c', null, null),
  ('c9000000-0000-0000-0000-000000000001', 'lawyer', 'case_request_response',
   'd', 'd', null, now()),
  ('c9000000-0000-0000-0000-000000000001', 'firm', 'firm_case_started',
   'e', 'e', 'c8000000-0000-0000-0000-000000000001', null),
  ('c9000000-0000-0000-0000-000000000001', 'firm', 'firm_case_started',
   'f', 'f', 'c8000000-0000-0000-0000-000000000002', null),
  -- De OUTRA pessoa: nunca pode aparecer na contagem.
  ('c9000000-0000-0000-0000-000000000002', 'client', 'case_update',
   'g', 'g', null, null);

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'c9000000-0000-0000-0000-000000000001', true);
set local role authenticated;

-- ---------------------------------------------------------------------------
-- Os tres escopos vem sempre, inclusive zerados
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::int from public.fetch_unread_notification_counts()),
  3,
  'devolve sempre os tres fluxos, para o app desenhar a lista direto');

select results_eq(
  $$select scope from public.fetch_unread_notification_counts() order by scope$$,
  $$values ('client'), ('firm'), ('lawyer')$$,
  'os tres escopos do app, nomeados como o banco os grava');

select is(
  (select unread from public.fetch_unread_notification_counts()
    where scope = 'client'),
  2,
  'cliente: as duas nao lidas');

select is(
  (select unread from public.fetch_unread_notification_counts()
    where scope = 'lawyer'),
  1,
  'advogado: so a nao lida — a que ja foi lida nao conta');

-- ---------------------------------------------------------------------------
-- Escritorio: o contador tem que bater com o sino de dentro do modo
-- ---------------------------------------------------------------------------

select is(
  (select unread from public.fetch_unread_notification_counts()
    where scope = 'firm'),
  2,
  'sem escritorio escolhido, soma as firmas');

select is(
  (select unread from public.fetch_unread_notification_counts(
    'c8000000-0000-0000-0000-000000000001')
    where scope = 'firm'),
  1,
  'com escritorio escolhido, conta so o dele');

select is(
  (select unread from public.fetch_unread_notification_counts(
    'c8000000-0000-0000-0000-000000000001')
    where scope = 'client'),
  2,
  'o filtro de escritorio nao mexe nos outros dois fluxos');

-- ---------------------------------------------------------------------------
-- Nao vaza notificacao alheia
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'c9000000-0000-0000-0000-000000000002', true);
set local role authenticated;

select is(
  (select unread from public.fetch_unread_notification_counts()
    where scope = 'client'),
  1,
  'cada um conta so as proprias');

reset role;

select ok(
  has_function_privilege('authenticated',
    'public.fetch_unread_notification_counts(uuid)', 'execute')
  and not has_function_privilege('anon',
    'public.fetch_unread_notification_counts(uuid)', 'execute'),
  'so authenticated executa');

select * from finish();
rollback;
