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

select plan(20);

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

-- ---------------------------------------------------------------------------
-- O aviso: quem foi analisado fica sabendo
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::int from public.notifications
    where recipient_profile_id = 'e9000000-0000-0000-0000-000000000002'
      and type = 'verification_approved'),
  1,
  'aprovacao avisa a pessoa');

-- Uma segunda verificacao, para provar que a recusa leva o MOTIVO no corpo
insert into public.lawyer_verifications
  (id, user_id, oab_number, oab_state, practice_area, practice_areas, status)
values
  ('e8000000-0000-0000-0000-000000000002',
   'e9000000-0000-0000-0000-000000000003',
   '770002', 'RS', 'Direito Cível', array['Direito Cível'], 'pending');

select set_config('request.jwt.claim.sub',
  'e9000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select public.review_lawyer_verification(
  'e8000000-0000-0000-0000-000000000002', false,
  'A foto da carteira da OAB esta ilegivel.');
reset role;

select is(
  (select body from public.notifications
    where recipient_profile_id = 'e9000000-0000-0000-0000-000000000003'
      and type = 'verification_rejected'),
  'A foto da carteira da OAB esta ilegivel.',
  'a recusa leva o MOTIVO no corpo, para a pessoa saber o que corrigir');

-- ---------------------------------------------------------------------------
-- O historico: o que ja foi decidido, e por quem
-- ---------------------------------------------------------------------------

-- Intruso nao le historico: sao os mesmos documentos da fila.
select set_config('request.jwt.claim.sub',
  'e9000000-0000-0000-0000-000000000003', true);
set local role authenticated;
select throws_ok(
  $$select * from public.fetch_reviewed_verifications()$$,
  'Only Jurii staff can review verifications',
  'intruso nao le o historico');
select throws_ok(
  $$select public.count_reviewed_verifications()$$,
  'Only Jurii staff can review verifications',
  'intruso nao conta o historico');
reset role;

select set_config('request.jwt.claim.sub',
  'e9000000-0000-0000-0000-000000000001', true);
set local role authenticated;

-- As duas decididas acima (uma aprovada, uma recusada) aparecem, e a fila
-- de pendentes ficou vazia: nada some, so muda de aba.
select is(
  (select count(*)::int from public.fetch_reviewed_verifications()),
  2,
  'o historico traz a aprovada E a recusada');

-- A trilha completa: quem decidiu vem pelo NOME, e o motivo vem junto.
select results_eq(
  $$select reviewer_name, rejection_reason
     from public.fetch_reviewed_verifications()
     where status = 'rejected'$$,
  $$values ('Equipe Jurii', 'A foto da carteira da OAB esta ilegivel.')$$,
  'a recusa mostra quem decidiu e por que');

reset role;

-- ---------------------------------------------------------------------------
-- O logotipo do escritório chega à revisão
--
-- Aprovar PUBLICA essa imagem (approve_law_firm_verification copia
-- avatar_storage_path para law_firms.avatar_url, que o cliente vê na busca).
-- Enquanto ela não vinha na lista, a única peça que a decisão tornava pública
-- era a única que ninguém olhava antes de decidir.
-- ---------------------------------------------------------------------------
insert into public.law_firm_verifications
  (id, owner_profile_id, firm_name, cnpj, status, avatar_storage_path)
values
  ('e7000000-0000-0000-0000-000000000001',
   'e9000000-0000-0000-0000-000000000002',
   'Escritorio Com Logo', '11222333000181', 'pending',
   'e9000000-0000-0000-0000-000000000002/e7000000-0000-0000-0000-000000000001/avatar-1-logo.png'),
  ('e7000000-0000-0000-0000-000000000002',
   'e9000000-0000-0000-0000-000000000002',
   'Escritorio Sem Logo', '11222333000262', 'pending', null);

insert into public.law_firm_verification_documents
  (verification_id, owner_profile_id, document_type, title, storage_path, mime_type)
values
  ('e7000000-0000-0000-0000-000000000001',
   'e9000000-0000-0000-0000-000000000002',
   'cnpj_registration', 'Cartao CNPJ',
   'e9000000-0000-0000-0000-000000000002/cnpj_registration-1-cartao.pdf',
   'application/pdf');

select set_config('request.jwt.claim.sub',
  'e9000000-0000-0000-0000-000000000001', true);
set local role authenticated;

-- O logotipo vem PRIMEIRO, e do balde dele: quem revisa não deve precisar
-- rolar até o fim para achar a peça que vai ao ar.
select is(
  (select documents->0->>'bucket'
     from public.fetch_pending_verifications()
     where id = 'e7000000-0000-0000-0000-000000000001'),
  'law-firm-avatars',
  'o logotipo abre a lista, e vem do balde publico dele');

select is(
  (select documents->0->>'tipo'
     from public.fetch_pending_verifications()
     where id = 'e7000000-0000-0000-0000-000000000001'),
  'profile_photo',
  'o logotipo chega como profile_photo');

-- E os documentos de análise continuam lá, atrás dele.
select is(
  (select jsonb_array_length(documents)::int
     from public.fetch_pending_verifications()
     where id = 'e7000000-0000-0000-0000-000000000001'),
  2,
  'logotipo mais o documento de analise');

-- Escritório sem logotipo não ganha uma entrada vazia: seria um quadro
-- quebrado na tela, e pior, pareceria documento que não abre.
select is(
  (select jsonb_array_length(documents)::int
     from public.fetch_pending_verifications()
     where id = 'e7000000-0000-0000-0000-000000000002'),
  0,
  'sem logotipo, nenhuma entrada fantasma');

reset role;

-- A função que monta a lista é INTERNA: existe para a fila e o histórico
-- contarem a mesma história, e não para ser chamada de fora. Sem grant,
-- ninguém autenticado alcança os documentos de uma verificação alheia.
select is(
  (select count(*)::int
     from information_schema.role_routine_grants
    where routine_schema = 'public'
      and routine_name = 'law_firm_review_documents'
      and grantee in ('authenticated', 'anon', 'public')),
  0,
  'law_firm_review_documents nao e chamavel por cliente nenhum');

select * from finish();
rollback;
