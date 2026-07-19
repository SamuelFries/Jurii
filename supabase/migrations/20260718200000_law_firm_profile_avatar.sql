-- ---------------------------------------------------------------------------
-- Foto publica e opcional do escritorio durante a verificacao
-- ---------------------------------------------------------------------------
-- A imagem e solicitada na etapa de documentos, mas nao e um documento
-- comprobatório: fica em bucket publico dedicado e so passa a representar o
-- escritorio depois da aprovacao administrativa. Verificacoes antigas sem
-- foto continuam validas e escritorios antigos continuam usando iniciais.
-- ---------------------------------------------------------------------------

alter table public.law_firm_verifications
  add column if not exists avatar_storage_path text;

alter table public.law_firms
  add column if not exists avatar_url text;

alter table public.law_firm_verifications
  drop constraint if exists law_firm_verifications_avatar_path_chk;

alter table public.law_firm_verifications
  add constraint law_firm_verifications_avatar_path_chk
  check (
    avatar_storage_path is null
    or (
      avatar_storage_path ~
        '^[0-9a-fA-F-]{36}/[0-9a-fA-F-]{36}/[A-Za-z0-9._-]{1,160}$'
      and split_part(avatar_storage_path, '/', 1) = owner_profile_id::text
      and split_part(avatar_storage_path, '/', 2) = id::text
    )
  );

alter table public.law_firms
  drop constraint if exists law_firms_avatar_url_chk;

alter table public.law_firms
  add constraint law_firms_avatar_url_chk
  check (
    avatar_url is null
    or avatar_url ~
      '^/storage/v1/object/public/law-firm-avatars/[0-9a-fA-F-]{36}/[0-9a-fA-F-]{36}/[A-Za-z0-9._-]{1,160}$'
  );

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'law-firm-avatars',
  'law-firm-avatars',
  true,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp']::text[]
)
on conflict (id) do update
set
  name = excluded.name,
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "law_firm_avatars_public_read" on storage.objects;
create policy "law_firm_avatars_public_read"
on storage.objects for select
to public
using (bucket_id = 'law-firm-avatars');

drop policy if exists "law_firm_avatars_pending_owner_insert"
on storage.objects;
create policy "law_firm_avatars_pending_owner_insert"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'law-firm-avatars'
  and name ~
    '^[0-9a-fA-F-]{36}/[0-9a-fA-F-]{36}/[A-Za-z0-9._-]{1,160}$'
  and (storage.foldername(name))[1] = auth.uid()::text
  and exists (
    select 1
    from public.law_firm_verifications verification
    where verification.id::text = (storage.foldername(name))[2]
      and verification.owner_profile_id = auth.uid()
      and verification.status in ('draft', 'pending')
  )
);

drop policy if exists "law_firm_avatars_unapproved_owner_delete"
on storage.objects;
create policy "law_firm_avatars_unapproved_owner_delete"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'law-firm-avatars'
  and name ~
    '^[0-9a-fA-F-]{36}/[0-9a-fA-F-]{36}/[A-Za-z0-9._-]{1,160}$'
  and (storage.foldername(name))[1] = auth.uid()::text
  and exists (
    select 1
    from public.law_firm_verifications verification
    where verification.id::text = (storage.foldername(name))[2]
      and verification.owner_profile_id = auth.uid()
      and verification.law_firm_id is null
      and verification.status in ('draft', 'pending', 'rejected')
  )
);

-- O cliente so pode criar/editar os campos declarados do formulario. Campos
-- de revisao, vinculacao e avatar ficam sob RPCs SECURITY DEFINER.
revoke insert, update on public.law_firm_verifications from authenticated;

grant insert (
  owner_profile_id,
  firm_name,
  cnpj,
  phone,
  email,
  address,
  practice_areas,
  status
)
on public.law_firm_verifications to authenticated;

grant update (
  firm_name,
  cnpj,
  phone,
  email,
  address,
  practice_areas,
  status
)
on public.law_firm_verifications to authenticated;

