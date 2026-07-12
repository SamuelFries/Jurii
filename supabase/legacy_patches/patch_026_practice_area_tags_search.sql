-- Multi-area practice tags for lawyer and law firm onboarding/search.
--
-- Run after patch_025. This keeps the legacy primary area fields for existing
-- screens, while adding practice_areas arrays for multi-tag search.

alter table public.lawyer_verifications
add column if not exists practice_areas text[] not null default '{}'::text[];

alter table public.lawyer_profiles
add column if not exists practice_areas text[] not null default '{}'::text[];

alter table public.law_firm_verifications
add column if not exists practice_areas text[] not null default '{}'::text[];

alter table public.law_firms
add column if not exists practice_areas text[] not null default '{}'::text[];

update public.lawyer_verifications
set practice_areas = array[practice_area]
where cardinality(practice_areas) = 0
  and nullif(trim(coalesce(practice_area, '')), '') is not null;

update public.lawyer_profiles
set practice_areas = array[primary_area]
where cardinality(practice_areas) = 0
  and nullif(trim(coalesce(primary_area, '')), '') is not null;

update public.law_firms
set practice_areas = array[specialty]
where cardinality(practice_areas) = 0
  and nullif(trim(coalesce(specialty, '')), '') is not null;

create index if not exists lawyer_profiles_practice_areas_idx
on public.lawyer_profiles using gin (practice_areas);

create index if not exists law_firms_practice_areas_idx
on public.law_firms using gin (practice_areas);

create or replace function public.normalize_practice_area_search(value text)
returns text
language sql
immutable
as $$
  select translate(
    lower(trim(coalesce(value, ''))),
    'áàâãéêíóôõúüç',
    'aaaaeeiooouuc'
  );
$$;

drop function if exists public.submit_lawyer_verification(text, text, text);

