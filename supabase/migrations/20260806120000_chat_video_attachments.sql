-- Anexo de VIDEO no chat, e o caminho para foto/video renderizarem no balao.
--
-- Antes: message_attachments.kind aceitava so 'image' e 'document', o RPC
-- recusava qualquer MIME de video e o bucket nao listava video/* — ou seja,
-- video nao era "anexo que aparece como arquivo", era anexo IMPOSSIVEL de
-- enviar. Esta migration abre o tipo no banco; a renderizacao inline (foto e
-- video dentro do balao, estilo WhatsApp) e a parte do app.
--
-- TETOS POR TIPO (o RPC continua sendo quem manda):
--   imagem    5 MB   (inalterado)
--   documento 10 MB  (inalterado)
--   video     25 MB  (novo)
--
-- CONSEQUENCIA no bucket: file_size_limit e por BUCKET, nao por tipo. Subir
-- para 25 MB significa que um upload direto pela Storage API (fora do app)
-- pode gravar um objeto de 25 MB mesmo sendo PDF. Enquanto nao houver linha em
-- message_attachments, esse objeto e ilegivel para todo mundo (a policy de
-- leitura exige a linha) — o custo e espaco desperdicado, nao vazamento. O
-- patch_041 tinha alinhado bucket e RPC para nao existir essa folga; ela volta
-- em 15 MB e so fecha de vez com limpeza de orfaos.
--
-- MAS o teto do bucket sozinho nao bastava, e e por isso que esta migration
-- tambem revoga INSERT em message_attachments (secao 3). O grant do baseline
-- dava INSERT direto a `authenticated`, e a policy so exige dono, acesso a
-- conversa e pasta propria — nada de MIME, nada de tamanho, nada de coerencia
-- entre kind e mime_type. Ou seja: o RPC NAO era o unico caminho que cria a
-- linha, e quem inserisse na mao escapava de todas as validacoes dele. Com o
-- CHECK da tabela subindo de 10 para 25 MB, esse desvio passaria a permitir
-- ligar um objeto de 25 MB como se fosse foto (teto real do RPC: 5 MB). Sem o
-- revoke, subir o CHECK seria afrouxar o teto de foto e de documento junto.

-- ---------------------------------------------------------------------------
-- 1. Tabela: 'video' no CHECK de kind e teto de tamanho no teto do maior tipo
-- ---------------------------------------------------------------------------

alter table public.message_attachments
  drop constraint if exists message_attachments_kind_check;

alter table public.message_attachments
  add constraint message_attachments_kind_check
  check (kind in ('image', 'document', 'video'));

alter table public.message_attachments
  drop constraint if exists message_attachments_file_size_bytes_check;

alter table public.message_attachments
  add constraint message_attachments_file_size_bytes_check
  check (file_size_bytes > 0 and file_size_bytes <= 26214400);

-- ---------------------------------------------------------------------------
-- 2. RPC: ramo de video. Corpo VERBATIM do que esta em producao — muda so a
--    lista de kinds e o bloco novo. (O corpo em producao ja aceitava
--    image/heic e image/heif, que nenhuma migration do repositorio havia
--    gravado; preservado aqui, o que tambem traz o repositorio de volta ao
--    que o banco realmente executa.)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.send_chat_attachment(conversation_id_value uuid, file_name_value text, mime_type_value text, file_size_bytes_value bigint, storage_path_value text, kind_value text, sender_type_value text)
 RETURNS TABLE(id uuid, conversation_id uuid, sender_id uuid, sender_type text, body text, metadata jsonb, read_at timestamp with time zone, created_at timestamp with time zone, attachment_id uuid, file_name text, mime_type text, file_size_bytes bigint, storage_path text, kind text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  clean_file_name text;
  normalized_mime text;
  normalized_kind text;
  clean_storage_path text;
  message_body text;
  message_id_value uuid;
  attachment_id_value uuid;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  if not public.can_access_conversation(conversation_id_value) then
    raise exception 'User cannot access this conversation';
  end if;

  clean_file_name := nullif(trim(coalesce(file_name_value, '')), '');
  normalized_mime := lower(trim(coalesce(mime_type_value, '')));
  normalized_kind := lower(trim(coalesce(kind_value, '')));
  clean_storage_path := nullif(trim(coalesce(storage_path_value, '')), '');

  if clean_file_name is null or clean_storage_path is null then
    raise exception 'Attachment file name and storage path are required';
  end if;

  if clean_storage_path not like auth.uid()::text || '/%' then
    raise exception 'Attachment storage path must be in the current user folder';
  end if;

  if coalesce(sender_type_value, '') not in ('client', 'lawyer') then
    raise exception 'Invalid message sender type';
  end if;

  if normalized_kind not in ('image', 'document', 'video') then
    raise exception 'Invalid attachment kind';
  end if;

  if coalesce(file_size_bytes_value, 0) <= 0 then
    raise exception 'Attachment file is empty';
  end if;

  if normalized_kind = 'image' then
    if normalized_mime not in (
      'image/jpeg',
      'image/png',
      'image/webp',
      'image/heic',
      'image/heif'
    ) then
      raise exception 'Unsupported image type';
    end if;
    if file_size_bytes_value > 5242880 then
      raise exception 'Image attachment exceeds 5 MB';
    end if;
    message_body := 'Foto enviada';
  elsif normalized_kind = 'video' then
    -- Só mp4 e quicktime (.mov): sao os dois que a camera de Android e iOS
    -- produzem E que os dois sistemas conseguem tocar. webm ficou de fora de
    -- proposito — o iOS nao reproduz, e um video enviado pela web viraria
    -- anexo morto no celular de quem recebe.
    if normalized_mime not in ('video/mp4', 'video/quicktime') then
      raise exception 'Unsupported video type';
    end if;
    -- 25 MB: cerca de 30s de 1080p. Nem image_picker no Android nem no iOS
    -- comprime video (o plugin usa QualityTypeHigh e so copia o arquivo), o
    -- que faz deste teto o unico freio entre a galeria do usuario e a conta
    -- de Storage.
    if file_size_bytes_value > 26214400 then
      raise exception 'Video attachment exceeds 25 MB';
    end if;
    message_body := 'Vídeo enviado';
  else
    if normalized_mime not in (
      'application/pdf',
      'application/msword',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
    ) then
      raise exception 'Unsupported document type';
    end if;
    if file_size_bytes_value > 10485760 then
      raise exception 'Document attachment exceeds 10 MB';
    end if;
    message_body := 'Documento enviado';
  end if;

  insert into public.messages (
    conversation_id,
    sender_id,
    sender_type,
    body,
    metadata
  )
  values (
    conversation_id_value,
    auth.uid(),
    sender_type_value::public.message_sender_type,
    message_body,
    jsonb_build_object(
      'type', 'chat_attachment',
      'attachment_kind', normalized_kind,
      'file_name', clean_file_name,
      'mime_type', normalized_mime,
      'file_size_bytes', file_size_bytes_value,
      'storage_path', clean_storage_path
    )
  )
  returning messages.id into message_id_value;

  insert into public.message_attachments (
    message_id,
    conversation_id,
    uploaded_by,
    file_name,
    mime_type,
    file_size_bytes,
    storage_path,
    kind
  )
  values (
    message_id_value,
    conversation_id_value,
    auth.uid(),
    clean_file_name,
    normalized_mime,
    file_size_bytes_value,
    clean_storage_path,
    normalized_kind
  )
  returning message_attachments.id into attachment_id_value;

  update public.messages as msg
  set metadata = msg.metadata || jsonb_build_object('attachment_id', attachment_id_value)
  where msg.id = message_id_value;

  return query
  select
    m.id,
    m.conversation_id,
    m.sender_id,
    m.sender_type::text,
    m.body,
    m.metadata,
    m.read_at,
    m.created_at,
    ma.id,
    ma.file_name,
    ma.mime_type,
    ma.file_size_bytes,
    ma.storage_path,
    ma.kind
  from public.messages m
  join public.message_attachments ma
    on ma.message_id = m.id
  where m.id = message_id_value;
end;
$function$;

-- create or replace preserva os grants; o revoke/grant fica explicito para a
-- migration continuar correta se um dia ela rodar num banco novo.
revoke all on function public.send_chat_attachment(
  uuid, text, text, bigint, text, text, text
)
from public, anon;

grant execute on function public.send_chat_attachment(
  uuid, text, text, bigint, text, text, text
)
to authenticated;

-- ---------------------------------------------------------------------------
-- 3. O RPC passa a ser MESMO o unico caminho que cria a linha do anexo.
--
--    send_chat_attachment e SECURITY DEFINER com owner postgres, entao segue
--    inserindo normalmente — o revoke atinge so o INSERT direto do cliente.
--    O trigger message_attachments_block_guard (20260801120000) fica onde
--    esta: defesa em profundidade nao se remove porque a porta da frente
--    fechou.
-- ---------------------------------------------------------------------------

revoke insert on public.message_attachments from authenticated;

-- ---------------------------------------------------------------------------
-- 4. Bucket: sem os MIMEs de video aqui, o upload morre ANTES do RPC.
-- ---------------------------------------------------------------------------

update storage.buckets
set
  file_size_limit = 26214400,
  allowed_mime_types = array[
    'image/jpeg',
    'image/png',
    'image/webp',
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'video/mp4',
    'video/quicktime'
  ]
where id = 'chat-attachments';

notify pgrst, 'reload schema';
