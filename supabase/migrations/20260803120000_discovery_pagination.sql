-- Paginação da descoberta: offset_value nas duas RPCs de recomendação.
--
-- Antes, o app pedia limit 6 (advogados) / 10 (escritórios) e não havia como
-- ver o resto: a função central do marketplace parava na primeira tela.
--
-- Corpos extraídos VERBATIM das definições vigentes (20260721120000 para
-- advogados, 20260724120000 para escritórios); mudanças exatas:
--   1. parâmetro novo offset_value int default 0 (por último: chamada antiga
--      com 2 args continua válida — app publicado não quebra);
--   2. desempate final por eligible.id no ORDER BY (paginação estável);
--   3. offset greatest(coalesce(offset_value, 0), 0) após o LIMIT.
--
-- DROP explícito antes de recriar: criar a assinatura de 3 args AO LADO da
-- de 2 viraria sobrecarga e o PostgREST falharia em resolver a chamada com
-- 2 parâmetros (ambígua) — armadilha já vivida com profile_display_name.
-- Drop+create zera grants: revoke/grant refeitos no fim (lição documentada).

drop function public.fetch_recommended_lawyers(int, text);
drop function public.fetch_recommended_law_firms(int, text);

create function public.fetch_recommended_lawyers(
  limit_value int default 6,
  search_value text default null,
  offset_value int default 0
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
  avatar_url text,
  is_featured boolean
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
      exists (
        select 1
        from public.featured_placements fp
        where fp.lawyer_id = lp.id
          and fp.revoked_at is null
          and now() >= fp.starts_at
          and now() < fp.ends_at
      ) as is_featured,
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
  ),
  eligible as (
    select ranked.*
    from ranked
    cross join search
    where search.q is null
      or ranked.direct_match
      or ranked.intent_weight > 0
  ),
  -- Ate 2 posicoes patrocinadas por lista. O destaque so reordena entre os
  -- RELEVANTES (eligible ja aplicou o filtro da busca): quem busca uma area
  -- nunca ve patrocinado de outra area furando o resultado. Havendo mais
  -- destacados que vagas, a escolha gira por hora (md5 deterministico) para
  -- nenhum pagante ficar permanentemente invisivel. O SELO (is_featured) vale
  -- para todo destacado, mesmo fora do slot: pagou, e identificado.
  featured_slots as (
    select eligible.id
    from eligible
    where eligible.is_featured
    order by md5(eligible.id::text || to_char(now(), 'YYYYMMDDHH24'))
    limit 2
  )
  select
    eligible.id,
    eligible.full_name,
    eligible.initials,
    eligible.oab_number,
    eligible.oab_state,
    eligible.primary_area,
    eligible.practice_areas,
    eligible.bio,
    eligible.rating,
    eligible.reviews_count,
    eligible.avatar_type,
    eligible.avatar_url,
    eligible.is_featured
  from eligible
  left join featured_slots on featured_slots.id = eligible.id
  order by
    (featured_slots.id is not null) desc,
    eligible.intent_weight desc,
    eligible.direct_match desc,
    eligible.approved_at desc nulls last,
    eligible.created_at desc,
    -- Desempate ESTÁVEL: sem ele, empate em created_at pode duplicar ou
    -- pular um perfil entre páginas consecutivas (offset).
    eligible.id
  limit least(greatest(coalesce(limit_value, 6), 1), 20)
  offset greatest(coalesce(offset_value, 0), 0);
$$;

create function public.fetch_recommended_law_firms(
  limit_value int default 10,
  search_value text default null,
  offset_value int default 0
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
  avatar_url text,
  is_featured boolean,
  latitude double precision,
  longitude double precision
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
      firm.latitude,
      firm.longitude,
      exists (
        select 1
        from public.featured_placements fp
        where fp.law_firm_id = firm.id
          and fp.revoked_at is null
          and now() >= fp.starts_at
          and now() < fp.ends_at
      ) as is_featured,
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
  ),
  eligible as (
    select ranked.*
    from ranked
    cross join search
    where search.q is null
      or ranked.direct_match
      or ranked.intent_weight > 0
  ),
  -- Ate 2 posicoes patrocinadas por lista. O destaque so reordena entre os
  -- RELEVANTES (eligible ja aplicou o filtro da busca): quem busca uma area
  -- nunca ve patrocinado de outra area furando o resultado. Havendo mais
  -- destacados que vagas, a escolha gira por hora (md5 deterministico) para
  -- nenhum pagante ficar permanentemente invisivel. O SELO (is_featured) vale
  -- para todo destacado, mesmo fora do slot: pagou, e identificado.
  featured_slots as (
    select eligible.id
    from eligible
    where eligible.is_featured
    order by md5(eligible.id::text || to_char(now(), 'YYYYMMDDHH24'))
    limit 2
  )
  select
    eligible.id,
    eligible.name,
    eligible.initials,
    eligible.rating,
    eligible.distance_label,
    eligible.specialty,
    eligible.practice_areas,
    eligible.reviews_count,
    eligible.avatar_type,
    eligible.description,
    eligible.phone,
    eligible.email,
    eligible.website_url,
    eligible.address,
    eligible.avatar_url,
    eligible.is_featured,
    eligible.latitude,
    eligible.longitude
  from eligible
  left join featured_slots on featured_slots.id = eligible.id
  order by
    (featured_slots.id is not null) desc,
    eligible.intent_weight desc,
    eligible.direct_match desc,
    eligible.rating desc,
    eligible.created_at desc,
    -- Desempate ESTÁVEL: sem ele, empate em created_at pode duplicar ou
    -- pular um escritório entre páginas consecutivas (offset).
    eligible.id
  limit least(greatest(coalesce(limit_value, 10), 1), 30)
  offset greatest(coalesce(offset_value, 0), 0);
$$;

revoke all on function public.fetch_recommended_lawyers(int, text, int)
from public, anon;

grant execute on function public.fetch_recommended_lawyers(int, text, int)
to authenticated;

revoke all on function public.fetch_recommended_law_firms(int, text, int)
from public, anon;

grant execute on function public.fetch_recommended_law_firms(int, text, int)
to authenticated;

notify pgrst, 'reload schema';
