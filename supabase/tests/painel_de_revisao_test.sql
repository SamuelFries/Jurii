-- O painel de revisão da equipe Jurii: quem entra, quem não entra, e a
-- trilha de quem decidiu.
--
-- O QUE ISTO PROTEGE: as funções de decisão são SECURITY DEFINER e
-- alcançam as service_role. Se a checagem de equipe falhar, qualquer
-- pessoa autenticada aprova a própria OAB. É o teste mais importante do
-- arquivo, e por isso ele vem primeiro.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(9);

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('e9000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'equipe@jurii.test', '', now(), '{}'::jsonb,
   '{"full_name":"Equipe Jurii"}'::jsonb, now(), now()),
  ('e9000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'candidato@jurii.test', '', now(), '{}'::jsonb,
   '{"full_name":"Candidato Silva"}'::jsonb, now(), now()),
  ('e9000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'intruso@jurii.test', '', now(), '{}'::jsonb,
   '{"full_name":"Intruso Qualquer"}'::jsonb, now(), now());

insert into public.jurii_staff (profile_id)
values ('e9000000-0000-0000-0000-000000000001');

insert into public.lawyer_verifications
  (id, user_id, oab_number, oab_state, practice_area, practice_areas, status)
values
  ('e8000000-0000-0000-0000-000000000001',
   'e9000000-0000-0000-0000-000000000002',
   '770001', 'RS', 'Direito Cível', array['Direito Cível'], 'pending');

-- ---------------------------------------------------------------------------
-- A tabela da equipe não é alcançável por cliente nenhum
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::int from pg_policies
    where schemaname='public' and tablename='jurii_staff'),
  0,
  'jurii_staff nao tem policy: nenhum cliente le nem escreve');

select ok(
  not has_table_privilege('authenticated', 'public.jurii_staff', 'INSERT'),
  'authenticated nao INSERE na equipe (nem para se listar)');

-- ---------------------------------------------------------------------------
-- O INTRUSO: autenticado, mas fora da equipe
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub',
  'e9000000-0000-0000-0000-000000000003', true);
set local role authenticated;

select is(public.is_jurii_staff(), false, 'intruso nao e da equipe');

select throws_ok(
  $$select * from public.fetch_pending_verifications()$$,
  'Only Jurii staff can review verifications',
  'intruso nao ve a fila');

-- O teste que mais importa: sem a checagem, isto aprovaria a verificacao.
select throws_ok(
  $$select public.review_lawyer_verification(
      'e8000000-0000-0000-0000-000000000001', true)$$,
  'Only Jurii staff can review verifications',
  'intruso NAO aprova verificacao alheia');

reset role;

-- ---------------------------------------------------------------------------
-- A EQUIPE
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub',
  'e9000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select is(public.is_jurii_staff(), true, 'quem esta na tabela e da equipe');

select is(
  (select count(*)::int from public.fetch_pending_verifications()
    where kind = 'lawyer'),
  1,
  'a equipe ve a verificacao pendente');

-- Recusa SEM motivo e barrada: o candidato precisa saber o que corrigir.
select throws_ok(
  $$select public.review_lawyer_verification(
      'e8000000-0000-0000-0000-000000000001', false, '   ')$$,
  'Rejection reason is required',
  'recusa exige motivo');

reset role;

-- ---------------------------------------------------------------------------
-- A trilha: quem decidiu fica gravado
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub',
  'e9000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select public.review_lawyer_verification(
  'e8000000-0000-0000-0000-000000000001', true);
reset role;

select results_eq(
  $$select status::text, reviewer_id from public.lawyer_verifications
     where id = 'e8000000-0000-0000-0000-000000000001'$$,
  $$values ('approved', 'e9000000-0000-0000-0000-000000000001'::uuid)$$,
  'aprovada, e com o revisor gravado');

select * from finish();
rollback;
