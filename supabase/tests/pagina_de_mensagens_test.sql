-- A página de mensagens do chat.
--
-- O teto fixo de 100 fazia a mensagem 101 sumir em silêncio. A função pagina
-- por cursor composto (created_at, id), que é estável sob timestamps
-- empatados, e roda como INVOKER: quem corta é a RLS de messages, a mesma de
-- sempre.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(12);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('b1000000-0000-4000-8000-00000000000a','authenticated','authenticated','cliente@pag.test','',now(),'{}','{"full_name":"Cliente Pag"}',now(),now()),
  ('b1000000-0000-4000-8000-00000000000b','authenticated','authenticated','intruso@pag.test','',now(),'{}','{"full_name":"Intruso Pag"}',now(),now());

insert into public.conversations (id, type, client_id, title)
values ('bc000000-0000-4000-8000-00000000000c','client_firm',
        'b1000000-0000-4000-8000-00000000000a','Conversa paginada');

-- Sete mensagens; m3 e m4 nascem no MESMO instante de propósito: é o empate
-- que faria um cursor só de created_at pular uma delas para sempre.
insert into public.messages (id, conversation_id, sender_id, sender_type, body, created_at)
select ('bd000000-0000-4000-8000-00000000000' || n)::uuid,
       'bc000000-0000-4000-8000-00000000000c',
       'b1000000-0000-4000-8000-00000000000a', 'client', 'm' || n,
       case when n in (3,4)
            then timestamptz '2026-08-10 12:00:00+00'
            else timestamptz '2026-08-10 12:00:00+00' + (n || ' minutes')::interval
       end
from generate_series(1,7) n;

-- ---------------------------------------------------------------------------
-- 1. Primeira página e cursor
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-00000000000a', true);
set local role authenticated;

select results_eq(
  $$select body from public.fetch_conversation_messages_page(
      'bc000000-0000-4000-8000-00000000000c', null, null, 3)$$,
  $$values ('m7'),('m6'),('m5')$$,
  'a primeira pagina traz as mais recentes, da mais nova para tras');

-- O cursor aponta para m5 (a mais antiga da primeira página).
select results_eq(
  $$select body from public.fetch_conversation_messages_page(
      'bc000000-0000-4000-8000-00000000000c',
      timestamptz '2026-08-10 12:05:00+00',
      'bd000000-0000-4000-8000-000000000005', 3)$$,
  $$values ('m2'),('m1'),('m4')$$,
  'a segunda pagina continua exatamente de onde a primeira parou');

-- O EMPATE: cursor em m4 (12:00) não pode pular a m3 (também 12:00).
select results_eq(
  $$select body from public.fetch_conversation_messages_page(
      'bc000000-0000-4000-8000-00000000000c',
      timestamptz '2026-08-10 12:00:00+00',
      'bd000000-0000-4000-8000-000000000004', 3)$$,
  $$values ('m3')$$,
  'timestamp empatado nao pula mensagem: o id desempata');

select is(
  (select count(*)::int from public.fetch_conversation_messages_page(
      'bc000000-0000-4000-8000-00000000000c',
      timestamptz '2026-08-10 12:00:00+00',
      'bd000000-0000-4000-8000-000000000003', 3)),
  0,
  'depois da mais antiga nao vem nada');

-- Emenda completa: paginando de 3 em 3 a partir do topo, as 7 aparecem uma
-- vez cada, sem buraco e sem repetição.
select is(
  (with pagina1 as (
     select * from public.fetch_conversation_messages_page(
       'bc000000-0000-4000-8000-00000000000c', null, null, 3)
   ), pagina2 as (
     select * from public.fetch_conversation_messages_page(
       'bc000000-0000-4000-8000-00000000000c',
       (select min(created_at) from pagina1),
       (select id from pagina1 order by created_at asc, id asc limit 1), 3)
   ), pagina3 as (
     select * from public.fetch_conversation_messages_page(
       'bc000000-0000-4000-8000-00000000000c',
       (select min(created_at) from pagina2),
       (select id from pagina2 order by created_at asc, id asc limit 1), 3)
   )
   select count(distinct body)::int
   from (select body from pagina1 union all select body from pagina2
         union all select body from pagina3) tudo),
  7,
  'tres paginas emendadas cobrem as sete mensagens sem repetir nenhuma');

reset role;

-- ---------------------------------------------------------------------------
-- 2. A RLS continua sendo quem corta
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-00000000000b', true);
set local role authenticated;

select is(
  (select count(*)::int from public.fetch_conversation_messages_page(
      'bc000000-0000-4000-8000-00000000000c', null, null, 50)),
  0,
  'quem nao e da conversa recebe pagina VAZIA: invoker deixa a RLS decidir');

reset role;

set local role anon;
select throws_ok(
  $$select * from public.fetch_conversation_messages_page(
      'bc000000-0000-4000-8000-00000000000c', null, null, 50)$$,
  '42501',
  null,
  'anon nem executa a funcao');
reset role;

-- ---------------------------------------------------------------------------
-- 3. O teto duro do page_size
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-00000000000a', true);
set local role authenticated;

select is(
  (select count(*)::int from public.fetch_conversation_messages_page(
      'bc000000-0000-4000-8000-00000000000c', null, null, 999999)),
  7,
  'pedir um milhao devolve as 7 que existem');

-- Cursor pela metade (só o timestamp, sem id) é tratado como SEM cursor.
-- AQUI, antes do lote de fundo, os dois comportamentos divergem de verdade:
-- ignorado devolve as 7; virando filtro capenga devolveria só as 4 anteriores
-- a 12:03. Depois do lote os dois davam página cheia e a sabotagem não mordia.
select is(
  (select count(*)::int from public.fetch_conversation_messages_page(
      'bc000000-0000-4000-8000-00000000000c',
      timestamptz '2026-08-10 12:03:00+00', null, 50)),
  7,
  'cursor pela metade e ignorado em vez de virar filtro capenga');

reset role;

-- O TETO DE 200 precisa de mais de 200 mensagens para morder. Sem sessão no
-- insert de fundo: o teto de ENVIO (20260908120000) conta por remetente
-- logado, e montar cenário não é enviar mensagem.
select set_config('request.jwt.claim.sub', '', true);
insert into public.messages (conversation_id, sender_id, sender_type, body, created_at)
select 'bc000000-0000-4000-8000-00000000000c',
       'b1000000-0000-4000-8000-00000000000a', 'client', 'fundo ' || n,
       timestamptz '2026-08-09 00:00:00+00' + (n || ' seconds')::interval
from generate_series(1, 250) n;

select set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-00000000000a', true);
set local role authenticated;

select is(
  (select count(*)::int from public.fetch_conversation_messages_page(
      'bc000000-0000-4000-8000-00000000000c', null, null, 999999)),
  200,
  'com 257 mensagens na conversa, uma chamada nunca traz mais de 200');

select is(
  (select count(*)::int from public.fetch_conversation_messages_page(
      'bc000000-0000-4000-8000-00000000000c', null, null, -5)),
  1,
  'page_size negativo vira 1, e nao lista vazia nem erro');

select is(
  (select count(*)::int from public.fetch_conversation_messages_page(
      'bc000000-0000-4000-8000-00000000000c', null, null, null)),
  50,
  'page_size nulo cai no padrao de 50');

reset role;

select * from finish();
rollback;
