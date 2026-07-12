-- Stable entry point for the client home recommended lawyers section.
--
-- Run after patch_010. This avoids the app depending on multiple client-side
-- RLS reads across lawyer_profiles and profiles just to render public cards.

create or replace function public.fetch_recommended_lawyers(
  limit_value int default 6
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
  where lp.is_available = true
  order by lp.approved_at desc nulls last, lp.created_at desc
  limit least(greatest(coalesce(limit_value, 6), 1), 20);
$$;

revoke all on function public.fetch_recommended_lawyers(int)
from public, anon, authenticated;

grant execute on function public.fetch_recommended_lawyers(int)
to authenticated;
