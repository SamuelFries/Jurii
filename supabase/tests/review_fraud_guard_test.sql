-- Testes das migrations 20260805120000 e 20260805150000.
--
-- O primeiro bloco reproduz o EXPLOIT que existia: advogado aprovado usa uma
-- conta de cliente fantoche, propõe caso a si mesmo, aceita e se avalia 5
-- estrelas. Antes o gate liberava; agora tem que barrar em cada etapa que
-- falta. Os controles POSITIVOS abaixo garantem que a correção não tornou o
-- cliente legítimo inelegível — que seria trocar um problema por outro pior.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(12);

-- ---------------------------------------------------------------------------
-- Fixtures: advogada aprovada, cliente REAL e cliente FANTOCHE
-- ---------------------------------------------------------------------------

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('d1000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'advogada@fraude.test', '', now(), '{}'::jsonb,
   '{"full_name":"Advogada Fraude"}'::jsonb, now(), now()),
  ('d1000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'real@fraude.test', '', now(), '{}'::jsonb,
   '{"full_name":"Cliente Real"}'::jsonb, now(), now()),
  ('d1000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'fantoche@fraude.test', '', now(), '{}'::jsonb,
   '{"full_name":"Cliente Fantoche"}'::jsonb, now(), now());

update public.profiles set lawyer_status = 'approved'
where id = 'd1000000-0000-0000-0000-000000000001';

insert into public.lawyer_profiles (id, oab_number, oab_state, primary_area, practice_areas)
values ('d1000000-0000-0000-0000-000000000001', '313131', 'RS',
        'Direito Cível', array['Direito Cível']);

-- FANTOCHE: caso recém-criado, encerrado na hora, conversa só de um lado.
insert into public.conversations (id, type, client_id, lawyer_id, title, created_at)
values ('d2000000-0000-0000-0000-000000000001', 'client_firm',
        'd1000000-0000-0000-0000-000000000003',
        'd1000000-0000-0000-0000-000000000001', 'Conversa Fantoche', now());

insert into public.legal_cases (id, title, area, client_id, assigned_lawyer_id, status, created_at)
values ('d3000000-0000-0000-0000-000000000001', 'Caso Fantoche', 'Direito Cível',
        'd1000000-0000-0000-0000-000000000003',
        'd1000000-0000-0000-0000-000000000001', 'closed', now());

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000003', true);
set local role authenticated;

select ok(
  not public.can_review_professional('lawyer', 'd1000000-0000-0000-0000-000000000001'),
  'fantoche com caso encerrado NA HORA e sem conversa nao avalia');

reset role;

-- Envelhece o caso além das 24h: falta ainda a conversa dos dois lados.
update public.legal_cases set created_at = now() - interval '3 days'
where id = 'd3000000-0000-0000-0000-000000000001';

set local role authenticated;
select ok(
  not public.can_review_professional('lawyer', 'd1000000-0000-0000-0000-000000000001'),
  'caso velho mas SEM conversa ainda nao avalia');
reset role;

-- Só o fantoche falou (encenou um lado): ainda não basta.
insert into public.messages (conversation_id, sender_id, sender_type, body)
values ('d2000000-0000-0000-0000-000000000001',
        'd1000000-0000-0000-0000-000000000003', 'client', 'oi');

set local role authenticated;
select ok(
  not public.can_review_professional('lawyer', 'd1000000-0000-0000-0000-000000000001'),
  'conversa com UM lado so ainda nao avalia');
reset role;

-- Encenou os dois lados: aqui o gate cede. É o limite honesto — quem controla
-- as duas contas sempre consegue forjar; o que mudou é o custo (conta nova,
-- conversa dos dois lados, caso encerrado e 24h de espera por estrela).
insert into public.messages (conversation_id, sender_id, sender_type, body)
values ('d2000000-0000-0000-0000-000000000001',
        'd1000000-0000-0000-0000-000000000001', 'lawyer', 'ola');