drop policy if exists "law_firm_verifications_insert_own"
on public.law_firm_verifications;
create policy "law_firm_verifications_insert_own"
on public.law_firm_verifications for insert
to authenticated
with check (
  owner_profile_id = auth.uid()
  and status in ('draft', 'pending')
  and law_firm_id is null
  and avatar_storage_path is null
  and reviewer_id is null
  and reviewed_at is null
  and rejection_reason is null
);

drop policy if exists "law_firm_verifications_update_own_pending"
on public.law_firm_verifications;
create policy "law_firm_verifications_update_own_pending"
on public.law_firm_verifications for update
to authenticated
using (
  owner_profile_id = auth.uid()
  and status in ('draft', 'pending')
)
with check (
  owner_profile_id = auth.uid()
  and status in ('draft', 'pending')
  and law_firm_id is null
  and reviewer_id is null
  and reviewed_at is null
  and rejection_reason is null
);

-- Retorna URL relativa somente para um objeto que pertence ao namespace da
-- verificacao e realmente existe no bucket correto.
create or replace function public.safe_law_firm_avatar_url(
  owner_profile_id_value uuid,
  verification_id_value uuid,
  storage_path_value text
)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when nullif(btrim(storage_path_value), '') is not null
      and storage_path_value ~
        '^[0-9a-fA-F-]{36}/[0-9a-fA-F-]{36}/[A-Za-z0-9._-]{1,160}$'
      and split_part(storage_path_value, '/', 1)
        = owner_profile_id_value::text
      and split_part(storage_path_value, '/', 2)
        = verification_id_value::text
      and exists (
        select 1
        from storage.objects stored_object
        where stored_object.bucket_id = 'law-firm-avatars'
          and stored_object.name = storage_path_value
      )
    then '/storage/v1/object/public/law-firm-avatars/' || storage_path_value
    else null
  end;
$$;

revoke all on function public.safe_law_firm_avatar_url(uuid, uuid, text)
from public, anon, authenticated;

