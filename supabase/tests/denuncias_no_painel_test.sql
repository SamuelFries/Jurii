-- As denúncias no painel da equipe.
--
-- O que este arquivo protege, em ordem de gravidade: que a conversa alheia
-- não vire leitura pública por causa da fotografia; que a fotografia seja
-- FOTOGRAFIA (congelada, sobrevivendo ao apagar) e não janela; e que a fila
-- só se esvazie com decisão registrada.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(18);

-- ---------------------------------------------------------------------------
-- Cenário: uma conversa de balcão entre cliente e escritório
-- ---------------------------------------------------------------------------
insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('e1000000-0000-0000-0000-000000000001','authenticated','authenticated','equipe@d.test','',now(),'{}','{"full_name":"Equipe Jurii"}',now(),now()),
  ('e1000000-0000-0000-0000-000000000002','authenticated','authenticated','cliente@d.test','',now(),'{}','{"full_name":"Cliente Denunciante"}',now(),now()),
  ('e1000000-0000-0000-0000-000000000003','authenticated','authenticated','advogado@d.test','',now(),'{}','{"full_name":"Advogado Denunciado"}',now(),now()),
  ('e1000000-0000-0000-0000-000000000004','authenticated','authenticated','curioso@d.test','',now(),'{}','{"full_name":"Curioso Qualquer"}',now(),now());

insert into public.jurii_staff (profile_id)
values ('e1000000-0000-0000-0000-000000000001');

insert into public.lawyer_profiles (id, oab_number, oab_state, primary_area, is_available, approved_at)
values ('e1000000-0000-0000-0000-000000000003','990001','RS','Direito Civel',true,now());

insert into public.conversations (id, type, client_id, lawyer_id, title, specialty)
values ('ec000000-0000-0000-0000-000000000001','client_firm'::conversation_type,
        'e1000000-0000-0000-0000-000000000002','e1000000-0000-0000-0000-000000000003',
        'Advogado Denunciado','Direito Civel');

-- 20 mensagens: a fotografia leva as 15 ultimas, entao as 5 primeiras ficam
-- de fora e isso precisa ser verdade, nao intencao.
insert into public.messages (conversation_id, sender_id, sender_type, body, created_at)
select
  'ec000000-0000-0000-0000-000000000001',
  case when i % 2 = 0 then 'e1000000-0000-0000-0000-000000000002'::uuid
       else 'e1000000-0000-0000-0000-000000000003'::uuid end,
  case when i % 2 = 0 then 'client'::message_sender_type
       else 'lawyer'::message_sender_type end,
  'mensagem ' || i::text,
  now() - ((30 - i) || ' minutes')::interval
from generate_series(1, 20) as i;

-- ---------------------------------------------------------------------------
-- A denúncia leva a fotografia junto
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','e1000000-0000-0000-0000-000000000002', true);
set local role authenticated;

select lives_ok(
  $$select public.report_conversation(
      'ec000000-0000-0000-0000-000000000001', 'conteudo_abusivo', 'me xingou')$$,
  'o cliente consegue denunciar a conversa');

reset role;

-- O id vai por configuracao de sessao: `user_reports` e fechada a
-- authenticated de proposito, entao nem o teste pode consultar a tabela de
-- dentro daquela role. Ler dali mascararia a falha de permissao como se
-- fosse a guarda da funcao respondendo.
select set_config('teste.denuncia_id',
  (select id::text from public.user_reports limit 1), false);

select is(
  (select jsonb_array_length(message_snapshot) from public.user_reports),
  15,
  'a denuncia guarda as 15 ultimas mensagens, e nao a conversa inteira');

select is(
  (select message_snapshot->0->>'corpo' from public.user_reports),
  'mensagem 6',
  'as 15 ultimas comecam na sexta, em ordem de leitura');

select is(
  (select message_snapshot->14->>'corpo' from public.user_reports),
  'mensagem 20',
  'e terminam na ultima');

