-- Propaga a foto publica de perfil pelas superficies que representam pessoas.
--
-- As RPCs continuam expondo apenas o retrato publico. Email, CPF e telefone
-- permanecem fora dos perfis de contraparte. Conversas com escritorios e o
-- canal interno da equipe retornam avatar nulo, pois law_firms ainda nao tem
-- um logo proprio e uma unica foto seria incorreta para varios remetentes.

-- Converte URLs antigas em um caminho publico relativo somente quando o objeto
-- realmente existe na pasta do titular. Isso neutraliza hosts externos que
-- podiam ter sido gravados antes do hardening de 18/07/2026.
create or replace function public.safe_profile_avatar_url(
  profile_id_value uuid,
  stored_url_value text
)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  with candidate as (
    select case
      when position(
        '/storage/v1/object/public/profile-avatars/' in stored_url_value
      ) > 0 then split_part(
        split_part(
          split_part(
            stored_url_value,
            '/storage/v1/object/public/profile-avatars/',
            2
          ),
          '?',
          1
        ),
        '#',
        1
      )
      else null
    end as storage_path
  )
  select case
    when candidate.storage_path
           ~ '^[0-9a-fA-F-]{36}/[A-Za-z0-9._-]{1,240}$'
      and (storage.foldername(candidate.storage_path))[1]
            = profile_id_value::text
      and exists (
        select 1
        from storage.objects stored_object
        where stored_object.bucket_id = 'profile-avatars'
          and stored_object.name = candidate.storage_path
      ) then '/storage/v1/object/public/profile-avatars/'
        || candidate.storage_path
    else null
  end
  from candidate;
$$;

revoke all on function public.safe_profile_avatar_url(uuid, text)
from public, anon, authenticated;

update public.profiles profile
set avatar_url = public.safe_profile_avatar_url(profile.id, profile.avatar_url)
where profile.avatar_url is not null;

-- Novas escritas tambem persistem somente o caminho relativo. O app o resolve
-- contra a URL configurada do proprio projeto, portanto nenhum host arbitrario
-- volta a entrar no banco.
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

    avatar_url_value := '/storage/v1/object/public/profile-avatars/'
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

drop function if exists public.fetch_recommended_lawyers(int, text);