create or replace function public.set_current_law_firm_verification_avatar(
  verification_id_value uuid,
  storage_path_value text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  profile_id_value uuid := auth.uid();
  verification_row public.law_firm_verifications%rowtype;
  normalized_path_value text := nullif(btrim(storage_path_value), '');
  avatar_url_value text;
begin
  if profile_id_value is null then
    raise exception 'User must be authenticated';
  end if;

  select *
  into verification_row
  from public.law_firm_verifications verification
  where verification.id = verification_id_value
  for update;

  if not found
     or verification_row.owner_profile_id <> profile_id_value then
    raise exception 'Law firm verification not found';
  end if;

  if verification_row.status not in ('draft', 'pending') then
    raise exception 'Law firm verification cannot be edited';
  end if;

  if normalized_path_value is null then
    avatar_url_value := null;
  else
    avatar_url_value := public.safe_law_firm_avatar_url(
      profile_id_value,
      verification_id_value,
      normalized_path_value
    );
    if avatar_url_value is null then
      raise exception 'Invalid law firm avatar path';
    end if;
  end if;

  update public.law_firm_verifications verification
  set avatar_storage_path = normalized_path_value
  where verification.id = verification_id_value;

  return avatar_url_value;
end;
$$;

revoke all on function public.set_current_law_firm_verification_avatar(uuid, text)
from public, anon, authenticated;

grant execute on function public.set_current_law_firm_verification_avatar(uuid, text)
to authenticated;

-- A aprovacao valida a referencia antes de criar/alterar o escritorio. A foto
-- e opcional; em atualizacao, ausencia preserva a foto publica ja existente.
create or replace function public.approve_law_firm_verification(
  verification_id_value uuid,
  reviewer_id_value uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  verification_row public.law_firm_verifications%rowtype;
  firm_id_value uuid;
  initials_value text;
  existing_member_id uuid;
  areas_value text[];
  specialty_value text;
  avatar_url_value text;
begin
  select *
  into verification_row
  from public.law_firm_verifications verification
  where verification.id = verification_id_value
  for update;

  if not found then
    raise exception 'Law firm verification not found: %',
      verification_id_value;
  end if;

  if verification_row.status <> 'pending' then
    raise exception 'Law firm verification is not pending';
  end if;

  if verification_row.avatar_storage_path is not null then
    avatar_url_value := public.safe_law_firm_avatar_url(
      verification_row.owner_profile_id,
      verification_row.id,
      verification_row.avatar_storage_path
    );
    if avatar_url_value is null then
      raise exception 'Invalid law firm avatar path';
    end if;
  end if;

  initials_value := upper(left(trim(verification_row.firm_name), 1));
  if initials_value is null or initials_value = '' then
    initials_value := 'E';
  end if;

  areas_value := coalesce(verification_row.practice_areas, '{}'::text[]);
  if cardinality(areas_value) = 0 then
    areas_value := array['Escritório jurídico'];
  end if;
  specialty_value := coalesce(areas_value[1], 'Escritório jurídico');

  if verification_row.law_firm_id is null then
    insert into public.law_firms (
      name,
      initials,
      specialty,
      practice_areas,
      rating,
      reviews_count,
      distance_label,
      avatar_type,
      avatar_url,
      phone,
      email,
      address,
      is_active
    )
    values (
      verification_row.firm_name,
      initials_value,
      specialty_value,
      areas_value,
      0,
      0,
      '',
      'purple',
      avatar_url_value,
      nullif(verification_row.phone, ''),
      nullif(verification_row.email, ''),
      nullif(verification_row.address, ''),
      true
    )
    returning id into firm_id_value;
  else
    firm_id_value := verification_row.law_firm_id;

    if not exists (
      select 1
      from public.law_firm_members member
      where member.law_firm_id = firm_id_value
        and member.profile_id = verification_row.owner_profile_id
        and member.status = 'active'
        and (
          member.member_role = 'owner'
          or 'owner' = any(coalesce(member.roles, '{}'::text[]))
        )
    ) then
      raise exception 'Verification owner cannot update linked law firm';
    end if;

    update public.law_firms firm
    set
      name = verification_row.firm_name,
      initials = initials_value,
      specialty = specialty_value,
      practice_areas = areas_value,
      phone = nullif(verification_row.phone, ''),
      email = nullif(verification_row.email, ''),
      address = nullif(verification_row.address, ''),
      avatar_type = 'purple',
      avatar_url = coalesce(avatar_url_value, firm.avatar_url),
      is_active = true,
      updated_at = now()
    where firm.id = firm_id_value;

    if not found then
      raise exception 'Linked law firm not found: %', firm_id_value;
    end if;
  end if;

  update public.law_firm_verifications verification
  set
    status = 'approved',
    law_firm_id = firm_id_value,
    reviewed_at = now(),
    reviewer_id = reviewer_id_value,
    rejection_reason = null
  where verification.id = verification_id_value;

  select member.id
  into existing_member_id
  from public.law_firm_members member
  where member.law_firm_id = firm_id_value
    and member.profile_id = verification_row.owner_profile_id
  limit 1;

  if existing_member_id is null then
    insert into public.law_firm_members (
      law_firm_id,
      profile_id,
      role,
      member_role,
      roles,
      status
    )
    values (
      firm_id_value,
      verification_row.owner_profile_id,
      'owner',
      'owner',
      array['owner']::text[],
      'active'
    );
  else
    update public.law_firm_members member
    set
      role = 'owner',
      member_role = 'owner',
      roles = public.normalize_law_firm_member_roles(
        coalesce(member.roles, '{}'::text[]) || array['owner']::text[]
      ),
      status = 'active'
    where member.id = existing_member_id;
  end if;

  return firm_id_value;
end;
$$;

revoke all on function public.approve_law_firm_verification(uuid, uuid)
from public, anon, authenticated;

grant execute on function public.approve_law_firm_verification(uuid, uuid)
to service_role;

-- O retorno ganha uma coluna; por isso a funcao precisa ser removida antes de
-- ser recriada. Clientes antigos ignoram a chave JSON adicional.
drop function if exists public.fetch_recommended_law_firms(int, text);

create function public.fetch_recommended_law_firms(
  limit_value int default 10,
  search_value text default null
)
returns table (
  id uuid,
  name text,
  initials text,
  rating numeric,
  distance_label text,
  specialty text,
  practice_areas text[],
  reviews_count int,
  avatar_type text,
  description text,
  phone text,
  email text,
  website_url text,
  address text,
  avatar_url text
)
language sql
stable
security definer
set search_path = public
as $$
  with search as (
    select nullif(public.normalize_practice_area_search(search_value), '') as q
  ),
  inferred as (
    select *
    from public.infer_legal_search_areas(search_value)
  ),
  base as (
    select
      firm.id,
      firm.name,
      firm.initials,
      firm.rating,
      firm.distance_label,
      firm.specialty,
      case
        when cardinality(firm.practice_areas) > 0 then firm.practice_areas
        else array[firm.specialty]
      end as practice_areas,
      firm.reviews_count,
      firm.avatar_type,
      firm.description,
      firm.phone,
      firm.email,
      firm.website_url,
      firm.address,
      firm.avatar_url,
      firm.created_at
    from public.law_firms firm
    where firm.is_active = true
  ),
  ranked as (
    select
      base.*,
      coalesce(
        public.normalize_practice_area_search(base.name)
          like '%' || search.q || '%'
        or public.normalize_practice_area_search(base.specialty)
          like '%' || search.q || '%'
        or exists (
          select 1
          from unnest(base.practice_areas) as areas(area_value)
          where public.normalize_practice_area_search(areas.area_value)
            like '%' || search.q || '%'
        ),
        false
      ) as direct_match,
      coalesce((
        select max(inferred.weight)
        from inferred
        where public.normalize_practice_area_search(base.specialty) =
          public.normalize_practice_area_search(inferred.practice_area)
          or exists (
            select 1
            from unnest(base.practice_areas) as areas(area_value)
            where public.normalize_practice_area_search(areas.area_value) =
              public.normalize_practice_area_search(inferred.practice_area)
          )
      ), 0) as intent_weight
    from base
    cross join search
  )
  select
    ranked.id,
    ranked.name,
    ranked.initials,
    ranked.rating,
    ranked.distance_label,
    ranked.specialty,
    ranked.practice_areas,
    ranked.reviews_count,
    ranked.avatar_type,
    ranked.description,
    ranked.phone,
    ranked.email,
    ranked.website_url,
    ranked.address,
    ranked.avatar_url
  from ranked
  cross join search
  where search.q is null
    or ranked.direct_match
    or ranked.intent_weight > 0
  order by
    ranked.intent_weight desc,
    ranked.direct_match desc,
    ranked.rating desc,
    ranked.created_at desc
  limit least(greatest(coalesce(limit_value, 10), 1), 30);
$$;

revoke all on function public.fetch_recommended_law_firms(int, text)
from public, anon, authenticated;

grant execute on function public.fetch_recommended_law_firms(int, text)
to authenticated;

-- A coluna avatar_url ja fazia parte dos contratos de conversa. Apenas o
-- ramo que representa o escritorio passa a usar a foto publica aprovada.
create or replace function public.fetch_conversation_for_current_user(
  conversation_id_value uuid
)
returns table (
  id uuid,
  type text,
  title text,
  initials text,
  avatar_url text,
  specialty text,
  last_message text,
  last_message_at timestamptz,
  law_firm_id uuid,
  client_id uuid,
  lawyer_id uuid
)
language sql
stable
security definer
set search_path = public
as $$
  select
    conversation.id,
    conversation.type::text,
    case
      when conversation.client_id = auth.uid()
           and conversation.law_firm_id is not null then
        coalesce(firm.name, conversation.title)
      when conversation.client_id = auth.uid()
           and conversation.lawyer_id is not null then
        public.profile_display_name(
          lawyer_profile.full_name,
          lawyer_profile.deleted_display_name,
          lawyer_profile.deleted_at
        )
      when conversation.client_id = auth.uid() then conversation.title
      else public.profile_display_name(
        client_profile.full_name,
        client_profile.deleted_display_name,
        client_profile.deleted_at
      )
    end as title,
    case
      when conversation.client_id = auth.uid()
           and conversation.law_firm_id is not null then
        coalesce(firm.initials, 'JE')
      when conversation.client_id = auth.uid()
           and conversation.lawyer_id is not null then
        coalesce(lawyer_profile.initials, 'AJ')
      when conversation.client_id = auth.uid() then
        upper(left(trim(conversation.title), 2))
      else coalesce(client_profile.initials, 'CL')
    end as initials,
    case
      when conversation.client_id = auth.uid()
           and conversation.law_firm_id is not null then firm.avatar_url
      when conversation.client_id = auth.uid()
           and conversation.lawyer_id is not null then
        public.safe_profile_avatar_url(
          lawyer_profile.id,
          lawyer_profile.avatar_url
        )
      when conversation.client_id = auth.uid() then null::text
      else public.safe_profile_avatar_url(
        client_profile.id,
        client_profile.avatar_url
      )
    end as avatar_url,
    coalesce(conversation.specialty, 'Atendimento jurídico') as specialty,
    coalesce(conversation.last_message, 'Nova conversa') as last_message,
    conversation.last_message_at,
    conversation.law_firm_id,
    conversation.client_id,
    conversation.lawyer_id
  from public.conversations conversation
  left join public.profiles client_profile
    on client_profile.id = conversation.client_id
  left join public.law_firms firm
    on firm.id = conversation.law_firm_id
  left join public.profiles lawyer_profile
    on lawyer_profile.id = conversation.lawyer_id
  where conversation.id = conversation_id_value
    and (
      conversation.client_id = auth.uid()
      or conversation.lawyer_id = auth.uid()
      or exists (
        select 1
        from public.law_firm_members member
        where member.law_firm_id = conversation.law_firm_id
          and member.profile_id = auth.uid()
          and member.status = 'active'
      )
      or (
        conversation.case_id is not null
        and public.can_access_case(conversation.case_id)
      )
    )
  limit 1;
$$;

revoke all on function public.fetch_conversation_for_current_user(uuid)
from public, anon;

grant execute on function public.fetch_conversation_for_current_user(uuid)
to authenticated;

create or replace function public.fetch_conversations_for_current_user(
  scope_value text,
  law_firm_id_value uuid default null
)
returns table (
  id uuid,
  type text,
  title text,
  initials text,
  avatar_url text,
  specialty text,
  last_message text,
  last_message_at timestamptz,
  law_firm_id uuid,
  client_id uuid,
  lawyer_id uuid
)
language sql
stable
security definer
set search_path = public
as $$
  with scoped_conversations as (
    select conversation.*
    from public.conversations conversation
    where auth.uid() is not null
      and exists (
        select 1
        from public.messages message
        where message.conversation_id = conversation.id
      )
      and (
        (
          scope_value = 'client'
          and conversation.client_id = auth.uid()
        )
        or (
          scope_value = 'lawyer'
          and conversation.type <> 'firm_internal'
          and (
            conversation.lawyer_id = auth.uid()
            or (
              conversation.case_id is not null
              and public.can_access_case(conversation.case_id)
            )
          )
        )
        or (
          scope_value = 'firmClient'
          and law_firm_id_value is not null
          and conversation.law_firm_id = law_firm_id_value
          and conversation.type <> 'firm_internal'
          and exists (
            select 1
            from public.law_firm_members member
            where member.law_firm_id = law_firm_id_value
              and member.profile_id = auth.uid()
              and member.status = 'active'
          )
        )
        or (
          scope_value = 'firmTeam'
          and law_firm_id_value is not null
          and conversation.law_firm_id = law_firm_id_value
          and conversation.type = 'firm_internal'
          and exists (
            select 1
            from public.law_firm_members member
            where member.law_firm_id = law_firm_id_value
              and member.profile_id = auth.uid()
              and member.status = 'active'
          )
        )
      )
  )
  select
    conversation.id,
    conversation.type::text,
    case
      when scope_value in ('lawyer', 'firmClient') then
        public.profile_display_name(
          client_profile.full_name,
          client_profile.deleted_display_name,
          client_profile.deleted_at
        )
      when scope_value = 'client'
           and conversation.law_firm_id is not null then
        coalesce(firm.name, conversation.title)
      when scope_value = 'client'
           and conversation.lawyer_id is not null then
        public.profile_display_name(
          lawyer_profile.full_name,
          lawyer_profile.deleted_display_name,
          lawyer_profile.deleted_at
        )
      else conversation.title
    end as title,
    case
      when scope_value in ('lawyer', 'firmClient') then
        coalesce(client_profile.initials, 'CL')
      when scope_value = 'client'
           and conversation.law_firm_id is not null then
        coalesce(firm.initials, 'JE')
      when scope_value = 'client'
           and conversation.lawyer_id is not null then
        coalesce(lawyer_profile.initials, 'AJ')
      else upper(left(trim(conversation.title), 2))
    end as initials,
    case
      when scope_value in ('lawyer', 'firmClient') then
        public.safe_profile_avatar_url(
          client_profile.id,
          client_profile.avatar_url
        )
      when scope_value = 'client'
           and conversation.law_firm_id is not null then firm.avatar_url
      when scope_value = 'client'
           and conversation.lawyer_id is not null then
        public.safe_profile_avatar_url(
          lawyer_profile.id,
          lawyer_profile.avatar_url
        )
      else null::text
    end as avatar_url,
    coalesce(conversation.specialty, 'Atendimento jurídico') as specialty,
    coalesce(conversation.last_message, 'Nova conversa') as last_message,
    conversation.last_message_at,
    conversation.law_firm_id,
    conversation.client_id,
    conversation.lawyer_id
  from scoped_conversations conversation
  left join public.profiles client_profile
    on client_profile.id = conversation.client_id
  left join public.law_firms firm
    on firm.id = conversation.law_firm_id
  left join public.profiles lawyer_profile
    on lawyer_profile.id = conversation.lawyer_id
  order by conversation.last_message_at desc nulls last,
    conversation.updated_at desc;
$$;

revoke all on function public.fetch_conversations_for_current_user(text, uuid)
from public, anon;

grant execute on function public.fetch_conversations_for_current_user(text, uuid)
to authenticated;

-- A exclusao de uma conta remove apenas avatares de verificacoes que ainda
-- nao viraram patrimonio de um escritorio aprovado. Fotos aprovadas sobrevivem
-- a transferencia de titularidade do escritorio.
create or replace function public.get_account_deletion_storage_paths(
  profile_id_value uuid
)
returns table (
  bucket_id text,
  storage_path text
)
language sql
stable
security definer
set search_path = ''
as $$
  with avatar_paths as (
    select split_part(
      split_part(
        split_part(
          profile.avatar_url,
          '/storage/v1/object/public/profile-avatars/',
          2
        ),
        '?',
        1
      ),
      '#',
      1
    ) as storage_path
    from public.profiles profile
    where profile.id = profile_id_value
      and position(
        '/storage/v1/object/public/profile-avatars/' in profile.avatar_url
      ) > 0
  )
  select
    'verification-documents'::text,
    document.storage_path
  from public.verification_documents document
  where document.user_id = profile_id_value
    and nullif(btrim(document.storage_path), '') is not null
    and document.storage_path like profile_id_value::text || '/%'

  union

  select
    'verification-documents'::text,
    document.storage_path
  from public.law_firm_verification_documents document
  where document.owner_profile_id = profile_id_value
    and nullif(btrim(document.storage_path), '') is not null
    and document.storage_path like profile_id_value::text || '/%'

  union

  select
    'profile-avatars'::text,
    avatar_paths.storage_path
  from avatar_paths
  where nullif(btrim(avatar_paths.storage_path), '') is not null
    and avatar_paths.storage_path like profile_id_value::text || '/%'

  union

  select
    'law-firm-avatars'::text,
    verification.avatar_storage_path
  from public.law_firm_verifications verification
  where verification.owner_profile_id = profile_id_value
    and verification.status <> 'approved'
    and verification.law_firm_id is null
    and nullif(btrim(verification.avatar_storage_path), '') is not null
    and verification.avatar_storage_path like profile_id_value::text || '/%';
$$;

revoke all on function public.get_account_deletion_storage_paths(uuid)
from public, anon, authenticated;

grant execute on function public.get_account_deletion_storage_paths(uuid)
to service_role;

select pg_notify('pgrst', 'reload schema');
