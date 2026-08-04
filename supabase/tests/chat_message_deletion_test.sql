-- Testes da migration 20260808120000: apagar mensagem no chat.
--
-- Duas coisas diferentes, e o teste existe principalmente para elas nao se
-- confundirem: "para mim" some so da minha tela, "para todos" apaga o conteudo
-- de verdade — e so o autor, so dentro da janela.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(21);

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('a9000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'cliente@apagar.test', '', now(), '{}'::jsonb,
   '{"full_name":"Cliente Apagar"}'::jsonb, now(), now()),
  ('a9000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'advogada@apagar.test', '', now(), '{}'::jsonb,
   '{"full_name":"Advogada Apagar"}'::jsonb, now(), now()),
  ('a9000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'estranho@apagar.test', '', now(), '{}'::jsonb,
   '{"full_name":"Estranho Apagar"}'::jsonb, now(), now());

update public.profiles set lawyer_status = 'approved'
where id = 'a9000000-0000-0000-0000-000000000002';

insert into public.lawyer_profiles (id, oab_number, oab_state, primary_area, practice_areas)
values ('a9000000-0000-0000-0000-000000000002', '929292', 'RS',
        'Direito Cível', array['Direito Cível']);

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'a9000000-0000-0000-0000-000000000001', true);
set local role authenticated;

create temporary table t_apagar (name text primary key, id uuid);
insert into t_apagar
select 'conv', public.start_or_get_lawyer_conversation(
  'a9000000-0000-0000-0000-000000000002', 'mensagem do cliente');

insert into t_apagar
select 'do_cliente', id from public.messages
where conversation_id = (select id from t_apagar where name = 'conv')
  and body = 'mensagem do cliente';

reset role;

insert into public.messages (id, conversation_id, sender_id, sender_type, body)
values ('a8000000-0000-0000-0000-000000000001',
        (select id from t_apagar where name = 'conv'),
        'a9000000-0000-0000-0000-000000000002', 'lawyer', 'resposta da advogada');

-- Mensagem velha do cliente, fora da janela de 60h.
insert into public.messages (id, conversation_id, sender_id, sender_type, body, created_at)
values ('a8000000-0000-0000-0000-000000000002',
        (select id from t_apagar where name = 'conv'),
        'a9000000-0000-0000-0000-000000000001', 'client', 'promessa antiga',
        now() - interval '5 days');

-- ---------------------------------------------------------------------------
-- "Apagar para todos": só o autor, só na janela
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'a9000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select is(
  public.delete_messages_for_everyone(
    array['a8000000-0000-0000-0000-000000000001'::uuid]),
  0,
  'cliente NAO apaga para todos a mensagem da advogada');

select is(
  (select body from public.messages
    where id = 'a8000000-0000-0000-0000-000000000001'),
  'resposta da advogada',
  'a mensagem da advogada continua intacta');

select is(
  public.delete_messages_for_everyone(
    array['a8000000-0000-0000-0000-000000000002'::uuid]),
  0,
  'mensagem de 5 dias esta fora da janela de 60h');

select is(
  (select body from public.messages
    where id = 'a8000000-0000-0000-0000-000000000002'),
  'promessa antiga',
  'e o texto dela continua la — a janela existe para isso');

select is(
  public.delete_messages_for_everyone(
    array[(select id from t_apagar where name = 'do_cliente')]),
  1,
  'cliente apaga para todos a PROPRIA mensagem recente');

-- Apagar de verdade: nao basta esconder na tela.
select is(
  (select body from public.messages
    where id = (select id from t_apagar where name = 'do_cliente')),
  '',
  'o texto e zerado no banco, nao so escondido');

select ok(
  (select deleted_for_all_at is not null from public.messages
    where id = (select id from t_apagar where name = 'do_cliente')),
  'a lapide fica marcada com a hora');

-- A linha continua existindo: e o que permite mostrar "mensagem apagada" no
-- lugar, em vez de a conversa dar um salto sem explicacao.
select is(
  (select count(*)::int from public.messages
    where id = (select id from t_apagar where name = 'do_cliente')),
  1,
  'a linha permanece, para a lapide ter onde aparecer');

select is(
  public.delete_messages_for_everyone(
    array[(select id from t_apagar where name = 'do_cliente')]),
  0,
  'apagar de novo o que ja foi apagado nao faz nada');