create function public.fetch_recommended_lawyers(
  limit_value int default 6,
  search_value text default null
)
returns table (
  id uuid,
  full_name text,
  initials text,
  oab_number text,
  oab_state text,
  primary_area text,
  practice_areas text[],
  bio text,
  rating numeric,
  reviews_count int,
  avatar_type text,
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
      lp.id,
      coalesce(p.full_name, 'Advogado Jurii') as full_name,
      coalesce(p.initials, 'AJ') as initials,
      lp.oab_number,
      lp.oab_state::text as oab_state,
      lp.primary_area,
      case
        when cardinality(lp.practice_areas) > 0 then lp.practice_areas
        else array[lp.primary_area]
      end as practice_areas,
      coalesce(lp.bio, 'Perfil profissional verificado pela Jurii.') as bio,
      lp.rating,
      lp.reviews_count,
      'navy'::text as avatar_type,
      public.safe_profile_avatar_url(p.id, p.avatar_url) as avatar_url,
      lp.approved_at,
      lp.created_at
    from public.lawyer_profiles lp
    join public.profiles p on p.id = lp.id
    where lp.is_available = true
      and p.deleted_at is null
  ),
  ranked as (
    select
      base.*,
      coalesce(
        public.normalize_practice_area_search(base.full_name)
          like '%' || search.q || '%'
        or public.normalize_practice_area_search(base.primary_area)
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
        where public.normalize_practice_area_search(base.primary_area) =
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
    ranked.full_name,
    ranked.initials,
    ranked.oab_number,
    ranked.oab_state,
    ranked.primary_area,
    ranked.practice_areas,
    ranked.bio,
    ranked.rating,
    ranked.reviews_count,
    ranked.avatar_type,
    ranked.avatar_url
  from ranked
  cross join search
  where search.q is null
    or ranked.direct_match
    or ranked.intent_weight > 0
  order by
    ranked.intent_weight desc,
    ranked.direct_match desc,
    ranked.approved_at desc nulls last,
    ranked.created_at desc
  limit least(greatest(coalesce(limit_value, 6), 1), 20);
$$;

revoke all on function public.fetch_recommended_lawyers(int, text)
from public, anon;

grant execute on function public.fetch_recommended_lawyers(int, text)
to authenticated;

drop function if exists public.fetch_lawyer_public_profile(uuid);

create function public.fetch_lawyer_public_profile(
  lawyer_profile_id_value uuid
)
returns table (
  id uuid,
  full_name text,
  initials text,
  oab_number text,
  oab_state text,
  primary_area text,
  practice_areas text[],
  bio text,
  rating numeric,
  reviews_count int,
  avatar_type text,
  avatar_url text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    lp.id,
    coalesce(p.full_name, 'Advogado Jurii') as full_name,
    coalesce(p.initials, 'AJ') as initials,
    lp.oab_number,
    lp.oab_state::text as oab_state,
    lp.primary_area,
    case
      when cardinality(lp.practice_areas) > 0 then lp.practice_areas
      else array[lp.primary_area]
    end as practice_areas,
    coalesce(lp.bio, 'Perfil profissional verificado pela Jurii.') as bio,
    lp.rating,
    lp.reviews_count,
    'navy'::text as avatar_type,
    public.safe_profile_avatar_url(p.id, p.avatar_url) as avatar_url
  from public.lawyer_profiles lp
  join public.profiles p on p.id = lp.id
  where lp.id = lawyer_profile_id_value
    and lp.is_available = true
    and p.deleted_at is null
  limit 1;
$$;

revoke all on function public.fetch_lawyer_public_profile(uuid)
from public, anon;

grant execute on function public.fetch_lawyer_public_profile(uuid)
to authenticated;

drop function if exists public.fetch_chat_profile(uuid);

create function public.fetch_chat_profile(
  profile_id_value uuid
)
returns table (
  id uuid,
  full_name text,
  email text,
  initials text,
  avatar_url text,
  member_since date,
  lawyer_status text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    p.full_name,
    ''::text as email,
    p.initials,
    public.safe_profile_avatar_url(p.id, p.avatar_url) as avatar_url,
    p.member_since,
    p.lawyer_status::text
  from public.profiles p
  where p.id = profile_id_value
    and p.deleted_at is null
    and public.can_select_profile(p.id)
  limit 1;
$$;

revoke all on function public.fetch_chat_profile(uuid)
from public, anon;

grant execute on function public.fetch_chat_profile(uuid)
to authenticated;

drop function if exists public.fetch_conversation_for_current_user(uuid);

create function public.fetch_conversation_for_current_user(
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
    c.id,
    c.type::text,
    case
      when c.client_id = auth.uid() and c.law_firm_id is not null then
        coalesce(lf.name, c.title)
      when c.client_id = auth.uid() and c.lawyer_id is not null then
        public.profile_display_name(
          lawyer_profile.full_name,
          lawyer_profile.deleted_display_name,
          lawyer_profile.deleted_at
        )
      when c.client_id = auth.uid() then
        c.title
      else
        public.profile_display_name(
          client_profile.full_name,
          client_profile.deleted_display_name,
          client_profile.deleted_at
        )
    end as title,
    case
      when c.client_id = auth.uid() and c.law_firm_id is not null then
        coalesce(lf.initials, 'JE')
      when c.client_id = auth.uid() and c.lawyer_id is not null then
        coalesce(lawyer_profile.initials, 'AJ')
      when c.client_id = auth.uid() then
        upper(left(trim(c.title), 2))
      else
        coalesce(client_profile.initials, 'CL')
    end as initials,
    case
      when c.client_id = auth.uid() and c.law_firm_id is not null then
        null::text
      when c.client_id = auth.uid() and c.lawyer_id is not null then
        public.safe_profile_avatar_url(
          lawyer_profile.id,
          lawyer_profile.avatar_url
        )
      when c.client_id = auth.uid() then
        null::text
      else
        public.safe_profile_avatar_url(
          client_profile.id,
          client_profile.avatar_url
        )
    end as avatar_url,
    coalesce(c.specialty, 'Atendimento jurídico') as specialty,
    coalesce(c.last_message, 'Nova conversa') as last_message,
    c.last_message_at,
    c.law_firm_id,
    c.client_id,
    c.lawyer_id
  from public.conversations c
  left join public.profiles client_profile
    on client_profile.id = c.client_id
  left join public.law_firms lf
    on lf.id = c.law_firm_id
  left join public.profiles lawyer_profile
    on lawyer_profile.id = c.lawyer_id
  where c.id = conversation_id_value
    and (
      c.client_id = auth.uid()
      or c.lawyer_id = auth.uid()
      or exists (
        select 1
        from public.law_firm_members lfm
        where lfm.law_firm_id = c.law_firm_id
          and lfm.profile_id = auth.uid()
          and lfm.status = 'active'
      )
      or (
        c.case_id is not null
        and public.can_access_case(c.case_id)
      )
    )
  limit 1;
$$;

revoke all on function public.fetch_conversation_for_current_user(uuid)
from public, anon;

grant execute on function public.fetch_conversation_for_current_user(uuid)
to authenticated;

drop function if exists public.fetch_conversations_for_current_user(text, uuid);

create function public.fetch_conversations_for_current_user(
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
    select c.*
    from public.conversations c
    where auth.uid() is not null
      and exists (
        select 1
        from public.messages m
        where m.conversation_id = c.id
      )
      and (
        (
          scope_value = 'client'
          and c.client_id = auth.uid()
        )
        or (
          scope_value = 'lawyer'
          and c.type <> 'firm_internal'
          and (
            c.lawyer_id = auth.uid()
            or (
              c.case_id is not null
              and public.can_access_case(c.case_id)
            )
          )
        )
        or (
          scope_value = 'firmClient'
          and law_firm_id_value is not null
          and c.law_firm_id = law_firm_id_value
          and c.type <> 'firm_internal'
          and exists (
            select 1
            from public.law_firm_members lfm
            where lfm.law_firm_id = law_firm_id_value
              and lfm.profile_id = auth.uid()
              and lfm.status = 'active'
          )
        )
        or (
          scope_value = 'firmTeam'
          and law_firm_id_value is not null
          and c.law_firm_id = law_firm_id_value
          and c.type = 'firm_internal'
          and exists (
            select 1
            from public.law_firm_members lfm
            where lfm.law_firm_id = law_firm_id_value
              and lfm.profile_id = auth.uid()
              and lfm.status = 'active'
          )
        )
      )
  )
  select
    c.id,
    c.type::text,
    case
      when scope_value in ('lawyer', 'firmClient') then
        public.profile_display_name(
          client_profile.full_name,
          client_profile.deleted_display_name,
          client_profile.deleted_at
        )
      when scope_value = 'client' and c.law_firm_id is not null then
        coalesce(lf.name, c.title)
      when scope_value = 'client' and c.lawyer_id is not null then
        public.profile_display_name(
          lawyer_profile.full_name,
          lawyer_profile.deleted_display_name,
          lawyer_profile.deleted_at
        )
      else c.title
    end as title,
    case
      when scope_value in ('lawyer', 'firmClient') then
        coalesce(client_profile.initials, 'CL')
      when scope_value = 'client' and c.law_firm_id is not null then
        coalesce(lf.initials, 'JE')
      when scope_value = 'client' and c.lawyer_id is not null then
        coalesce(lawyer_profile.initials, 'AJ')
      else upper(left(trim(c.title), 2))
    end as initials,
    case
      when scope_value in ('lawyer', 'firmClient') then
        public.safe_profile_avatar_url(
          client_profile.id,
          client_profile.avatar_url
        )
      when scope_value = 'client' and c.law_firm_id is not null then
        null::text
      when scope_value = 'client' and c.lawyer_id is not null then
        public.safe_profile_avatar_url(
          lawyer_profile.id,
          lawyer_profile.avatar_url
        )
      else
        null::text
    end as avatar_url,
    coalesce(c.specialty, 'Atendimento jurídico') as specialty,
    coalesce(c.last_message, 'Nova conversa') as last_message,
    c.last_message_at,
    c.law_firm_id,
    c.client_id,
    c.lawyer_id
  from scoped_conversations c
  left join public.profiles client_profile
    on client_profile.id = c.client_id
  left join public.law_firms lf
    on lf.id = c.law_firm_id
  left join public.profiles lawyer_profile
    on lawyer_profile.id = c.lawyer_id
  order by c.last_message_at desc nulls last, c.updated_at desc;
$$;

revoke all on function public.fetch_conversations_for_current_user(text, uuid)
from public, anon;

grant execute on function public.fetch_conversations_for_current_user(text, uuid)
to authenticated;

select pg_notify('pgrst', 'reload schema');
