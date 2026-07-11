-- Profile entry points opened from chat headers.
--
-- Run after patch_012.

create or replace function public.fetch_chat_profile(
  profile_id_value uuid
)
returns table (
  id uuid,
  full_name text,
  email text,
  initials text,
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
    p.email,
    p.initials,
    p.member_since,
    p.lawyer_status::text
  from public.profiles p
  where p.id = profile_id_value
    and public.can_select_profile(p.id)
  limit 1;
$$;

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

revoke all on function public.fetch_chat_profile(uuid)
from public, anon, authenticated;

revoke all on function public.fetch_lawyer_public_profile(uuid)
from public, anon, authenticated;

grant execute on function public.fetch_chat_profile(uuid)
to authenticated;

grant execute on function public.fetch_lawyer_public_profile(uuid)
to authenticated;
