-- Testes da migration 20260729150000 (andamento processual via DataJud).
-- Rodar no banco local: psql ... -f supabase/tests/case_process_timeline_test.sql
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(27);

-- ---------------------------------------------------------------------------
-- Fixtures: cliente, advogada, secretaria de escritorio e caso
-- ---------------------------------------------------------------------------

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('30000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'cliente@cnj.test', '', now(), '{}'::jsonb,
   '{"full_name":"Cliente CNJ"}'::jsonb, now(), now()),
  ('30000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'advogada@cnj.test', '', now(), '{}'::jsonb,
   '{"full_name":"Advogada CNJ"}'::jsonb, now(), now()),
  ('30000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'secretaria@cnj.test', '', now(), '{}'::jsonb,
   '{"full_name":"Secretaria CNJ"}'::jsonb, now(), now()),
  ('30000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated',
   'estranho@cnj.test', '', now(), '{}'::jsonb,
   '{"full_name":"Estranho CNJ"}'::jsonb, now(), now());

insert into public.lawyer_profiles (id, oab_number, oab_state, primary_area, practice_areas)
values ('30000000-0000-0000-0000-000000000002', '424242', 'RS',
        'Direito Cível', array['Direito Cível']);

insert into public.law_firms (id, name, initials, specialty, is_active)
values ('40000000-0000-0000-0000-000000000001', 'Firma CNJ', 'FC', 'Civil', true);

insert into public.law_firm_members (law_firm_id, profile_id, roles, status)
values ('40000000-0000-0000-0000-000000000001',
        '30000000-0000-0000-0000-000000000003',
        array['secretary'], 'active');

insert into public.legal_cases (id, title, area, client_id, assigned_lawyer_id, law_firm_id)
values ('50000000-0000-0000-0000-000000000001', 'Caso CNJ', 'Direito Cível',
        '30000000-0000-0000-0000-000000000001',
        '30000000-0000-0000-0000-000000000002',
        '40000000-0000-0000-0000-000000000001');

-- ---------------------------------------------------------------------------
-- 1-4. Validador do numero CNJ
-- ---------------------------------------------------------------------------

select ok(public.is_valid_cnj('0000842-67.2023.8.21.7000'),
  'cnj valido com mascara');
select ok(public.is_valid_cnj('50144802820258219000'),
  'cnj valido so digitos');
select ok(not public.is_valid_cnj('00008426720238217001'),
  'digito verificador errado e rejeitado');
select ok(not public.is_valid_cnj(''), 'vazio e rejeitado');

-- ---------------------------------------------------------------------------
-- 5-9. set_case_cnj_number: papeis e validacao
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select throws_ok(
  $$select public.set_case_cnj_number('50000000-0000-0000-0000-000000000001',
    '0000842-67.2023.8.21.7000')$$,
  'P0001',
  'Only professionals assigned to this case can set the case number',
  'cliente nao grava o numero');

reset role;
select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000002', true);
set local role authenticated;

select throws_ok(
  $$select public.set_case_cnj_number('50000000-0000-0000-0000-000000000001', '123')$$,
  'P0001', 'Invalid CNJ case number',
  'numero curto/invalido e recusado');

select throws_ok(
  $$select public.set_case_cnj_number('50000000-0000-0000-0000-000000000001', 'abc---')$$,
  'P0001', 'Invalid CNJ case number',
  'texto sem digitos nao vira limpeza silenciosa');

select lives_ok(
  $$select public.set_case_cnj_number('50000000-0000-0000-0000-000000000001',
    '0000842-67.2023.8.21.7000')$$,
  'advogada atribuida grava o numero');

reset role;
select is(
  (select cnj_number from public.legal_cases
   where id = '50000000-0000-0000-0000-000000000001'),
  '00008426720238217000',
  'numero armazenado normalizado (so digitos)');

-- ---------------------------------------------------------------------------
-- 10-11. Grants por coluna em legal_cases
-- ---------------------------------------------------------------------------

select ok(
  not has_column_privilege('authenticated', 'public.legal_cases',
    'cnj_number', 'UPDATE'),
  'cnj_number sem update direto: escrita so via RPC');
select ok(
  has_column_privilege('authenticated', 'public.legal_cases',
    'title', 'UPDATE'),
  'colunas de conteudo continuam com update direto (comportamento preservado)');

-- ---------------------------------------------------------------------------
-- 12-14. Primeira passada = backfill: grava tudo, NAO notifica, NAO mexe no label
-- ---------------------------------------------------------------------------

update public.legal_cases set last_update_label = 'Label manual da advogada'
where id = '50000000-0000-0000-0000-000000000001';

