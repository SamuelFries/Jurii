-- Testes da migration 20260729210000 (polimento das notificações).
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(9);

-- ---------------------------------------------------------------------------
-- Fixtures: escritório com uma sócia-advogada e uma advogada-secretária
-- (o caso que o fan-out por member_role deixava de fora).
-- ---------------------------------------------------------------------------

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('a1000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'dona@notif.test', '', now(), '{}'::jsonb,
   '{"full_name":"Dona Notif"}'::jsonb, now(), now()),
  ('a1000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'advsec@notif.test', '', now(), '{}'::jsonb,
   '{"full_name":"Advogada Secretaria"}'::jsonb, now(), now()),
  ('a1000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'estagio@notif.test', '', now(), '{}'::jsonb,
   '{"full_name":"Estagiario Notif"}'::jsonb, now(), now());

insert into public.law_firms (id, name, initials, specialty, is_active)
values ('a2000000-0000-0000-0000-000000000001', 'Firma Notif', 'FN', 'Civil', true);

-- roles = ['lawyer','secretary'] normaliza com 'lawyer' na frente, então
-- member_role vira 'lawyer' e o fan-out antigo pulava esta pessoa.
insert into public.law_firm_members
  (law_firm_id, profile_id, roles, member_role, status)
values
  ('a2000000-0000-0000-0000-000000000001',
   'a1000000-0000-0000-0000-000000000001', array['owner'], 'owner', 'active'),
  ('a2000000-0000-0000-0000-000000000001',
   'a1000000-0000-0000-0000-000000000002',
   array['lawyer', 'secretary'], 'lawyer', 'active'),
  ('a2000000-0000-0000-0000-000000000001',
   'a1000000-0000-0000-0000-000000000003', array['intern'], 'intern', 'active');

-- ---------------------------------------------------------------------------
-- 1-3. Fan-out do escritório passa a usar o ARRAY de papéis
-- ---------------------------------------------------------------------------

select ok(
  (select prosrc like '%roles && array%'
   from pg_proc where proname = 'respond_to_case_request'),
  'respond_to_case_request escolhe destinatários pelo array roles');

select ok(
  (select prosrc not like '%member_role in%'
   from pg_proc where proname = 'respond_to_case_request'),
  'o filtro pela coluna legada member_role saiu de vez');

-- O predicado novo bate exatamente com quem pode gerenciar casos.
select is(
  (select count(*)::int from public.law_firm_members lfm
   where lfm.law_firm_id = 'a2000000-0000-0000-0000-000000000001'
     and lfm.status = 'active'
     and lfm.roles && array['owner', 'admin', 'secretary']::text[]),
  2,
  'dona e advogada-secretária entram no fan-out; estagiário fica fora');

-- ---------------------------------------------------------------------------
-- 4-6. Remoção de token de push morto
-- ---------------------------------------------------------------------------

insert into public.push_tokens (profile_id, token, platform)
values ('a1000000-0000-0000-0000-000000000001', 'token-morto', 'android');

select is(
  public.delete_push_token_by_value('token-morto'), 1,
  'delete_push_token_by_value remove o token e informa quantos saíram');

select is(
  public.delete_push_token_by_value('token-inexistente'), 0,
  'token inexistente devolve 0 sem erro');

select ok(
  not has_function_privilege('authenticated',
    'public.delete_push_token_by_value(text)', 'EXECUTE'),
  'authenticated não executa a remoção de token (só o servidor de push)');

-- ---------------------------------------------------------------------------
-- 7. Teto na leitura de tokens
-- ---------------------------------------------------------------------------

insert into public.push_tokens (profile_id, token, platform)
select 'a1000000-0000-0000-0000-000000000001', 'token-' || generate_series, 'android'
from generate_series(1, 25);

select is(
  (select count(*)::int from public.fetch_push_tokens_for_recipient(
    'a1000000-0000-0000-0000-000000000001')),
  20,
  'fetch_push_tokens_for_recipient limita o fan-out aos 20 mais recentes');

-- ---------------------------------------------------------------------------
-- 8-9. Retenção: só apaga notificação LIDA e antiga
-- ---------------------------------------------------------------------------

insert into public.notifications
  (recipient_profile_id, type, title, body, read_at, created_at)
values
  ('a1000000-0000-0000-0000-000000000001', 'system', 'Velha lida', '.',
   now() - interval '200 days', now() - interval '200 days'),
  ('a1000000-0000-0000-0000-000000000001', 'system', 'Velha NAO lida', '.',
   null, now() - interval '200 days'),
  ('a1000000-0000-0000-0000-000000000001', 'system', 'Recente lida', '.',
   now(), now());

select is(
  public.purge_old_notifications(), 1,
  'purge apaga só a lida e antiga');

select is(
  (select count(*)::int from public.notifications
   where recipient_profile_id = 'a1000000-0000-0000-0000-000000000001'),
  2,
  'não lida antiga e lida recente sobrevivem');

select * from finish();
rollback;
