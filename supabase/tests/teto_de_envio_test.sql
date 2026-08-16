-- O teto de envio.
--
-- Abrir conversa era limitado a 20 por dia desde a 20260805150000. Despejar
-- mensagens DENTRO dela não era limitado por nada: a política de INSERT de
-- `messages` confere identidade e acesso, e só. Num produto onde o advogado
-- recebe cliente que não escolheu, isso é uma caixa de entrada aberta.
--
-- NOTA SOBRE O RELÓGIO: `now()` é o horário de início da TRANSAÇÃO, então
-- todas as linhas inseridas aqui nascem com o mesmo `created_at` e caem na
-- mesma janela de um minuto. Isso é bom para o teste (não é preciso esperar) e
-- é justamente por isso que o teto tem que ser alto o bastante para nenhum
-- lote legítimo de teste esbarrar nele.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(10);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('f1000000-0000-0000-0000-00000000000a','authenticated','authenticated','cliente@f.test','',now(),'{}','{"full_name":"Cliente Insistente"}',now(),now()),
  ('f1000000-0000-0000-0000-00000000000b','authenticated','authenticated','advogada@f.test','',now(),'{}','{"full_name":"Advogada Alvo"}',now(),now()),
  ('f1000000-0000-0000-0000-00000000000c','authenticated','authenticated','outro@f.test','',now(),'{}','{"full_name":"Outro Cliente"}',now(),now());

update public.profiles set lawyer_status = 'approved'
where id = 'f1000000-0000-0000-0000-00000000000b';

insert into public.lawyer_profiles
  (id, oab_number, oab_state, primary_area, practice_areas, approved_at)
values
  ('f1000000-0000-0000-0000-00000000000b','717171','RS','Direito Cível',
   array['Direito Cível'], now());

insert into public.conversations (id, type, client_id, lawyer_id, title)
values
  ('fc000000-0000-0000-0000-000000000001','client_firm',
   'f1000000-0000-0000-0000-00000000000a','f1000000-0000-0000-0000-00000000000b',
   'Conversa Um'),
  ('fc000000-0000-0000-0000-000000000002','client_firm',
   'f1000000-0000-0000-0000-00000000000c','f1000000-0000-0000-0000-00000000000b',
   'Conversa Dois');

-- ---------------------------------------------------------------------------
-- 1. Conversar normalmente não esbarra em nada
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-00000000000a', true);
set local role authenticated;

select lives_ok(
  $$insert into public.messages (conversation_id, sender_id, sender_type, body)
    select 'fc000000-0000-0000-0000-000000000001',
           'f1000000-0000-0000-0000-00000000000a','client','oi ' || n
    from generate_series(1, 30) n$$,
  'trinta mensagens seguidas passam: o teto e o limite, e nao o comeco dele');

-- ---------------------------------------------------------------------------
-- 2. A trigésima primeira, no mesmo minuto, é recusada
-- ---------------------------------------------------------------------------
--
-- Ninguém digita trinta mensagens em um minuto. Um script digita trinta mil, e
-- é ele que este número existe para parar.
select throws_ok(
  $$insert into public.messages (conversation_id, sender_id, sender_type, body)
    values ('fc000000-0000-0000-0000-000000000001',
            'f1000000-0000-0000-0000-00000000000a','client','a trigesima primeira')$$,
  'Too many messages. Try again later',
  'a trigesima primeira no mesmo minuto e recusada');

-- E TROCAR DE CONVERSA NÃO ZERA O CONTADOR: o teto é da pessoa, não do
-- assunto. Se fosse por conversa, bastaria abrir outra para seguir despejando.
select throws_ok(
  $$insert into public.messages (conversation_id, sender_id, sender_type, body)
    values ('fc000000-0000-0000-0000-000000000002',
            'f1000000-0000-0000-0000-00000000000a','client','mudei de conversa')$$,
  'Too many messages. Try again later',
  'e mudar de conversa nao devolve cota');

reset role;

-- ---------------------------------------------------------------------------
-- 3. O teto é de QUEM ENVIA, e não da conversa nem do destinatário
-- ---------------------------------------------------------------------------
--
-- A advogada precisa poder responder mesmo com o cliente no teto. Um limite
-- que calasse os dois lados puniria a vítima junto com quem inunda.
select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-00000000000b', true);
set local role authenticated;

