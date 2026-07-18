-- ---------------------------------------------------------------------------
-- Customizacao segura do perfil: identidade, telefone e ciclo do avatar
-- ---------------------------------------------------------------------------
-- `upsert_current_profile` ja preservava telefone quando o parametro era NULL,
-- mas tambem preservava quando o app enviava string vazia. Para a tela de
-- edicao, NULL continua significando "nao alterar" e string vazia passa a
-- significar "remover". O valor persistido e normalizado para 10/11 digitos.
-- CPF ja preenchido se torna imutavel tambem na RPC, nao apenas na interface.
--
-- Avatares usam nomes unicos. A URL deixa de aceitar UPDATE direto: uma RPC
-- valida o objeto na pasta do titular e deriva a origem do issuer assinado do
-- JWT. A customizacao consolida nome, telefone e avatar numa transacao de DB.
-- A policy DELETE na propria pasta permite limpar a foto anterior.
-- ---------------------------------------------------------------------------

create or replace function public.upsert_current_profile(
  full_name_value text,
  cpf_value text default null,
  phone_value text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  profile_id_value uuid := auth.uid();
  auth_email_value text;
  clean_cpf_value text;
  clean_phone_value text;
  current_cpf_value text;
  normalized_name_value text;
  normalized_initials_value text;
  name_parts text[];
begin
  if profile_id_value is null then
    raise exception 'User must be authenticated';
  end if;

  normalized_name_value := nullif(
    btrim(
      regexp_replace(
        coalesce(full_name_value, ''),
        '[[:space:]]+',
        ' ',
        'g'
      )
    ),
    ''
  );

  if normalized_name_value is null then
    raise exception 'Full name is required';
  end if;

  clean_cpf_value := nullif(
    regexp_replace(coalesce(cpf_value, ''), '[^0-9]', '', 'g'),
    ''
  );

  if clean_cpf_value is not null and not public.is_valid_cpf(clean_cpf_value) then
    raise exception 'Invalid CPF';
  end if;

  select profile.cpf
  into current_cpf_value
  from public.profiles profile
  where profile.id = profile_id_value
  for update;

  -- Depois de definido, o CPF e uma ancora de identidade e nao pode ser
  -- substituido por uma chamada direta. O mesmo valor continua idempotente e
  -- um perfil incompleto ainda pode preencher o CPF pela primeira vez.
  if current_cpf_value is not null
     and clean_cpf_value is not null
     and clean_cpf_value <> current_cpf_value then
    raise exception 'CPF cannot be changed';
  end if;

  if clean_cpf_value is not null and exists (
    select 1
    from public.profiles other_profile
    where other_profile.cpf = clean_cpf_value
      and other_profile.id <> profile_id_value
  ) then
    raise exception 'CPF already registered';
  end if;

  if phone_value is not null
     and phone_value ~ '[^0-9[:space:]()+.\-]' then
    raise exception 'Invalid phone';
  end if;

  clean_phone_value := case
    when phone_value is null then null
    else nullif(regexp_replace(phone_value, '[^0-9]', '', 'g'), '')
  end;

  -- Autofill e agenda do celular frequentemente entregam +55. Aceita o
  -- codigo do Brasil, mas persiste apenas DDD + numero nacional.
  if length(clean_phone_value) in (12, 13)
     and clean_phone_value like '55%' then
    clean_phone_value := substring(clean_phone_value from 3);
  end if;

  if clean_phone_value is not null
     and length(clean_phone_value) not in (10, 11) then
    raise exception 'Invalid phone';
  end if;

  select nullif(trim(auth_user.email), '')
  into auth_email_value
  from auth.users auth_user
  where auth_user.id = profile_id_value;

  if not found or auth_email_value is null then
    raise exception 'Authenticated user was not found';
  end if;

  name_parts := regexp_split_to_array(normalized_name_value, '[[:space:]]+');
  normalized_initials_value := upper(
    left(name_parts[1], 1)
    || case
      when array_length(name_parts, 1) > 1
        then left(name_parts[array_upper(name_parts, 1)], 1)
      else ''
    end
  );

  insert into public.profiles (
    id,
    full_name,
    email,
    initials,
    cpf,
    phone
  )
  values (
    profile_id_value,
    normalized_name_value,
    auth_email_value,
    normalized_initials_value,
    clean_cpf_value,
    clean_phone_value
  )
  on conflict (id) do update
  set
    full_name = excluded.full_name,
    email = excluded.email,
    initials = excluded.initials,
    cpf = coalesce(excluded.cpf, public.profiles.cpf),
    phone = case
      when phone_value is null then public.profiles.phone
      else clean_phone_value
    end
  where public.profiles.deleted_at is null;

  if not found then
    raise exception 'Deleted profile cannot be restored';
  end if;
end;
$$;

revoke all on function public.upsert_current_profile(text, text, text)
from public, anon;

grant execute on function public.upsert_current_profile(text, text, text)
to authenticated;

-- A URL do avatar nao pode mais ser escrita diretamente pelo cliente: ela e
-- derivada do issuer assinado do JWT e de um objeto que existe na pasta do
-- proprio usuario. Isso impede apontar o avatar para um host externo de
-- rastreamento e contornar a validacao/upload do bucket.
create or replace function public.set_current_profile_avatar(
  storage_path_value text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  profile_id_value uuid := auth.uid();
  normalized_path_value text := nullif(btrim(storage_path_value), '');
  issuer_value text;
  api_base_url_value text;
  avatar_url_value text;
begin
  if profile_id_value is null then
    raise exception 'User must be authenticated';
  end if;

  if normalized_path_value is null then
    avatar_url_value := null;
  else
    if normalized_path_value !~ '^[0-9a-fA-F-]{36}/[A-Za-z0-9._-]{1,240}$'
       or (storage.foldername(normalized_path_value))[1]
          <> profile_id_value::text
       or not exists (
         select 1
         from storage.objects stored_object
         where stored_object.bucket_id = 'profile-avatars'
           and stored_object.name = normalized_path_value
       ) then
      raise exception 'Invalid avatar path';
    end if;

    issuer_value := nullif(auth.jwt() ->> 'iss', '');
    if issuer_value is null
       or issuer_value !~ '^https?://[^/]+/auth/v1/?$' then
      raise exception 'Authenticated issuer was not found';
    end if;

    api_base_url_value := regexp_replace(
      issuer_value,
      '/auth/v1/?$',
      '',
      'i'
    );
    avatar_url_value := api_base_url_value
      || '/storage/v1/object/public/profile-avatars/'
      || normalized_path_value;
  end if;

  update public.profiles profile
  set avatar_url = avatar_url_value
  where profile.id = profile_id_value
    and profile.deleted_at is null;

  if not found then
    raise exception 'Active profile was not found';
  end if;

  return avatar_url_value;
end;
$$;

revoke all on function public.set_current_profile_avatar(text)
from public, anon;

grant execute on function public.set_current_profile_avatar(text)
to authenticated;

-- Nome, telefone e referencia do avatar mudam em uma unica transacao no
-- banco. O blob novo e enviado antes pelo Storage; se esta RPC falhar, o app
-- remove esse blob como rollback best-effort.
create or replace function public.update_current_profile_customization(
  full_name_value text,
  phone_value text,
  avatar_action_value text default 'preserve',
  avatar_storage_path_value text default null
)
returns table (
  id uuid,
  full_name text,
  email text,
  initials text,
  cpf text,
  phone text,
  avatar_url text,
  lawyer_status public.lawyer_status,
  member_since date,
  created_at timestamptz,
  updated_at timestamptz,
  deleted_at timestamptz,
  deleted_display_name text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  profile_id_value uuid := auth.uid();
  normalized_action_value text := lower(btrim(avatar_action_value));
begin
  if normalized_action_value not in ('preserve', 'replace', 'remove') then
    raise exception 'Invalid avatar action';
  end if;
  if normalized_action_value = 'replace'
     and nullif(btrim(avatar_storage_path_value), '') is null then
    raise exception 'Avatar path is required';
  end if;
  if normalized_action_value <> 'replace'
     and nullif(btrim(avatar_storage_path_value), '') is not null then
    raise exception 'Avatar path is not allowed for this action';
  end if;

  perform public.upsert_current_profile(full_name_value, null, phone_value);

  if normalized_action_value = 'replace' then
    perform public.set_current_profile_avatar(avatar_storage_path_value);
  elsif normalized_action_value = 'remove' then
    perform public.set_current_profile_avatar(null);
  end if;

  return query
  select
    profile.id,
    profile.full_name,
    profile.email,
    profile.initials,
    profile.cpf,
    profile.phone,
    profile.avatar_url,
    profile.lawyer_status,
    profile.member_since,
    profile.created_at,
    profile.updated_at,
    profile.deleted_at,
    profile.deleted_display_name
  from public.profiles profile
  where profile.id = profile_id_value
    and profile.deleted_at is null;
end;
$$;

revoke all on function public.update_current_profile_customization(
  text, text, text, text
)
from public, anon;

grant execute on function public.update_current_profile_customization(
  text, text, text, text
)
to authenticated;

revoke update (avatar_url) on public.profiles from authenticated;

update storage.buckets
set
  file_size_limit = 10485760,
  allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp']
where id = 'profile-avatars';

drop policy if exists "profile_avatars_own_folder_delete" on storage.objects;
create policy "profile_avatars_own_folder_delete"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'profile-avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

select pg_notify('pgrst', 'reload schema');