set local role authenticated;
select ok(
  public.can_review_professional('lawyer', 'd1000000-0000-0000-0000-000000000001'),
  'com TODAS as etapas encenadas o gate cede (limite conhecido e aceito)');
reset role;

-- ---------------------------------------------------------------------------
-- Controles POSITIVOS: o cliente legítimo continua podendo avaliar
-- ---------------------------------------------------------------------------

insert into public.conversations (id, type, client_id, lawyer_id, title, created_at)
values ('d2000000-0000-0000-0000-000000000002', 'client_firm',
        'd1000000-0000-0000-0000-000000000002',
        'd1000000-0000-0000-0000-000000000001', 'Conversa Real',
        now() - interval '10 days');

insert into public.messages (conversation_id, sender_id, sender_type, body)
values
  ('d2000000-0000-0000-0000-000000000002',
   'd1000000-0000-0000-0000-000000000002', 'client', 'preciso de ajuda'),
  ('d2000000-0000-0000-0000-000000000002',
   'd1000000-0000-0000-0000-000000000001', 'lawyer', 'claro, vamos ver');

insert into public.legal_cases (id, title, area, client_id, assigned_lawyer_id, status, created_at)
values ('d3000000-0000-0000-0000-000000000002', 'Caso Real', 'Direito Cível',
        'd1000000-0000-0000-0000-000000000002',
        'd1000000-0000-0000-0000-000000000001', 'closed', now() - interval '9 days');

select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000002', true);
set local role authenticated;

select ok(
  public.can_review_professional('lawyer', 'd1000000-0000-0000-0000-000000000001'),
  'CONTROLE POSITIVO: cliente real com caso encerrado e conversa avalia');

select lives_ok(
  $$select public.submit_professional_review('lawyer',
      'd1000000-0000-0000-0000-000000000001', 5, 'atendimento otimo')$$,
  'cliente real consegue gravar a avaliacao');

reset role;

-- Caso ABERTO não habilita: o gate agora coincide com o convite de avaliação
-- ('case_closed'), que só é disparado no encerramento.
update public.legal_cases set status = 'open'
where id = 'd3000000-0000-0000-0000-000000000002';

set local role authenticated;
select ok(
  not public.can_review_professional('lawyer', 'd1000000-0000-0000-0000-000000000001'),
  'caso ainda ABERTO nao habilita avaliacao');
reset role;

update public.legal_cases set status = 'closed'
where id = 'd3000000-0000-0000-0000-000000000002';

-- Autoavaliação direta segue barrada (guarda antiga preservada).
select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select ok(
  not public.can_review_professional('lawyer', 'd1000000-0000-0000-0000-000000000001'),
  'autoavaliacao direta continua barrada');
reset role;

-- ---------------------------------------------------------------------------
-- Antiflood (20260805150000)
-- ---------------------------------------------------------------------------

select has_function_privilege('authenticated',
  'public.can_review_professional(text, uuid)', 'execute') as auth_ok;

select ok(
  (select pg_get_functiondef(p.oid) like '%pg_advisory_xact_lock%'
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'start_or_get_lawyer_conversation'),
  'start_or_get_lawyer_conversation ganhou antiflood');

select ok(
  (select pg_get_functiondef(p.oid) like '%pg_advisory_xact_lock%'
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'start_or_get_law_firm_conversation'),
  'start_or_get_law_firm_conversation ganhou antiflood');

select ok(
  (select pg_get_functiondef(p.oid) like '%Too many case proposals%'
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'create_case_request'),
  'create_case_request ganhou antiflood');

-- Limite folgado: o cliente real abre conversa normalmente (o teto é 20/dia).
select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select lives_ok(
  $$select public.start_or_get_lawyer_conversation(
      'd1000000-0000-0000-0000-000000000001', 'oi de novo')$$,
  'CONTROLE POSITIVO: uso normal nao esbarra no antiflood');
reset role;

select * from finish();
rollback;