create or replace function public.submit_lawyer_verification(
  oab_number_value text,
  oab_state_value text,
  practice_area_value text,
  practice_areas_value text[] default null
)
returns table (
  id uuid,
  user_id uuid,
  oab_number text,
  oab_state char(2),
  practice_area text,
  practice_areas text[],
  status public.verification_status,
  submitted_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  user_id_value uuid;
  email_value text;
  full_name_value text;
  verification_id_value uuid;
  submitted_at_value timestamptz;
  normalized_oab_number text;
  normalized_oab_state char(2);
  normalized_practice_area text;
  normalized_practice_areas text[];
  status_value public.verification_status := 'pending';
begin
  user_id_value := auth.uid();

  if user_id_value is null then
    raise exception 'User must be authenticated';
  end if;

  normalized_oab_number := nullif(trim(coalesce(oab_number_value, '')), '');
  normalized_oab_state := upper(trim(coalesce(oab_state_value, '')))::char(2);
  normalized_practice_area :=
    nullif(trim(coalesce(practice_area_value, '')), '');

  select coalesce(array_agg(area order by first_ordinal), '{}'::text[])
  into normalized_practice_areas
  from (
    select trim(area_value) as area, min(ordinality) as first_ordinal
    from unnest(coalesce(practice_areas_value, '{}'::text[]))
      with ordinality as areas(area_value, ordinality)
    where nullif(trim(area_value), '') is not null
    group by trim(area_value)
  ) clean_areas;

  if cardinality(normalized_practice_areas) = 0
      and normalized_practice_area is not null then
    normalized_practice_areas := array[normalized_practice_area];
  end if;

  if normalized_practice_area is null
      and cardinality(normalized_practice_areas) > 0 then
    normalized_practice_area := normalized_practice_areas[1];
  end if;

  if normalized_oab_number is null then
    raise exception 'OAB number is required';
  end if;

  if nullif(trim(coalesce(oab_state_value, '')), '') is null then
    raise exception 'OAB state is required';
  end if;

  if normalized_practice_area is null then
    raise exception 'Practice area is required';
  end if;

  email_value := coalesce(auth.jwt() ->> 'email', '');
  full_name_value := coalesce(
    nullif(auth.jwt() -> 'user_metadata' ->> 'full_name', ''),
    nullif(auth.jwt() -> 'user_metadata' ->> 'name', ''),
    nullif(split_part(email_value, '@', 1), ''),
    'Usuário Jurii'
  );

  insert into public.profiles (
    id,
    full_name,
    email,
    initials,
    lawyer_status
  )
  values (
    user_id_value,
    full_name_value,
    email_value,
    upper(left(full_name_value, 1)),
    'pending'
  )
  on conflict on constraint profiles_pkey do update
  set
    full_name = coalesce(
      nullif(public.profiles.full_name, ''),
      excluded.full_name
    ),
    email = coalesce(nullif(public.profiles.email, ''), excluded.email),
    initials = coalesce(
      nullif(public.profiles.initials, ''),
      excluded.initials
    ),
    lawyer_status = case
      when public.profiles.lawyer_status = 'approved' then
        'approved'::public.lawyer_status
      else 'pending'::public.lawyer_status
    end,
    updated_at = now();

  insert into public.lawyer_verifications (
    user_id,
    oab_number,
    oab_state,
    practice_area,
    practice_areas,
    status
  )
  values (
    user_id_value,
    normalized_oab_number,
    normalized_oab_state,
    normalized_practice_area,
    normalized_practice_areas,
    status_value
  )
  returning
    public.lawyer_verifications.id,
    public.lawyer_verifications.submitted_at
  into verification_id_value, submitted_at_value;

  return query
  select
    verification_id_value,
    user_id_value,
    normalized_oab_number,
    normalized_oab_state,
    normalized_practice_area,
    normalized_practice_areas,
    status_value,
    submitted_at_value;
end;
$$;

create or replace function public.approve_lawyer_verification(
  verification_id_value uuid,
  reviewer_id_value uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  verification_row public.lawyer_verifications%rowtype;
  areas_value text[];
  primary_area_value text;
begin
  select *
  into verification_row
  from public.lawyer_verifications
  where id = verification_id_value;

  if not found then
    raise exception 'Lawyer verification not found: %', verification_id_value;
  end if;

  areas_value := coalesce(verification_row.practice_areas, '{}'::text[]);
  primary_area_value :=
    nullif(trim(coalesce(verification_row.practice_area, '')), '');

  if cardinality(areas_value) = 0 and primary_area_value is not null then
    areas_value := array[primary_area_value];
  end if;

  if primary_area_value is null and cardinality(areas_value) > 0 then
    primary_area_value := areas_value[1];
  end if;

  primary_area_value := coalesce(primary_area_value, 'Atendimento jurídico');

  update public.lawyer_verifications
  set
    status = 'approved',
    reviewed_at = now(),
    reviewer_id = reviewer_id_value,
    rejection_reason = null
  where id = verification_id_value;

  update public.profiles
  set lawyer_status = 'approved'
  where id = verification_row.user_id;

  insert into public.lawyer_profiles (
    id,
    oab_number,
    oab_state,
    primary_area,
    practice_areas,
    approved_at
  )
  values (
    verification_row.user_id,
    verification_row.oab_number,
    verification_row.oab_state,
    primary_area_value,
    areas_value,
    now()
  )
  on conflict (id) do update
  set
    oab_number = excluded.oab_number,
    oab_state = excluded.oab_state,
    primary_area = excluded.primary_area,
    practice_areas = excluded.practice_areas,
    approved_at = coalesce(
      public.lawyer_profiles.approved_at,
      excluded.approved_at
    );

  return verification_row.user_id;
end;
$$;

create or replace function public.approve_law_firm_verification(
  verification_id_value uuid,
  reviewer_id_value uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  verification_row public.law_firm_verifications%rowtype;
  firm_id_value uuid;
  initials_value text;
  existing_member_id uuid;
  areas_value text[];
  specialty_value text;
begin
  select *
  into verification_row
  from public.law_firm_verifications
  where id = verification_id_value;

  if not found then
    raise exception 'Law firm verification not found: %',
      verification_id_value;
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
      nullif(verification_row.phone, ''),
      nullif(verification_row.email, ''),
      nullif(verification_row.address, ''),
      true
    )
    returning id into firm_id_value;
  else
    firm_id_value := verification_row.law_firm_id;

    update public.law_firms
    set
      name = verification_row.firm_name,
      initials = initials_value,
      specialty = specialty_value,
      practice_areas = areas_value,
      phone = nullif(verification_row.phone, ''),
      email = nullif(verification_row.email, ''),
      address = nullif(verification_row.address, ''),
      avatar_type = 'purple',
      is_active = true,
      updated_at = now()
    where id = firm_id_value;
  end if;

  update public.law_firm_verifications
  set
    status = 'approved',
    law_firm_id = firm_id_value,
    reviewed_at = now(),
    reviewer_id = reviewer_id_value,
    rejection_reason = null
  where id = verification_id_value;

  select id
  into existing_member_id
  from public.law_firm_members
  where law_firm_id = firm_id_value
    and profile_id = verification_row.owner_profile_id
  limit 1;

  if existing_member_id is null then
    insert into public.law_firm_members (
      law_firm_id,
      profile_id,
      role,
      member_role,
      status
    )
    values (
      firm_id_value,
      verification_row.owner_profile_id,
      'owner',
      'owner',
      'active'
    );
  else
    update public.law_firm_members
    set
      role = 'owner',
      member_role = 'owner',
      status = 'active'
    where id = existing_member_id;
  end if;

  return firm_id_value;
end;
$$;

drop function if exists public.fetch_recommended_lawyers(int);

create or replace function public.fetch_recommended_lawyers(
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
  avatar_type text
)
language sql
stable
security definer
set search_path = public
as $$
  with search as (
    select nullif(public.normalize_practice_area_search(search_value), '') as q
  )
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
    4.8::numeric as rating,
    0::int as reviews_count,
    'navy'::text as avatar_type
  from public.lawyer_profiles lp
  join public.profiles p on p.id = lp.id
  cross join search
  where lp.is_available = true
    and (
      search.q is null
      or public.normalize_practice_area_search(p.full_name)
        like '%' || search.q || '%'
      or public.normalize_practice_area_search(lp.primary_area)
        like '%' || search.q || '%'
      or exists (
        select 1
        from unnest(coalesce(lp.practice_areas, '{}'::text[])) as area
        where public.normalize_practice_area_search(area)
          like '%' || search.q || '%'
      )
    )
  order by lp.approved_at desc nulls last, lp.created_at desc
  limit least(greatest(coalesce(limit_value, 6), 1), 20);
$$;

drop function if exists public.fetch_lawyer_public_profile(uuid);

create or replace function public.fetch_lawyer_public_profile(
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
  avatar_type text
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
    4.8::numeric as rating,
    0::int as reviews_count,
    'navy'::text as avatar_type
  from public.lawyer_profiles lp
  join public.profiles p on p.id = lp.id
  where lp.id = lawyer_profile_id_value
    and lp.is_available = true
  limit 1;
$$;

create or replace function public.fetch_recommended_law_firms(
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
  address text
)
language sql
stable
security definer
set search_path = public
as $$
  with search as (
    select nullif(public.normalize_practice_area_search(search_value), '') as q
  )
  select
    lf.id,
    lf.name,
    lf.initials,
    lf.rating,
    lf.distance_label,
    lf.specialty,
    case
      when cardinality(lf.practice_areas) > 0 then lf.practice_areas
      else array[lf.specialty]
    end as practice_areas,
    lf.reviews_count,
    lf.avatar_type,
    lf.description,
    lf.phone,
    lf.email,
    lf.website_url,
    lf.address
  from public.law_firms lf
  cross join search
  where lf.is_active = true
    and (
      search.q is null
      or public.normalize_practice_area_search(lf.name)
        like '%' || search.q || '%'
      or public.normalize_practice_area_search(lf.specialty)
        like '%' || search.q || '%'
      or exists (
        select 1
        from unnest(coalesce(lf.practice_areas, '{}'::text[])) as area
        where public.normalize_practice_area_search(area)
          like '%' || search.q || '%'
      )
    )
  order by lf.rating desc, lf.created_at desc
  limit least(greatest(coalesce(limit_value, 10), 1), 30);
$$;

revoke all on function public.normalize_practice_area_search(text)
from public, anon, authenticated;

revoke all on function public.submit_lawyer_verification(text, text, text, text[])
from public, anon, authenticated;

revoke all on function public.approve_lawyer_verification(uuid, uuid)
from public, anon, authenticated;

revoke all on function public.approve_law_firm_verification(uuid, uuid)
from public, anon, authenticated;

revoke all on function public.fetch_recommended_lawyers(int, text)
from public, anon, authenticated;

revoke all on function public.fetch_lawyer_public_profile(uuid)
from public, anon, authenticated;

revoke all on function public.fetch_recommended_law_firms(int, text)
from public, anon, authenticated;

grant execute on function public.submit_lawyer_verification(text, text, text, text[])
to authenticated;

grant execute on function public.approve_lawyer_verification(uuid, uuid)
to service_role;

grant execute on function public.approve_law_firm_verification(uuid, uuid)
to service_role;

grant execute on function public.fetch_recommended_lawyers(int, text)
to authenticated;

grant execute on function public.fetch_lawyer_public_profile(uuid)
to authenticated;

grant execute on function public.fetch_recommended_law_firms(int, text)
to authenticated;

notify pgrst, 'reload schema';
