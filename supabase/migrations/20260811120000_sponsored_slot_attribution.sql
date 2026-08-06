-- Separa "tem patrocinio ativo" de "ocupou a vaga paga".
--
-- O painel de alcance dizia ao profissional: "40 das 100 pessoas que viram
-- voce chegaram por uma VAGA PATROCINADA". Nao era verdade. O app marcava como
-- patrocinada toda impressao de quem tinha `is_featured`, e is_featured
-- significa apenas TER PATROCINIO ATIVO — o selo, que nao tem teto.
--
-- Vaga paga e outra coisa: sao no maximo 2 por lista (featured_slots). Quem
-- paga e aparece FORA delas, na posicao organica, estava sendo contado como
-- entregue pela vaga. Ou seja, o numero que justifica a renovacao do
-- patrocinio inflava a favor de quem vende — o mesmo erro, na mesma direcao,
-- que a metrica de lead tinha.
--
-- A funcao ja calculava featured_slots internamente para ordenar; so faltava
-- dizer quem estava neles. Corpos VERBATIM do que esta em producao: muda a
-- assinatura e uma coluna na saida.
--
-- O SELO na tela continua vindo de is_featured, e continua sem teto: quem
-- pagou e identificado como patrocinado mesmo aparecendo fora da vaga. O que
-- muda e so o que a MEDICAO atribui a vaga.

drop function public.fetch_recommended_lawyers(int, text, int);

create function public.fetch_recommended_lawyers(limit_value integer DEFAULT 6, search_value text DEFAULT NULL::text, offset_value integer DEFAULT 0)
 RETURNS TABLE(id uuid, full_name text, initials text, oab_number text, oab_state text, primary_area text, practice_areas text[], bio text, rating numeric, reviews_count integer, avatar_type text, avatar_url text, is_featured boolean, is_sponsored_slot boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
      ), 0) as intent_weight,
      -- Marcar muitas areas passa a nao ser atalho: entre relevantes, quem
      -- tem a area buscada como PRINCIPAL vem antes de quem apenas a incluiu
      -- na lista. O generalista continua aparecendo (nao ha teto de areas —
      -- advogado que atende cinco areas e realidade do interior), mas atras
      -- do especialista naquela area.
      coalesce((
        select true
        from inferred
        where public.normalize_practice_area_search(base.primary_area) =
          public.normalize_practice_area_search(inferred.practice_area)
        limit 1
      ), false) as primary_area_match
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
    eligible.is_featured,
    (featured_slots.id is not null) as is_sponsored_slot
  from eligible
  left join featured_slots on featured_slots.id = eligible.id
  order by
    (featured_slots.id is not null) desc,
    eligible.intent_weight desc,
    eligible.primary_area_match desc,
    eligible.direct_match desc,
    eligible.approved_at desc nulls last,
    eligible.created_at desc,
    -- Desempate ESTÁVEL: sem ele, empate em created_at pode duplicar ou
    -- pular um perfil entre páginas consecutivas (offset).
    eligible.id
  limit least(greatest(coalesce(limit_value, 6), 1), 20)
  offset greatest(coalesce(offset_value, 0), 0);
$function$;

revoke all on function public.fetch_recommended_lawyers(int, text, int)
from public, anon;
grant execute on function public.fetch_recommended_lawyers(int, text, int)
to authenticated;

drop function public.fetch_recommended_law_firms(int, text, int);

create function public.fetch_recommended_law_firms(limit_value integer DEFAULT 10, search_value text DEFAULT NULL::text, offset_value integer DEFAULT 0)
 RETURNS TABLE(id uuid, name text, initials text, rating numeric, distance_label text, specialty text, practice_areas text[], reviews_count integer, avatar_type text, description text, phone text, email text, website_url text, address text, avatar_url text, is_featured boolean, latitude double precision, longitude double precision, is_sponsored_slot boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    eligible.longitude,
    (featured_slots.id is not null) as is_sponsored_slot
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
$function$;

revoke all on function public.fetch_recommended_law_firms(int, text, int)
from public, anon;
grant execute on function public.fetch_recommended_law_firms(int, text, int)
to authenticated;

-- ---------------------------------------------------------------------------
-- Segundo vazamento do mesmo numero: o escritorio se vendo na descoberta.
--
-- log_discovery_events ja ignorava `target_id = auth.uid()`, o que resolve o
-- ADVOGADO olhando o proprio cartao. Para ESCRITORIO nao resolvia nada: o alvo
-- e o id da firma e quem navega e uma pessoa, entao dono, socio e secretaria
-- navegando na descoberta inflavam o alcance do proprio escritorio.
-- ---------------------------------------------------------------------------

create or replace function public.log_discovery_events(
  event_type_value text,
  target_type_value text,
  target_ids_value uuid[],
  sponsored_ids_value uuid[] default null
)
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  clean_ids uuid[];
  sponsored_ids uuid[];
  gravados integer;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if event_type_value not in ('impression', 'profile_view') then
    raise exception 'Invalid event type';
  end if;

  if target_type_value not in ('lawyer', 'law_firm') then
    raise exception 'Invalid target type';
  end if;

  select array_agg(distinct target_id)
  into clean_ids
  from unnest(coalesce(target_ids_value, array[]::uuid[])) as ids(target_id)
  where target_id is not null;

  clean_ids := coalesce(clean_ids, array[]::uuid[]);
  if cardinality(clean_ids) = 0 then
    return 0;
  end if;

  if cardinality(clean_ids) > 100 then
    raise exception 'Too many targets';
  end if;

  sponsored_ids := coalesce(sponsored_ids_value, array[]::uuid[]);

  insert into public.discovery_events (
    event_type, target_type, target_id, viewer_id, sponsored
  )
  select
    event_type_value,
    target_type_value,
    target_id,
    auth.uid(),
    target_id = any(sponsored_ids)
  from unnest(clean_ids) as ids(target_id)
  -- Advogado olhando o proprio cartao.
  where target_id is distinct from auth.uid()
    -- Membro do escritorio olhando o proprio escritorio.
    and not (
      target_type_value = 'law_firm'
      and exists (
        select 1
        from public.law_firm_members lfm
        where lfm.law_firm_id = target_id
          and lfm.profile_id = auth.uid()
          and lfm.status = 'active'
      )
    )
  on conflict (day, event_type, target_type, target_id, viewer_id)
  do update set sponsored = public.discovery_events.sponsored or excluded.sponsored;

  get diagnostics gravados = row_count;
  return gravados;
end;
$$;

revoke all on function public.log_discovery_events(text, text, uuid[], uuid[])
from public, anon;
grant execute on function public.log_discovery_events(text, text, uuid[], uuid[])
to authenticated;

notify pgrst, 'reload schema';
