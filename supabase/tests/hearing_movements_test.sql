-- Testes da migration 20260730120000: audiências na timeline com status real.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(15);

-- ---------------------------------------------------------------------------
-- Fixtures: cliente, advogada e um caso com número CNJ (TRT4 real).
-- ---------------------------------------------------------------------------

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('b1000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'cliente@aud.test', '', now(), '{}'::jsonb,
   '{"full_name":"Cliente Audiencia"}'::jsonb, now(), now()),
  ('b1000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'advogada@aud.test', '', now(), '{}'::jsonb,
   '{"full_name":"Advogada Audiencia"}'::jsonb, now(), now());

insert into public.lawyer_profiles (id, oab_number, oab_state, primary_area, practice_areas)
values ('b1000000-0000-0000-0000-000000000002', '717171', 'RS',
        'Direito Cível', array['Direito Cível']);

insert into public.legal_cases (id, title, area, client_id, assigned_lawyer_id, cnj_number)
values ('b2000000-0000-0000-0000-000000000001', 'Caso Audiencia', 'Direito Cível',
        'b1000000-0000-0000-0000-000000000001',
        'b1000000-0000-0000-0000-000000000002',
        '00202620920255040761');

-- ---------------------------------------------------------------------------
-- 1-3. Curadoria: o mesmo código gera textos opostos conforme o status
-- ---------------------------------------------------------------------------

select is(
  (select title from public.case_movement_translations
   where movement_code = 12749 and situation = 'designada'),
  'Audiência marcada',
  'código 12749 (instrução) + designada vira "Audiência marcada"');

select is(
  (select title from public.case_movement_translations
   where movement_code = 12749 and situation = 'cancelada'),
  'Audiência cancelada',
  'o mesmo código com status oposto tem título oposto');

select is(
  (select notify from public.case_movement_translations
   where movement_code = 12749 and situation = 'realizada'),
  false,
  'audiência realizada entra na timeline mas não notifica (o cliente estava lá)');

-- ---------------------------------------------------------------------------
-- 4-6. Primeira passada (backfill de histórico): grava, traduz, não notifica
-- ---------------------------------------------------------------------------

select public.ingest_case_movements(
  'b2000000-0000-0000-0000-000000000001',
  '00202620920255040761',
  '[
    {"code":"26","name":"Distribuição","occurred_at":"2025-05-08T10:00:00Z"},
    {"code":"12749","name":"de Instrução","occurred_at":"2025-08-22T20:53:28Z","situation":"designada"},
    {"code":"12740","name":"de Conciliação","occurred_at":"2025-06-02T09:00:00Z","situation":""}
  ]'::jsonb);

-- A timeline é lida como o CLIENTE (fetch_case_movements exige can_access_case).
select set_config('request.jwt.claim.sub',
  'b1000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select is(
  (select title from public.fetch_case_movements(
     'b2000000-0000-0000-0000-000000000001') where movement_code = 12749),
  'Audiência marcada',
  'a audiência aparece na timeline com o status (antes era invisível)');

select is(
  (select title from public.fetch_case_movements(
     'b2000000-0000-0000-0000-000000000001') where movement_code = 12740),
  'Audiência',
  'sem status reconhecido (TJRS manda o tipo), cai na linha genérica');

select is(
  (select title from public.fetch_case_movements(
     'b2000000-0000-0000-0000-000000000001') where movement_code = 26),
  'Processo distribuído',
  'movimento que não é audiência segue traduzido como antes');

reset role;

select is(
  (select count(*)::int from public.notifications
   where recipient_profile_id = 'b1000000-0000-0000-0000-000000000001'),
  0,
  'primeira passada é backfill: nenhuma notificação de histórico');

-- ---------------------------------------------------------------------------
-- 7-9. Passada incremental: cancelamento notifica com o texto certo
-- ---------------------------------------------------------------------------

