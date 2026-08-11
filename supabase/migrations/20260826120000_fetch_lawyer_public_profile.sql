-- Perfil publico do advogado por id, para o webapp.
--
-- POR QUE EXISTE. O nome do advogado mora em profiles, cuja RLS so abre
-- para o proprio dono ou para quem tem caso/conversa com ele; a descoberta
-- so entrega o nome via RPC SECURITY DEFINER (fetch_recommended_lawyers), e
-- nao havia RPC de perfil por id. O webapp precisa de deep link
-- (/profissionais/<id>) e sem isto a pagina nasceria sem nome.
--
-- O QUE ELA DEVOLVE: exatamente o subconjunto que a descoberta ja expoe a
-- qualquer autenticado, com as MESMAS expressoes (coalesce de nome e bio,
-- safe_profile_avatar_url, selo de destaque). Nada de telefone, e-mail ou
-- CPF: dado de contato do advogado nao e publico.
--
-- O MESMO portao da descoberta, e um pouco mais estreito: aprovado E
-- disponivel E perfil nao apagado. Funcao NOVA (create, nao replace):
-- nenhuma funcao existente e tocada, nenhum grant antigo e resetado.

create function public.fetch_lawyer_public_profile(lawyer_id_value uuid)
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
  reviews_count integer,
  avatar_type text,
  avatar_url text,
  is_featured boolean
)
language sql
stable
security definer
set search_path to 'public'
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
    public.safe_profile_avatar_url(p.id, p.avatar_url) as avatar_url,
    exists (
      select 1
      from public.featured_placements fp
      where fp.lawyer_id = lp.id
        and fp.revoked_at is null
        and now() >= fp.starts_at
        and now() < fp.ends_at
    ) as is_featured
  from public.lawyer_profiles lp
  join public.profiles p on p.id = lp.id
  where lp.id = lawyer_id_value
    and lp.approved_at is not null
    and lp.is_available = true
    and p.deleted_at is null;
$$;

revoke all on function public.fetch_lawyer_public_profile(uuid)
from public, anon;
grant execute on function public.fetch_lawyer_public_profile(uuid)
to authenticated;

notify pgrst, 'reload schema';
