-- Testes da migration 20260806120000: anexo de vídeo no chat.
--
-- O ponto central não é "vídeo passa" — é que os tetos dos OUTROS tipos não
-- subiram junto. O CHECK da tabela e o limite do bucket tiveram que ir a 25 MB
-- (são globais); quem continua segurando 5 MB para foto e 10 MB para documento
-- é o RPC. Se um dia alguém simplificar aquele if/elsif, os dois testes de
-- REGRESSÃO abaixo caem.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(19);

-- ---------------------------------------------------------------------------
-- Fixtures: cliente e advogada aprovada, com conversa pelo caminho oficial
-- ---------------------------------------------------------------------------

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('c1000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'cliente@video.test', '', now(), '{}'::jsonb,
   '{"full_name":"Cliente Video"}'::jsonb, now(), now()),
  ('c1000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'advogada@video.test', '', now(), '{}'::jsonb,
   '{"full_name":"Advogada Video"}'::jsonb, now(), now());

update public.profiles set lawyer_status = 'approved'
where id = 'c1000000-0000-0000-0000-000000000002';

insert into public.lawyer_profiles (id, oab_number, oab_state, primary_area, practice_areas)
values ('c1000000-0000-0000-0000-000000000002', '727272', 'RS',
        'Direito Cível', array['Direito Cível']);

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);
set local role authenticated;

create temporary table t_video (name text primary key, id uuid);
insert into t_video
select 'conv', public.start_or_get_lawyer_conversation(
  'c1000000-0000-0000-0000-000000000002', 'oi');

-- ---------------------------------------------------------------------------
-- RPC: o caminho novo
-- ---------------------------------------------------------------------------

select is(
  (select kind from public.send_chat_attachment(
    (select id from t_video where name = 'conv'),
    'obra.mp4', 'video/mp4', 4194304,
    'c1000000-0000-0000-0000-000000000001/obra.mp4', 'video', 'client')),
  'video',
  'mp4 vira anexo kind=video');

select is(
  (select body from public.send_chat_attachment(
    (select id from t_video where name = 'conv'),
    'obra2.mp4', 'video/mp4', 4194304,
    'c1000000-0000-0000-0000-000000000001/obra2.mp4', 'video', 'client')),
  'Vídeo enviado',
  'o corpo da mensagem distingue video de foto (vira preview da lista)');

-- O app decide o balão pelo metadata quando a mensagem chega por realtime,
-- antes de consultar message_attachments — se attachment_kind vier errado,
-- o vídeo aparece como documento por um instante.
select is(
  (select metadata ->> 'attachment_kind' from public.send_chat_attachment(
    (select id from t_video where name = 'conv'),
    'obra3.mp4', 'video/mp4', 4194304,
    'c1000000-0000-0000-0000-000000000001/obra3.mp4', 'video', 'client')),
  'video',
  'metadata carrega attachment_kind=video');

-- .mov é o que a câmera do iPhone entrega (image_picker copia o arquivo sem
-- converter): recusar quicktime tiraria o iOS inteiro da feature.
select lives_ok(
  $$select public.send_chat_attachment(
      (select id from t_video where name = 'conv'),
      'IMG_0042.MOV', 'video/quicktime', 8388608,
      'c1000000-0000-0000-0000-000000000001/IMG_0042.MOV', 'video', 'client')$$,
  'quicktime (.mov do iPhone) e aceito');

select throws_ok(
  $$select public.send_chat_attachment(
      (select id from t_video where name = 'conv'),
      'clipe.webm', 'video/webm', 1048576,
      'c1000000-0000-0000-0000-000000000001/clipe.webm', 'video', 'client')$$,
  'Unsupported video type',
  'webm e recusado (iOS nao reproduz)');

select throws_ok(
  $$select public.send_chat_attachment(
      (select id from t_video where name = 'conv'),
      'longo.mp4', 'video/mp4', 26214401,
      'c1000000-0000-0000-0000-000000000001/longo.mp4', 'video', 'client')$$,
  'Video attachment exceeds 25 MB',
  'video acima de 25 MB e recusado');

select lives_ok(
  $$select public.send_chat_attachment(
      (select id from t_video where name = 'conv'),
      'limite.mp4', 'video/mp4', 26214400,
      'c1000000-0000-0000-0000-000000000001/limite.mp4', 'video', 'client')$$,
  'exatamente 25 MB passa (o teto e inclusivo)');

-- ---------------------------------------------------------------------------
-- REGRESSÃO: os tetos de foto e documento NÃO subiram junto com o do bucket
-- ---------------------------------------------------------------------------

select throws_ok(
  $$select public.send_chat_attachment(
      (select id from t_video where name = 'conv'),
      'enorme.jpg', 'image/jpeg', 5242881,
      'c1000000-0000-0000-0000-000000000001/enorme.jpg', 'image', 'client')$$,
  'Image attachment exceeds 5 MB',
  'REGRESSAO: foto continua limitada a 5 MB');

select throws_ok(
  $$select public.send_chat_attachment(
      (select id from t_video where name = 'conv'),
      'enorme.pdf', 'application/pdf', 10485761,
      'c1000000-0000-0000-0000-000000000001/enorme.pdf', 'document', 'client')$$,
  'Document attachment exceeds 10 MB',
  'REGRESSAO: documento continua limitado a 10 MB');