select public.ingest_case_movements(
  'b2000000-0000-0000-0000-000000000001',
  '00202620920255040761',
  '[{"code":"12749","name":"de Instrução","occurred_at":"2025-09-01T09:00:00Z","situation":"cancelada"}]'::jsonb);

select is(
  (select count(*)::int from public.notifications
   where recipient_profile_id = 'b1000000-0000-0000-0000-000000000001'
     and type = 'case_update'),
  1,
  'cancelamento gera exatamente uma notificação');

select ok(
  (select body from public.notifications
   where type = 'case_update' limit 1) like '%cancelada%',
  'o corpo da notificação diz que a audiência foi cancelada');

select is(
  (select last_update_label from public.legal_cases
   where id = 'b2000000-0000-0000-0000-000000000001'),
  'Audiência cancelada',
  'o rótulo do caso reflete o movimento notável mais recente');

-- ---------------------------------------------------------------------------
-- 10-12. Backfill de situação em movimento gravado antes da coluna existir
-- ---------------------------------------------------------------------------

update public.case_movements set situation = ''
where case_id = 'b2000000-0000-0000-0000-000000000001'
  and movement_code = 12749
  and occurred_at = '2025-08-22T20:53:28Z';

select public.ingest_case_movements(
  'b2000000-0000-0000-0000-000000000001',
  '00202620920255040761',
  '[{"code":"12749","name":"de Instrução","occurred_at":"2025-08-22T20:53:28Z","situation":"designada"}]'::jsonb);

select is(
  (select situation from public.case_movements
   where case_id = 'b2000000-0000-0000-0000-000000000001'
     and movement_code = 12749
     and occurred_at = '2025-08-22T20:53:28Z'),
  'designada',
  'movimento antigo ganha a situação retroativamente');

select is(
  (select count(*)::int from public.notifications
   where recipient_profile_id = 'b1000000-0000-0000-0000-000000000001'
     and type = 'case_update'),
  1,
  'REGRESSÃO: o backfill de situação NÃO vira notificação de histórico');

select is(
  (select count(*)::int from public.case_movement_translations
   where movement_code = 970),
  6,
  'o código genérico 970 ganhou as 5 situações + a linha genérica');

-- ---------------------------------------------------------------------------
-- 14-15. Colapso do ruído de cartório (sequência REAL do TRT4, 25/06/2026:
--        quatro cancelamentos em cinco minutos + marcada + realizada)
-- ---------------------------------------------------------------------------

select public.ingest_case_movements(
  'b2000000-0000-0000-0000-000000000001',
  '00202620920255040761',
  '[
    {"code":"12749","name":"de Instrução","occurred_at":"2026-06-25T14:53:36Z","situation":"cancelada"},
    {"code":"12749","name":"de Instrução","occurred_at":"2026-06-25T14:54:49Z","situation":"cancelada"},
    {"code":"12749","name":"de Instrução","occurred_at":"2026-06-25T14:58:07Z","situation":"cancelada"},
    {"code":"12749","name":"de Instrução","occurred_at":"2026-06-25T14:58:12Z","situation":"cancelada"},
    {"code":"12749","name":"de Instrução","occurred_at":"2026-06-25T14:58:31Z","situation":"designada"},
    {"code":"12749","name":"de Instrução","occurred_at":"2026-06-25T15:43:11Z","situation":"realizada"}
  ]'::jsonb);

select is(
  (select count(*)::int from public.case_movements
   where case_id = 'b2000000-0000-0000-0000-000000000001'
     and occurred_at::date = '2026-06-25'),
  6,
  'os seis movimentos crus do dia ficam todos gravados');

select set_config('request.jwt.claim.sub',
  'b1000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select is(
  (select count(*)::int from public.fetch_case_movements(
     'b2000000-0000-0000-0000-000000000001')
   where occurred_at::date = '2026-06-25'),
  3,
  'a timeline colapsa para 3 linhas no dia (cancelada, marcada, realizada)');

reset role;

select * from finish();
rollback;