select lives_ok(
  $$insert into public.messages (conversation_id, sender_id, sender_type, body)
    values ('fc000000-0000-0000-0000-000000000001',
            'f1000000-0000-0000-0000-00000000000b','lawyer','consigo responder')$$,
  'a advogada responde normalmente, mesmo com o cliente no teto');

reset role;

select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-00000000000c', true);
set local role authenticated;

select lives_ok(
  $$insert into public.messages (conversation_id, sender_id, sender_type, body)
    values ('fc000000-0000-0000-0000-000000000002',
            'f1000000-0000-0000-0000-00000000000c','client','sou outra pessoa')$$,
  'e outro cliente nao herda o teto de ninguem');

reset role;

-- ---------------------------------------------------------------------------
-- 4. A janela da hora: andar devagar também não passa
-- ---------------------------------------------------------------------------
--
-- Sem esta segunda janela, 29 por minuto para sempre daria 41 mil mensagens
-- por dia sem esbarrar em nada. As linhas abaixo nascem no passado para provar
-- a janela larga sem o relógio precisar andar.
--
-- SEM SESSÃO de propósito: montar o cenário não é enviar mensagem, e com a
-- claim ainda posta o próprio teto barraria o lote na trigésima primeira linha.
select set_config('request.jwt.claim.sub', '', true);

insert into public.messages (conversation_id, sender_id, sender_type, body, created_at)
select 'fc000000-0000-0000-0000-000000000002',
       'f1000000-0000-0000-0000-00000000000c','client','antiga ' || n,
       now() - interval '30 minutes'
from generate_series(1, 600) n;

select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-00000000000c', true);
set local role authenticated;

select throws_ok(
  $$insert into public.messages (conversation_id, sender_id, sender_type, body)
    values ('fc000000-0000-0000-0000-000000000002',
            'f1000000-0000-0000-0000-00000000000c','client','mais uma')$$,
  'Too many messages. Try again later',
  'seiscentas na hora fecham a porta mesmo espalhadas no tempo');

reset role;

-- E o que saiu da janela não conta mais: o teto é uma janela deslizante, e não
-- uma punição permanente.
update public.messages
set created_at = now() - interval '2 hours'
where sender_id = 'f1000000-0000-0000-0000-00000000000c'
  and body like 'antiga%';

select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-00000000000c', true);
set local role authenticated;

select lives_ok(
  $$insert into public.messages (conversation_id, sender_id, sender_type, body)
    values ('fc000000-0000-0000-0000-000000000002',
            'f1000000-0000-0000-0000-00000000000c','client','passou a hora')$$,
  'passada a janela, a pessoa volta a enviar');

reset role;

-- ---------------------------------------------------------------------------
-- 5. Denunciar também tem teto
-- ---------------------------------------------------------------------------
--
-- O alvo de quem inunda a fila de denúncias não é a pessoa denunciada: é a
-- tela de revisão, que uma pessoa lê à mão. Afogá-la é a forma barata de
-- esconder a denúncia verdadeira.
-- Este teto JÁ EXISTIA, dentro de report_conversation (20260801120000), e o
-- que faltava era teste. Ele não aparece numa busca por "Too many" porque a
-- frase dele é outra, e foi assim que ele quase ganhou um gatilho duplicado
-- com o mesmo número em outro lugar. Guarda que ninguém testa é guarda que
-- alguém reescreve.
--
-- Denúncia não entra por insert direto: `authenticated` não tem grant em
-- user_reports, e o caminho é a RPC.
select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-00000000000a', true);
set local role authenticated;

select lives_ok(
  $$select public.report_conversation(
      'fc000000-0000-0000-0000-000000000001','spam','de novo', null)
    from generate_series(1, 10) n$$,
  'dez denuncias no dia passam');

select throws_ok(
  $$select public.report_conversation(
      'fc000000-0000-0000-0000-000000000001','spam','a decima primeira', null)$$,
  'Report limit reached',
  'a decima primeira denuncia do dia e recusada');

reset role;

select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-00000000000c', true);
set local role authenticated;

select lives_ok(
  $$select public.report_conversation(
      'fc000000-0000-0000-0000-000000000002','spam','primeira minha', null)$$,
  'e quem nunca denunciou segue podendo denunciar');

reset role;

select * from finish();
rollback;
