-- Testes da migration 20260730180000: abrir UM caso pelo id (destino do
-- toque na notificação).
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(10);

-- ---------------------------------------------------------------------------
-- Fixtures: cliente, advogada do caso e um estranho.
-- ---------------------------------------------------------------------------

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('c1000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'cliente@abrir.test', '', now(), '{}'::jsonb,
   '{"full_name":"Cliente Abrir"}'::jsonb, now(), now()),
  ('c1000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'advogada@abrir.test', '', now(), '{}'::jsonb,
   '{"full_name":"Advogada Abrir"}'::jsonb, now(), now()),
  ('c1000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'estranho@abrir.test', '', now(), '{}'::jsonb,
   '{"full_name":"Pessoa Estranha"}'::jsonb, now(), now());

insert into public.lawyer_profiles (id, oab_number, oab_state, primary_area, practice_areas)
values ('c1000000-0000-0000-0000-000000000002', '818181', 'RS',
        'Direito Cível', array['Direito Cível']);

insert into public.legal_cases
  (id, title, area, client_id, assigned_lawyer_id, cnj_number)
values ('c2000000-0000-0000-0000-000000000001', 'Caso Abrir', 'Direito Cível',
        'c1000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000002',
        '00202620920255040761');

-- ---------------------------------------------------------------------------
-- 1-3. O CLIENTE abre o caso, mas não pode editar
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub',
  'c1000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select is(
  (select title from public.fetch_case_for_current_user(
    'c2000000-0000-0000-0000-000000000001')),
  'Caso Abrir',
  'cliente abre o proprio caso pelo id');

select ok(
  (select viewer_is_client from public.fetch_case_for_current_user(
    'c2000000-0000-0000-0000-000000000001')),
  'viewer_is_client identifica o cliente (o app monta o subtitulo com isso)');

select ok(
  not (select can_manage from public.fetch_case_for_current_user(
    'c2000000-0000-0000-0000-000000000001')),
  'cliente NAO recebe permissao de editar o caso');

-- ---------------------------------------------------------------------------
-- 4-5. A ADVOGADA do caso abre e pode editar
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub',
  'c1000000-0000-0000-0000-000000000002', true);
set local role authenticated;

select ok(
  (select can_manage from public.fetch_case_for_current_user(
    'c2000000-0000-0000-0000-000000000001')),
  'advogada do caso recebe permissao de editar (o servidor decide, nao a tela)');

select ok(
  not (select viewer_is_client from public.fetch_case_for_current_user(
    'c2000000-0000-0000-0000-000000000001')),
  'advogada nao e o cliente');

-- ---------------------------------------------------------------------------
-- 6. ESTRANHO nao ve nada (zero linhas, nao erro: nao confirma existencia)
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub',
  'c1000000-0000-0000-0000-000000000003', true);
set local role authenticated;

select is(
  (select count(*)::int from public.fetch_case_for_current_user(
    'c2000000-0000-0000-0000-000000000001')),
  0,
  'quem nao participa do caso recebe zero linhas');

-- ---------------------------------------------------------------------------
-- 7. Caso inexistente tambem devolve vazio, sem estourar
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::int from public.fetch_case_for_current_user(
    'c2000000-0000-0000-0000-0000000000ff')),
  0,
  'caso inexistente devolve vazio sem erro');

-- ---------------------------------------------------------------------------
-- 8-10. GESTOR DO ESCRITÓRIO que não é participante
--
-- É quem recebe a notificação `firm_case_started`: o fan-out vai para todos os
-- gestores ativos, mas `respond_to_case_request` só cria participante para o
-- cliente, o advogado e quem pediu. Sem este ramo o toque dele abria NADA — e
-- o escopo do escritório não tem outro destino.
-- ---------------------------------------------------------------------------

reset role;

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('c1000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated',
   'socio@abrir.test', '', now(), '{}'::jsonb,
   '{"full_name":"Socio Abrir"}'::jsonb, now(), now());

insert into public.law_firms (id, name, initials, specialty, is_active)
values ('c3000000-0000-0000-0000-000000000001', 'Firma Abrir', 'FA', 'Civil', true);

insert into public.law_firm_members (law_firm_id, profile_id, roles, member_role, status)
values ('c3000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000004', array['owner'], 'owner', 'active');

update public.legal_cases
set law_firm_id = 'c3000000-0000-0000-0000-000000000001'
where id = 'c2000000-0000-0000-0000-000000000001';

select set_config('request.jwt.claim.sub',
  'c1000000-0000-0000-0000-000000000004', true);
set local role authenticated;

select is(
  (select count(*)::int from public.fetch_case_for_current_user(
    'c2000000-0000-0000-0000-000000000001')),
  1,
  'REGRESSAO: socio do escritorio (nao participante) abre o caso da notificacao');

select ok(
  not (select can_manage from public.fetch_case_for_current_user(
    'c2000000-0000-0000-0000-000000000001')),
  'gestor nao designado ve o caso SEM ganhar permissao de editar');

-- E o estranho continua sem ver, agora que o caso tem escritório.
reset role;
select set_config('request.jwt.claim.sub',
  'c1000000-0000-0000-0000-000000000003', true);
set local role authenticated;

select is(
  (select count(*)::int from public.fetch_case_for_current_user(
    'c2000000-0000-0000-0000-000000000001')),
  0,
  'o ramo do escritorio nao abriu brecha para quem nao e membro');

reset role;
select * from finish();
rollback;
