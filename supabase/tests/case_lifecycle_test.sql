-- Testes da migration 20260801150000: encerrar/reabrir caso e convite de
-- avaliação. Gate = advogado responsável OU gestor ativo do escritório;
-- cliente nunca.
--
-- O prazo manual saiu na 20260804120000 (exigia manutenção perpétua e não
-- dava para automatizar pelo DataJud); os testes dele saíram junto, e a
-- urgência do painel virou sinal automático — coberta em
-- discovery/urgencia no arquivo próprio.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(11);

-- ---------------------------------------------------------------------------
-- Fixtures: cliente, advogada, dono de escritório; caso solo e caso de firma
-- ---------------------------------------------------------------------------

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('94000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'cliente@ciclo.test', '', now(), '{}'::jsonb,
   '{"full_name":"Cliente Ciclo"}'::jsonb, now(), now()),
  ('94000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'advogada@ciclo.test', '', now(), '{}'::jsonb,
   '{"full_name":"Advogada Ciclo"}'::jsonb, now(), now()),
  ('94000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'dono@ciclo.test', '', now(), '{}'::jsonb,
   '{"full_name":"Dono Ciclo"}'::jsonb, now(), now());

update public.profiles set lawyer_status = 'approved'
where id = '94000000-0000-0000-0000-000000000002';

insert into public.lawyer_profiles (id, oab_number, oab_state, primary_area, practice_areas)
values ('94000000-0000-0000-0000-000000000002', '737373', 'RS',
        'Direito Cível', array['Direito Cível']);

insert into public.law_firms (id, name, initials, specialty, is_active)
values ('95000000-0000-0000-0000-000000000001', 'Firma Ciclo', 'FC', 'Civil', true);

insert into public.law_firm_members (law_firm_id, profile_id, member_role, roles, status)
values ('95000000-0000-0000-0000-000000000001',
        '94000000-0000-0000-0000-000000000003', 'owner', array['owner'], 'active');

insert into public.legal_cases (id, title, area, client_id, assigned_lawyer_id, description)
values ('96000000-0000-0000-0000-000000000001', 'Caso Solo', 'Direito Cível',
        '94000000-0000-0000-0000-000000000001',
        '94000000-0000-0000-0000-000000000002',
        'Relato do cliente sobre o problema.');

insert into public.legal_cases (id, title, area, client_id, assigned_lawyer_id, law_firm_id)
values ('96000000-0000-0000-0000-000000000002', 'Caso Firma', 'Direito Cível',
        '94000000-0000-0000-0000-000000000001',
        '94000000-0000-0000-0000-000000000002',
        '95000000-0000-0000-0000-000000000001');

-- ---------------------------------------------------------------------------
-- Encerrar: gate e efeitos
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '94000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select throws_ok(
  $$select public.close_legal_case('96000000-0000-0000-0000-000000000001')$$,
  'Only the responsible lawyer or firm managers can close a case',
  'cliente nao encerra caso');

reset role;
select set_config('request.jwt.claim.sub', '94000000-0000-0000-0000-000000000002', true);
set local role authenticated;

select lives_ok(
  $$select public.close_legal_case('96000000-0000-0000-0000-000000000001')$$,
  'advogada responsavel encerra');

reset role;

select is(
  (select status::text from public.legal_cases
    where id = '96000000-0000-0000-0000-000000000001'),
  'closed',
  'status gravado como closed');

select is(
  (select count(*) from public.case_updates
    where case_id = '96000000-0000-0000-0000-000000000001'
      and title = 'Caso encerrado')::int,
  1,
  'timeline manual ganha a entrada de encerramento');

select results_eq(
  $$select type, scope::text, metadata->>'case_id'
    from public.notifications
    where recipient_profile_id = '94000000-0000-0000-0000-000000000001'
      and type = 'case_closed'$$,
  $$values ('case_closed', 'client', '96000000-0000-0000-0000-000000000001')$$,
  'cliente recebe o convite de avaliacao com escopo client');

-- Idempotencia: repetir nao duplica timeline nem convite.
select set_config('request.jwt.claim.sub', '94000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select public.close_legal_case('96000000-0000-0000-0000-000000000001');
reset role;

select is(
  (select count(*) from public.notifications
    where recipient_profile_id = '94000000-0000-0000-0000-000000000001'
      and type = 'case_closed')::int,
  1,
  'encerrar de novo e no-op (sem convite duplicado)');

-- ---------------------------------------------------------------------------
-- Reabrir: volta a aceitar atualização
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '94000000-0000-0000-0000-000000000002', true);
set local role authenticated;

select lives_ok(
  $$select public.reopen_legal_case('96000000-0000-0000-0000-000000000001')$$,
  'advogada reabre o caso');

select lives_ok(
  $$select public.add_case_update('96000000-0000-0000-0000-000000000001',
      'Peticao protocolada', 'corpo')$$,
  'caso reaberto volta a aceitar atualizacao manual');

reset role;

-- ---------------------------------------------------------------------------
-- Escritório: gestor encerra caso da firma
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', '94000000-0000-0000-0000-000000000003', true);
set local role authenticated;

-- O app só mostra os controles se o fetch espelhar o gate de escrita: o
-- can_manage estreito (atualizações) é false para o gestor, mas o
-- can_manage_lifecycle tem que ser true — senão a feature nasce morta.
select results_eq(
  $$select can_manage, can_manage_lifecycle
    from public.fetch_case_for_current_user('96000000-0000-0000-0000-000000000002')$$,
  $$values (false, true)$$,
  'gestor ve can_manage_lifecycle=true no detalhe do caso');

select lives_ok(
  $$select public.close_legal_case('96000000-0000-0000-0000-000000000002')$$,
  'gestor ativo do escritorio encerra caso da firma');

-- Caso encerrado nao aceita atualizacao manual (senao o rotulo 'Encerrado'
-- seria sobrescrito e o caso voltaria ao topo das listas parecendo vivo).
reset role;
select set_config('request.jwt.claim.sub', '94000000-0000-0000-0000-000000000002', true);
set local role authenticated;

select throws_ok(
  $$select public.add_case_update('96000000-0000-0000-0000-000000000002',
      'Peticao protocolada', 'corpo')$$,
  'Case is closed',
  'caso encerrado nao aceita atualizacao manual');

select * from finish();
rollback;
