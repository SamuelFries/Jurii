-- Hotfix for patch_039.
--
-- Run after patch_039 if sending an attachment fails with:
-- column reference "metadata" is ambiguous.

create or replace function public.send_chat_attachment(
  conversation_id_value uuid,
  file_name_value text,
  mime_type_value text,
  file_size_bytes_value bigint,
  storage_path_value text,
  kind_value text,
  sender_type_value text
)
returns table (
  id uuid,
  conversation_id uuid,
  sender_id uuid,
  sender_type text,
  body text,
  metadata jsonb,
  read_at timestamptz,
  created_at timestamptz,
  attachment_id uuid,
  file_name text,
  mime_type text,
  file_size_bytes bigint,
  storage_path text,
  kind text
)
language plpgsql
security definer
set search_path = public
as $$
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

  if normalized_kind not in ('image', 'document') then
    raise exception 'Invalid attachment kind';
  end if;

  if coalesce(file_size_bytes_value, 0) <= 0 then
    raise exception 'Attachment file is empty';
  end if;

  if normalized_kind = 'image' then
    if normalized_mime not in ('image/jpeg', 'image/png', 'image/webp') then
      raise exception 'Unsupported image type';
    end if;
    if file_size_bytes_value > 5242880 then
      raise exception 'Image attachment exceeds 5 MB';
    end if;
    message_body := 'Foto enviada';
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
$$;

revoke all on function public.send_chat_attachment(
  uuid, text, text, bigint, text, text, text
)
from public, anon, authenticated;

grant execute on function public.send_chat_attachment(
  uuid, text, text, bigint, text, text, text
)
to authenticated;

select pg_notify('pgrst', 'reload schema');
