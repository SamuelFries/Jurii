-- Testes da migration 20260807120000: confirmacao de visualizacao no chat.
--
-- O ponto mais importante daqui nao e "marcar como lido funciona" — e que
-- NINGUEM consegue marcar a propria mensagem como vista. Se isso vazasse, o
-- tique azul viraria enfeite: qualquer um forjaria "seu advogado leu" sem
-- ninguem ter aberto nada.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(18);

-- ---------------------------------------------------------------------------
-- Fixtures: cliente, advogada aprovada e um estranho
-- ---------------------------------------------------------------------------

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('f1000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'cliente@lido.test', '', now(), '{}'::jsonb,
   '{"full_name":"Cliente Lido"}'::jsonb, now(), now()),
  ('f1000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'advogada@lido.test', '', now(), '{}'::jsonb,
   '{"full_name":"Advogada Lido"}'::jsonb, now(), now()),
  ('f1000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'estranho@lido.test', '', now(), '{}'::jsonb,
   '{"full_name":"Estranho Lido"}'::jsonb, now(), now());

update public.profiles set lawyer_status = 'approved'
where id = 'f1000000-0000-0000-0000-000000000002';

insert into public.lawyer_profiles (id, oab_number, oab_state, primary_area, practice_areas)
values ('f1000000-0000-0000-0000-000000000002', '828282', 'RS',
        'Direito Cível', array['Direito Cível']);

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000001', true);
set local role authenticated;

create temporary table t_lido (name text primary key, id uuid);
insert into t_lido
select 'conv', public.start_or_get_lawyer_conversation(
  'f1000000-0000-0000-0000-000000000002', 'primeira do cliente');

reset role;

-- A advogada responde duas vezes: e o que o CLIENTE tem por ler.
insert into public.messages (conversation_id, sender_id, sender_type, body)
values
  ((select id from t_lido where name = 'conv'),
   'f1000000-0000-0000-0000-000000000002', 'lawyer', 'resposta 1'),
  ((select id from t_lido where name = 'conv'),
   'f1000000-0000-0000-0000-000000000002', 'lawyer', 'resposta 2');

-- ---------------------------------------------------------------------------
-- Estado inicial: mensagem nova nasce sem entrega e sem leitura
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::int from public.messages
    where conversation_id = (select id from t_lido where name = 'conv')
      and read_at is null),
  3,
  'as tres mensagens comecam nao lidas');

select is(
  (select count(*)::int from public.messages
    where conversation_id = (select id from t_lido where name = 'conv')
      and delivered_at is null),
  3,
  'e comecam nao entregues');

-- ---------------------------------------------------------------------------
-- Contador de nao lidas: so conta o que veio do OUTRO
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select is(
  (select unread_count from public.fetch_conversations_for_current_user('client')
    where id = (select id from t_lido where name = 'conv')),
  2,
  'cliente ve 2 nao lidas (as da advogada), nao a propria');

reset role;
select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000002', true);
set local role authenticated;

select is(
  (select unread_count from public.fetch_conversations_for_current_user('lawyer')
    where id = (select id from t_lido where name = 'conv')),
  1,
  'advogada ve 1 nao lida (a do cliente), nao as proprias');

-- ---------------------------------------------------------------------------
-- EXPLOIT: marcar a propria mensagem como vista
-- ---------------------------------------------------------------------------

select is(
  public.mark_conversation_read((select id from t_lido where name = 'conv')),
  1,
  'advogada marca como vista SO a mensagem do cliente');

select is(
  (select count(*)::int from public.messages
    where conversation_id = (select id from t_lido where name = 'conv')
      and sender_id = 'f1000000-0000-0000-0000-000000000002'
      and read_at is not null),
  0,
  'as mensagens da PROPRIA advogada continuam nao lidas (sem tique forjado)');

-- Chamar de novo nao mexe em mais nada nem reescreve o horario.
select is(
  public.mark_conversation_read((select id from t_lido where name = 'conv')),
  0,
  'segunda chamada nao marca nada de novo');

select is(
  (select unread_count from public.fetch_conversations_for_current_user('lawyer')
    where id = (select id from t_lido where name = 'conv')),
  0,
  'o contador da advogada zera depois de abrir');

-- Do outro lado nada mudou: o cliente ainda tem as duas por ler.
reset role;
select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select is(
  (select unread_count from public.fetch_conversations_for_current_user('client')
    where id = (select id from t_lido where name = 'conv')),
  2,
  'ler de um lado nao zera o contador do outro');

-- Visto implica entregue: nao existe tique azul sem os dois cinzas antes.
reset role;

select is(
  (select count(*)::int from public.messages
    where conversation_id = (select id from t_lido where name = 'conv')
      and read_at is not null
      and delivered_at is null),
  0,
  'nao existe mensagem vista sem estar entregue');

-- ---------------------------------------------------------------------------
-- Quem nao participa nao marca nada nem descobre que a conversa existe
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000003', true);
set local role authenticated;

select throws_ok(
  $$select public.mark_conversation_read(
      (select id from t_lido where name = 'conv'))$$,
  'Conversation not found',
  'estranho nao marca conversa alheia como vista');

-- Entrega em lote: id de conversa alheia entra na lista e simplesmente nao
-- produz efeito (sem erro, para nao virar oraculo de existencia).
select is(
  public.mark_messages_delivered(
    array[(select id from t_lido where name = 'conv')]),
  0,
  'estranho nao entrega nada de conversa alheia, e nao recebe erro');

-- ---------------------------------------------------------------------------
-- Entrega em lote pelo dono
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select is(
  public.mark_messages_delivered(
    array[(select id from t_lido where name = 'conv')]),
  2,
  'cliente entrega as 2 mensagens da advogada');

select is(
  (select count(*)::int from public.messages
    where conversation_id = (select id from t_lido where name = 'conv')
      and sender_id = 'f1000000-0000-0000-0000-000000000001'
      and delivered_at is null),
  0,
  'a mensagem do proprio cliente ja tinha sido entregue ao abrir do outro lado');

-- Entregue NAO e lido: o contador continua de pe.
select is(
  (select unread_count from public.fetch_conversations_for_current_user('client')
    where id = (select id from t_lido where name = 'conv')),
  2,
  'entregar nao zera o contador — sao estados diferentes');

select throws_ok(
  $$select public.mark_messages_delivered(
      (select array_agg(gen_random_uuid()) from generate_series(1, 201)))$$,
  'Too many conversations',
  'lista gigante e recusada em vez de virar varredura da tabela');

select is(
  public.mark_messages_delivered(null),
  0,
  'array nulo nao explode');

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

reset role;

select ok(
  has_function_privilege('authenticated',
    'public.mark_conversation_read(uuid)', 'execute')
  and has_function_privilege('authenticated',
    'public.mark_messages_delivered(uuid[])', 'execute')
  and not has_function_privilege('anon',
    'public.mark_conversation_read(uuid)', 'execute')
  and not has_function_privilege('anon',
    'public.mark_messages_delivered(uuid[])', 'execute'),
  'so authenticated executa as duas RPCs de confirmacao');

select * from finish();
rollback;