select is(
  (public.ingest_case_movements('50000000-0000-0000-0000-000000000001',
    '00008426720238217000',
    '[
      {"code":"26","name":"Distribuição","occurred_at":"2023-02-09T14:20:19Z","orgao":"1a Vara","tribunal":"TJRS","grau":"G1"},
      {"code":"26","name":"Distribuição","occurred_at":"2023-02-09T14:20:19Z","orgao":"1a Vara","tribunal":"TJRS","grau":"G1"},
      {"code":"51","name":"Conclusão","occurred_at":"2023-03-01T10:00:00Z","orgao":"1a Vara","tribunal":"TJRS","grau":"G1"},
      {"code":"60","name":"Expedição de documento","occurred_at":"2023-03-02T10:00:00Z","orgao":"1a Vara","tribunal":"TJRS","grau":"G1"},
      {"code":"219","name":"Procedência","occurred_at":"2024-05-10T16:30:00Z","orgao":"1a Vara","tribunal":"TJRS","grau":"G1"}
    ]'::jsonb))->>'inserted',
  '4',
  'backfill insere 4 (duplicata exata absorvida)');

select is(
  (select count(*)::int from public.notifications
   where recipient_profile_id = '30000000-0000-0000-0000-000000000001'
     and type = 'case_update'),
  0,
  'backfill NAO notifica (historico antigo nao e novidade)');

select is(
  (select last_update_label from public.legal_cases
   where id = '50000000-0000-0000-0000-000000000001'),
  'Label manual da advogada',
  'backfill NAO sobrescreve o label manual');

-- ---------------------------------------------------------------------------
-- 15-18. Passada incremental: notifica 1x, escopo client, label atualizado
-- ---------------------------------------------------------------------------

select is(
  (public.ingest_case_movements('50000000-0000-0000-0000-000000000001',
    '00008426720238217000',
    '[{"code":"848","name":"Trânsito em julgado","occurred_at":"2026-07-20T12:00:00Z","orgao":"1a Vara","tribunal":"TJRS","grau":"G1"}]'::jsonb))->>'notified',
  'true',
  'movimento novo apos backfill notifica');

select is(
  (select count(*)::int from public.notifications
   where recipient_profile_id = '30000000-0000-0000-0000-000000000001'
     and type = 'case_update'),
  1,
  'exatamente 1 notificacao');

select is(
  (select scope::text from public.notifications where type = 'case_update' limit 1),
  'client',
  'escopo client derivado do tipo (sino do cliente)');

select is(
  (select last_update_label from public.legal_cases
   where id = '50000000-0000-0000-0000-000000000001'),
  'Decisão definitiva',
  'label atualizado com o titulo traduzido');

-- ---------------------------------------------------------------------------
-- 19-20. Blindagens: numero trocado durante a consulta e dataHora podre
-- ---------------------------------------------------------------------------

select is(
  (public.ingest_case_movements('50000000-0000-0000-0000-000000000001',
    '99999999999999999999',
    '[{"code":"22","name":"Baixa Definitiva","occurred_at":"2026-07-21T12:00:00Z"}]'::jsonb))->>'skipped',
  'cnj_changed',
  'ingest de numero que nao e mais o do caso vira NO-OP');

select is(
  (public.ingest_case_movements('50000000-0000-0000-0000-000000000001',
    '00008426720238217000',
    '[
      {"code":"466","name":"Homologação de Transação","occurred_at":"banana"},
      {"code":"466","name":"Homologação de Transação","occurred_at":"2026-07-22T09:00:00Z","orgao":"1a Vara","tribunal":"TJRS","grau":"G1"}
    ]'::jsonb))->>'inserted',
  '1',
  'dataHora invalida e descartada item a item, sem abortar o lote');

-- ---------------------------------------------------------------------------
-- 21-22. Timeline traduzida e RLS
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select is(
  (select count(*)::int from public.fetch_case_movements(
    '50000000-0000-0000-0000-000000000001')),
  5,
  'cliente ve so os traduzidos (26,51,219,848,466; o 60 e ruido e fica fora)');

reset role;
select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000004', true);
set local role authenticated;

select is(
  (select count(*)::int from public.fetch_case_movements(
    '50000000-0000-0000-0000-000000000001')),
  0,
  'estranho ao caso nao ve a timeline');

reset role;

-- ---------------------------------------------------------------------------
-- 23. Troca de numero (o indicativo needs_cnj_number saiu na 20260804120000
--     junto com o prazo manual: dependia de deadline_at e nunca disparou)
-- ---------------------------------------------------------------------------

update public.legal_cases
set cnj_number = null
where id = '50000000-0000-0000-0000-000000000001';
delete from public.case_movements
  where case_id = '50000000-0000-0000-0000-000000000001';
delete from public.case_movement_sync_state
  where case_id = '50000000-0000-0000-0000-000000000001';

select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000002', true);
set local role authenticated;

select lives_ok(
  $$select public.set_case_cnj_number('50000000-0000-0000-0000-000000000001',
    '50144802820258219000')$$,
  'advogada troca o numero');

select is(
  (select cnj_number from public.fetch_lawyer_cases() limit 1),
  '50144802820258219000',
  'numero novo aparece na lista do advogado');

reset role;

-- ---------------------------------------------------------------------------
-- 26. Secretaria do escritorio do caso tambem grava o numero
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000003', true);
set local role authenticated;

select lives_ok(
  $$select public.set_case_cnj_number('50000000-0000-0000-0000-000000000001',
    '0000842-67.2023.8.21.7000')$$,
  'gestora ativa do escritorio (secretaria) grava o numero');

reset role;

-- ---------------------------------------------------------------------------
-- 27-28. Fila do job e cron agendado
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::int from public.fetch_cases_for_movement_sync(10)),
  1,
  'caso com numero e sem sincronizacao entra na fila');

select is(
  (select count(*)::int from cron.job where jobname = 'case-movement-sync'),
  1,
  'job pg_cron case-movement-sync agendado');

select * from finish();
rollback;
