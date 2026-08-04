-- Testes da migration 20260729190000: autoavaliacao e avaliacao do proprio
-- escritorio bloqueadas (bug do teste com a mesma conta nos dois lados).
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(8);

-- ---------------------------------------------------------------------------
-- Fixtures: advogada L (membro ativa da firma F), secretaria S (membro ativa),
-- cliente C (sem vinculo com a firma). Casos aceitos para todos os cenarios.
-- ---------------------------------------------------------------------------

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('91000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'advogada@review.test', '', now(), '{}'::jsonb,
   '{"full_name":"Advogada Review"}'::jsonb, now(), now()),
  ('91000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'secretaria@review.test', '', now(), '{}'::jsonb,
   '{"full_name":"Secretaria Review"}'::jsonb, now(), now()),
  ('91000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'cliente@review.test', '', now(), '{}'::jsonb,
   '{"full_name":"Cliente Review"}'::jsonb, now(), now());

insert into public.lawyer_profiles (id, oab_number, oab_state, primary_area, practice_areas)
values ('91000000-0000-0000-0000-000000000001', '616161', 'RS',
        'Direito Cível', array['Direito Cível']);

insert into public.law_firms (id, name, initials, specialty, is_active)
values ('92000000-0000-0000-0000-000000000001', 'Firma Review', 'FR', 'Civil', true);

insert into public.law_firm_members (law_firm_id, profile_id, roles, status)
values
  ('92000000-0000-0000-0000-000000000001',
   '91000000-0000-0000-0000-000000000001', array['owner', 'lawyer'], 'active'),
  ('92000000-0000-0000-0000-000000000001',
   '91000000-0000-0000-0000-000000000002', array['secretary'], 'active');

-- Caso da propria advogada consigo mesma (cenario da conta dupla do Samuel).
insert into public.legal_cases (id, title, area, client_id, assigned_lawyer_id)
values ('93000000-0000-0000-0000-000000000001', 'Caso Espelho', 'Direito Cível',
        '91000000-0000-0000-0000-000000000001',
        '91000000-0000-0000-0000-000000000001');

-- Secretaria como cliente da propria firma.
insert into public.legal_cases (id, title, area, client_id, law_firm_id)
values ('93000000-0000-0000-0000-000000000002', 'Caso Interno', 'Direito Cível',
        '91000000-0000-0000-0000-000000000002',
        '92000000-0000-0000-0000-000000000001');

-- Cliente legitimo. Desde a 20260805120000 o gate exige mais que caso
-- aceito: caso ENCERRADO, com 24h de vida, e conversa com os DOIS lados —
-- as tres coisas que a fraude de conta-fantoche tinha de graca.
insert into public.legal_cases (id, title, area, client_id, assigned_lawyer_id,
  law_firm_id, status, created_at)
values ('93000000-0000-0000-0000-000000000003', 'Caso Legitimo', 'Direito Cível',
        '91000000-0000-0000-0000-000000000003',
        '91000000-0000-0000-0000-000000000001',
        '92000000-0000-0000-0000-000000000001',
        'closed', now() - interval '5 days');

insert into public.conversations (id, type, client_id, lawyer_id, law_firm_id,
  title, created_at)
values ('94000000-0000-0000-0000-000000000001', 'client_firm',
        '91000000-0000-0000-0000-000000000003',
        '91000000-0000-0000-0000-000000000001',
        '92000000-0000-0000-0000-000000000001',
        'Conversa Legitima', now() - interval '6 days');

insert into public.messages (conversation_id, sender_id, sender_type, body)
values
  ('94000000-0000-0000-0000-000000000001',
   '91000000-0000-0000-0000-000000000003', 'client', 'preciso de ajuda'),
  ('94000000-0000-0000-0000-000000000001',
   '91000000-0000-0000-0000-000000000001', 'lawyer', 'vamos resolver');

-- ---------------------------------------------------------------------------
-- 1-2. Advogada nao se autoavalia (gate e submissao)
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select ok(
  not public.can_review_professional('lawyer',
    '91000000-0000-0000-0000-000000000001'),
  'advogada nao e elegivel para avaliar a si mesma (botao some)');

select throws_ok(
  $$select public.submit_professional_review('lawyer',
    '91000000-0000-0000-0000-000000000001', 5, 'excelente!')$$,
  '42501',
  'Você pode avaliar depois que o caso for encerrado pelo profissional.',
  'submissao de autoavaliacao e recusada');

-- ---------------------------------------------------------------------------
-- 3-4. Advogada (membro ativa) nao avalia a propria firma
-- ---------------------------------------------------------------------------

select ok(
  not public.can_review_professional('law_firm',
    '92000000-0000-0000-0000-000000000001'),
  'dona/advogada nao e elegivel para avaliar a propria firma');

reset role;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000002', true);
set local role authenticated;

select ok(
  not public.can_review_professional('law_firm',
    '92000000-0000-0000-0000-000000000001'),
  'secretaria (membro ativa) nao e elegivel mesmo com caso como cliente');

-- ---------------------------------------------------------------------------
-- 5. Submissao da secretaria tambem barra
-- ---------------------------------------------------------------------------

select throws_ok(
  $$select public.submit_professional_review('law_firm',
    '92000000-0000-0000-0000-000000000001', 5, 'a melhor!')$$,
  '42501',
  'Você pode avaliar depois que o caso for encerrado pelo profissional.',
  'membro ativo nao consegue avaliar a propria firma');

-- ---------------------------------------------------------------------------
-- 6-8. Cliente legitimo segue avaliando normalmente
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000003', true);
set local role authenticated;

select ok(
  public.can_review_professional('lawyer',
    '91000000-0000-0000-0000-000000000001'),
  'cliente com caso aceito segue elegivel para avaliar a advogada');

select lives_ok(
  $$select public.submit_professional_review('lawyer',
    '91000000-0000-0000-0000-000000000001', 4, 'otimo atendimento')$$,
  'cliente avalia a advogada normalmente');

select lives_ok(
  $$select public.submit_professional_review('law_firm',
    '92000000-0000-0000-0000-000000000001', 5, null)$$,
  'cliente avalia a firma normalmente');

reset role;
select * from finish();
rollback;