select throws_ok(
  $$select public.send_chat_attachment(
      (select id from t_video where name = 'conv'),
      'audio.mp3', 'audio/mpeg', 1048576,
      'c1000000-0000-0000-0000-000000000001/audio.mp3', 'audio', 'client')$$,
  'Invalid attachment kind',
  'kind fora dos tres continua recusado');

-- Os outros dois tipos continuam ENTRANDO: a migration reemite o corpo inteiro
-- do RPC, então uma vírgula perdida na lista de MIME de documento derrubaria
-- .docx para todo mundo sem nenhum teste de vídeo reclamar.
select is(
  (select kind from public.send_chat_attachment(
    (select id from t_video where name = 'conv'),
    'peticao.docx',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    204800, 'c1000000-0000-0000-0000-000000000001/peticao.docx',
    'document', 'client')),
  'document',
  'REGRESSAO: docx continua sendo aceito');

select is(
  (select kind from public.send_chat_attachment(
    (select id from t_video where name = 'conv'),
    'foto.jpg', 'image/jpeg', 204800,
    'c1000000-0000-0000-0000-000000000001/foto.jpg', 'image', 'client')),
  'image',
  'REGRESSAO: foto continua sendo aceita');

select is(
  (select body from public.send_chat_attachment(
    (select id from t_video where name = 'conv'),
    'contrato.pdf', 'application/pdf', 204800,
    'c1000000-0000-0000-0000-000000000001/contrato.pdf', 'document', 'client')),
  'Documento enviado',
  'REGRESSAO: pdf continua aceito e com o corpo de sempre');

-- ---------------------------------------------------------------------------
-- INSERT direto: fechado, senão o CHECK de 25 MB viraria o teto real de TODOS
-- ---------------------------------------------------------------------------

reset role;

select ok(
  not has_table_privilege('authenticated', 'public.message_attachments',
    'insert'),
  'authenticated NAO insere anexo direto (so pela RPC)');

-- ---------------------------------------------------------------------------
-- CHECK da tabela: o teto novo é o do maior tipo, não "sem teto"
-- ---------------------------------------------------------------------------


insert into t_video
select 'msg', id from public.messages
where conversation_id = (select id from t_video where name = 'conv')
  and body = 'oi'
limit 1;

select throws_ok(
  $$insert into public.message_attachments
      (message_id, conversation_id, uploaded_by, file_name, mime_type,
       file_size_bytes, storage_path, kind)
    values ((select id from t_video where name = 'msg'),
            (select id from t_video where name = 'conv'),
            'c1000000-0000-0000-0000-000000000001', 'gigante.mp4',
            'video/mp4', 26214401,
            'c1000000-0000-0000-0000-000000000001/gigante.mp4', 'video')$$,
  '23514', null,
  'CHECK da tabela recusa acima de 25 MB');

select throws_ok(
  $$insert into public.message_attachments
      (message_id, conversation_id, uploaded_by, file_name, mime_type,
       file_size_bytes, storage_path, kind)
    values ((select id from t_video where name = 'msg'),
            (select id from t_video where name = 'conv'),
            'c1000000-0000-0000-0000-000000000001', 'audio.mp3',
            'audio/mpeg', 1024,
            'c1000000-0000-0000-0000-000000000001/audio.mp3', 'audio')$$,
  '23514', null,
  'CHECK de kind so aceita image/document/video');

-- ---------------------------------------------------------------------------
-- Bucket: sem os MIMEs aqui o upload morre antes de chegar ao RPC
-- ---------------------------------------------------------------------------

-- A lista INTEIRA, não só os dois tipos novos: a migration REESCREVE o array,
-- então um tipo antigo que caia fora na reescrita passaria despercebido por
-- uma asserção que só olhasse vídeo — e toda foto PNG começaria a ser recusada
-- pelo Storage, antes de o RPC ser sequer chamado.
select results_eq(
  $$select unnest(allowed_mime_types) from storage.buckets
    where id = 'chat-attachments' order by 1$$,
  $$values ('application/msword'),
           ('application/pdf'),
           ('application/vnd.openxmlformats-officedocument.wordprocessingml.document'),
           ('image/jpeg'),
           ('image/png'),
           ('image/webp'),
           ('video/mp4'),
           ('video/quicktime')$$,
  'bucket aceita exatamente os oito tipos esperados');

select is(
  (select file_size_limit from storage.buckets where id = 'chat-attachments'),
  26214400::bigint,
  'bucket aceita ate 25 MB');

-- ---------------------------------------------------------------------------
-- Bloqueio: vídeo passa pelo mesmo guard das outras mensagens
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select public.block_conversation((select id from t_video where name = 'conv'));

select throws_ok(
  $$select public.send_chat_attachment(
      (select id from t_video where name = 'conv'),
      'furada.mp4', 'video/mp4', 1048576,
      'c1000000-0000-0000-0000-000000000001/furada.mp4', 'video', 'client')$$,
  'conversation_blocked',
  'video nao fura conversa bloqueada');

select * from finish();
rollback;