-- ---------------------------------------------------------------------------
-- Anexo apagado para todos perde o acesso ao arquivo
-- ---------------------------------------------------------------------------

insert into t_apagar
select 'com_foto', (public.send_chat_attachment(
  (select id from t_apagar where name = 'conv'),
  'prova.jpg', 'image/jpeg', 2048,
  'a9000000-0000-0000-0000-000000000001/prova.jpg', 'image', 'client')).id;

select is(
  (select count(*)::int from public.message_attachments
    where message_id = (select id from t_apagar where name = 'com_foto')),
  1,
  'o anexo existe antes de apagar');

select is(
  public.delete_messages_for_everyone(
    array[(select id from t_apagar where name = 'com_foto')]),
  1,
  'foto propria e recente pode ser apagada para todos');

-- Sem a linha de message_attachments, a policy do Storage deixa de liberar o
-- objeto: e ISSO que torna a foto inacessivel, e nao a interface esconder.
select is(
  (select count(*)::int from public.message_attachments
    where message_id = (select id from t_apagar where name = 'com_foto')),
  0,
  'a linha do anexo some, e com ela o acesso ao arquivo');

-- ---------------------------------------------------------------------------
-- "Apagar para mim": some para mim, fica para o outro
-- ---------------------------------------------------------------------------

select is(
  public.delete_messages_for_me(
    array['a8000000-0000-0000-0000-000000000001'::uuid]),
  1,
  'cliente apaga para si a mensagem da advogada');

select is(
  (select count(*)::int from public.messages
    where id = 'a8000000-0000-0000-0000-000000000001'),
  0,
  'a mensagem some da leitura do cliente (RLS)');

reset role;
select set_config('request.jwt.claim.sub', 'a9000000-0000-0000-0000-000000000002', true);
set local role authenticated;

select is(
  (select body from public.messages
    where id = 'a8000000-0000-0000-0000-000000000001'),
  'resposta da advogada',
  'e continua inteira para a advogada — "para mim" e so meu');

-- ---------------------------------------------------------------------------
-- Contador de não lidas ignora o que não aparece mais
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'a9000000-0000-0000-0000-000000000002', true);
set local role authenticated;

-- Sobrou para a advogada ler: 'promessa antiga' e a foto (apagada para todos).
-- A apagada nao pode contar: nao ha o que ler nela.
select is(
  (select unread_count from public.fetch_conversations_for_current_user('lawyer')
    where id = (select id from t_apagar where name = 'conv')),
  1,
  'o contador ignora a mensagem apagada para todos');

-- ---------------------------------------------------------------------------
-- Quem não participa não apaga nada
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'a9000000-0000-0000-0000-000000000003', true);
set local role authenticated;

select is(
  public.delete_messages_for_me(
    array['a8000000-0000-0000-0000-000000000001'::uuid]),
  0,
  'estranho nao registra exclusao em conversa alheia');

select is(
  public.delete_messages_for_everyone(
    array['a8000000-0000-0000-0000-000000000001'::uuid]),
  0,
  'estranho nao apaga mensagem alheia para todos');

-- ---------------------------------------------------------------------------
-- Tetos e grants
-- ---------------------------------------------------------------------------

select throws_ok(
  $$select public.delete_messages_for_me(
      (select array_agg(gen_random_uuid()) from generate_series(1, 101)))$$,
  'Too many messages',
  'lista gigante e recusada em "apagar para mim"');

select throws_ok(
  $$select public.delete_messages_for_everyone(
      (select array_agg(gen_random_uuid()) from generate_series(1, 101)))$$,
  'Too many messages',
  'lista gigante e recusada em "apagar para todos"');

reset role;

select ok(
  -- SELECT e obrigatorio: a policy de messages consulta esta tabela, e
  -- expressao de RLS roda com o privilegio de quem consulta. Sem ele, ler
  -- QUALQUER mensagem estoura permission denied.
  has_table_privilege('authenticated', 'public.message_deletions', 'select')
  and not has_table_privilege('authenticated', 'public.message_deletions',
    'insert')
  and not has_table_privilege('authenticated', 'public.message_deletions',
    'delete')
  and has_function_privilege('authenticated',
    'public.delete_messages_for_me(uuid[])', 'execute')
  and has_function_privilege('authenticated',
    'public.delete_messages_for_everyone(uuid[])', 'execute'),
  'a tabela de exclusoes so e tocada pelas RPCs');

select * from finish();
rollback;
