-- Testes da migration 20260729180000: uma conversa por par, mesmo com caso
-- vinculado (regressao do bug de conversas duplicadas, 29/07).
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(6);

-- ---------------------------------------------------------------------------
-- Fixtures: cliente + advogada aprovada + escritorio ativo
-- ---------------------------------------------------------------------------

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('60000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'cliente@chat.test', '', now(), '{}'::jsonb,
   '{"full_name":"Cliente Chat"}'::jsonb, now(), now()),
  ('60000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'advogada@chat.test', '', now(), '{}'::jsonb,
   '{"full_name":"Advogada Chat"}'::jsonb, now(), now());

update public.profiles set lawyer_status = 'approved'
where id = '60000000-0000-0000-0000-000000000002';

insert into public.lawyer_profiles (id, oab_number, oab_state, primary_area, practice_areas)
values ('60000000-0000-0000-0000-000000000002', '515151', 'RS',
        'Direito Cível', array['Direito Cível']);

insert into public.law_firms (id, name, initials, specialty, is_active)
values ('70000000-0000-0000-0000-000000000001', 'Firma Chat', 'FC', 'Civil', true);

-- ---------------------------------------------------------------------------
-- Conversa com advogado: reusada mesmo depois de o caso ser vinculado
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '60000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

create temporary table t_ids (name text primary key, id uuid);

insert into t_ids
select 'conv_lawyer', public.start_or_get_lawyer_conversation(
  '60000000-0000-0000-0000-000000000002', 'oi');

select is(
  public.start_or_get_lawyer_conversation(
    '60000000-0000-0000-0000-000000000002', null),
  (select id from t_ids where name = 'conv_lawyer'),
  'segunda chamada sem caso reusa a mesma conversa');

reset role;

-- Simula o aceite de um caso: respond_to_case_request grava case_id na conversa.
insert into public.legal_cases (id, title, area, client_id, assigned_lawyer_id)
values ('80000000-0000-0000-0000-000000000001', 'Caso Chat', 'Direito Cível',
        '60000000-0000-0000-0000-000000000001',
        '60000000-0000-0000-0000-000000000002');

update public.conversations
set case_id = '80000000-0000-0000-0000-000000000001'
where id = (select id from t_ids where name = 'conv_lawyer');

select set_config('request.jwt.claim.sub', '60000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select is(
  public.start_or_get_lawyer_conversation(
    '60000000-0000-0000-0000-000000000002', null),
  (select id from t_ids where name = 'conv_lawyer'),
  'REGRESSAO: conversa com caso vinculado continua sendo reusada');

select is(
  (select count(*)::int from public.conversations
   where client_id = '60000000-0000-0000-0000-000000000001'
     and lawyer_id = '60000000-0000-0000-0000-000000000002'),
  1,
  'nenhuma conversa duplicada nasceu com o advogado');

-- ---------------------------------------------------------------------------
-- Conversa com escritorio: mesmo comportamento
-- ---------------------------------------------------------------------------

insert into t_ids
select 'conv_firm', public.start_or_get_law_firm_conversation(
  '70000000-0000-0000-0000-000000000001', 'ola');

reset role;
update public.conversations
set case_id = '80000000-0000-0000-0000-000000000001'
where id = (select id from t_ids where name = 'conv_firm');

select set_config('request.jwt.claim.sub', '60000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select is(
  public.start_or_get_law_firm_conversation(
    '70000000-0000-0000-0000-000000000001', null),
  (select id from t_ids where name = 'conv_firm'),
  'REGRESSAO: conversa de escritorio com caso vinculado e reusada');

select is(
  (select count(*)::int from public.conversations
   where client_id = '60000000-0000-0000-0000-000000000001'
     and law_firm_id = '70000000-0000-0000-0000-000000000001'
     and lawyer_id is null),
  1,
  'nenhuma conversa duplicada nasceu com o escritorio');

-- Mensagem inicial continua entrando na conversa reusada
select is(
  (select count(*)::int from public.messages
   where conversation_id = (select id from t_ids where name = 'conv_lawyer')),
  1,
  'mensagem inicial gravada uma unica vez na conversa original');

reset role;
select * from finish();
rollback;