-- ---------------------------------------------------------------------------
-- É FOTOGRAFIA, não janela
-- ---------------------------------------------------------------------------
-- Mensagem nova depois da denuncia NAO entra: a equipe ve o que existia
-- quando a acusacao foi feita, e nao a conversa que continua acontecendo.
insert into public.messages (conversation_id, sender_id, sender_type, body, created_at)
values ('ec000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000003',
        'lawyer'::message_sender_type,'assunto novo, posterior a denuncia', now());

select is(
  (select count(*)::int from public.user_reports
    where message_snapshot::text like '%posterior a denuncia%'),
  0,
  'mensagem posterior a denuncia NAO entra na fotografia');

-- E apagar para todos nao apaga a prova: quem ofende e apaga nao limpa o
-- proprio rastro, que e a razao de copiar em vez de referenciar id.
update public.messages
set deleted_for_all_at = now()
where conversation_id = 'ec000000-0000-0000-0000-000000000001'
  and body = 'mensagem 19';

select is(
  (select count(*)::int from public.user_reports
    where message_snapshot::text like '%mensagem 19%'),
  1,
  'apagar para todos NAO apaga a mensagem da denuncia');

-- ---------------------------------------------------------------------------
-- Quem alcança a fotografia
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','e1000000-0000-0000-0000-000000000004', true);
set local role authenticated;

select throws_ok(
  $$select * from public.fetch_open_reports()$$,
  'Only Jurii staff can review reports',
  'curioso nao le a fila de denuncias');

select throws_ok(
  $$select * from public.fetch_reviewed_reports()$$,
  'Only Jurii staff can review reports',
  'nem o historico');

select throws_ok(
  $$select public.count_reviewed_reports()$$,
  'Only Jurii staff can review reports',
  'nem a contagem');

select throws_ok(
  $$select public.review_user_report(
      current_setting('teste.denuncia_id')::uuid, 'dismissed', 'nada a ver')$$,
  'Only Jurii staff can review reports',
  'e nao decide denuncia alheia');

-- A funcao que tira a fotografia e INTERNA: se qualquer pessoa autenticada
-- pudesse chama-la, seria um leitor de conversa alheia com outro nome.
select is(
  (select count(*)::int from information_schema.role_routine_grants
    where routine_schema='public' and routine_name='snapshot_de_conversa'
      and grantee in ('authenticated','anon','public')),
  0,
  'snapshot_de_conversa nao e chamavel por cliente nenhum');

reset role;

-- ---------------------------------------------------------------------------
-- A equipe vê, decide, e a fila esvazia
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','e1000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select is(
  (select count(*)::int from public.fetch_open_reports()),
  1,
  'a equipe ve a denuncia aberta');

select results_eq(
  $$select reporter_name, reported_name, reason
      from public.fetch_open_reports()$$,
  $$values ('Cliente Denunciante','Advogado Denunciado','conteudo_abusivo')$$,
  'a ficha traz quem denunciou, quem foi denunciado e por que');

-- Decisao SEM nota e recusada: decisao de moderacao sem motivo escrito e
-- decisao que ninguem consegue revisar depois.
select throws_ok(
  $$select public.review_user_report(
      current_setting('teste.denuncia_id')::uuid, 'dismissed', '   ')$$,
  'Review note is required',
  'decidir exige nota');

select throws_ok(
  $$select public.review_user_report(
      current_setting('teste.denuncia_id')::uuid, 'engavetada', 'motivo')$$,
  'Invalid report decision',
  'so existem as duas saidas que a coluna sempre previu');

select lives_ok(
  $$select public.review_user_report(
      current_setting('teste.denuncia_id')::uuid, 'reviewed',
      'Confirmado no historico; advogado notificado.')$$,
  'a equipe decide, com nota');

select is(
  (select count(*)::int from public.fetch_open_reports()),
  0,
  'decidida SAI da fila');

select results_eq(
  $$select status, reviewer_name, review_note
      from public.fetch_reviewed_reports()$$,
  $$values ('reviewed','Equipe Jurii','Confirmado no historico; advogado notificado.')$$,
  'e o historico diz quem decidiu e por que');

reset role;

select * from finish();
rollback;
