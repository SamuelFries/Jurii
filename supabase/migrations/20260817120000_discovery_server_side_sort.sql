-- Ordenacao da descoberta passa a ser do SERVIDOR (distancia e avaliacao).
--
-- O QUE ESTAVA ERRADO: o app ordenava client-side a lista JA CARREGADA, e o
-- servidor entrega 10 por pagina. Com 40 escritorios em producao, escolher
-- "Distancia" respondia "qual o mais perto DOS DEZ PRIMEIROS" — o mais proximo
-- podia estar atras do "Ver mais" e so entrava na conta depois de carregado.
-- O paliativo anterior (20260816120000 + app) era baixar todas as paginas
-- antes de ordenar: funciona com 40 escritorios, nao funciona com 5 mil.
--
-- O QUE MUDOU DE PREMISSA: ate aqui a posicao do usuario nunca saia do
-- aparelho, e por isso a ordenacao por distancia nao podia ser do servidor.
-- Decisao de produto tomada em 06/08/2026: a posicao pode ser enviada. Com
-- ela, a ordenacao volta para onde a paginacao vive, e o "mais perto" passa a
-- ser o mais perto DE VERDADE, nao o mais perto da primeira pagina.
--
-- A posicao e usada de forma TRANSITORIA: a funcao e `stable`, nao escreve em
-- lugar nenhum e nao alimenta discovery_events (o registro de alcance e feito
-- pelo app, por outra RPC, e nunca recebeu coordenada de cliente). Nenhuma
-- coordenada de usuario e persistida por esta mudanca.
--
-- COMPATIBILIDADE: os tres parametros novos tem DEFAULT, entao a chamada de
-- tres argumentos do app publicado continua resolvendo durante a janela de
-- deploy — e cai em 'relevance', que e exatamente o que ele ja pedia.

drop function public.fetch_recommended_law_firms(int, text, int);

create function public.fetch_recommended_law_firms(limit_value integer DEFAULT 10, search_value text DEFAULT NULL::text, offset_value integer DEFAULT 0, sort_value text DEFAULT 'relevance'::text, user_latitude double precision DEFAULT NULL::double precision, user_longitude double precision DEFAULT NULL::double precision)
 RETURNS TABLE(id uuid, name text, initials text, rating numeric, distance_label text, specialty text, practice_areas text[], reviews_count integer, avatar_type text, description text, phone text, email text, website_url text, address text, avatar_url text, is_featured boolean, latitude double precision, longitude double precision, is_sponsored_slot boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with search as (
    select nullif(public.normalize_practice_area_search(search_value), '') as q
  ),
  sorting as (
    select
      -- Valor desconhecido cai em 'relevance' em vez de estourar: app mais
      -- novo ou mais velho que o banco nao pode derrubar a descoberta.
      case
        when lower(btrim(coalesce(sort_value, ''))) in ('rating', 'distance')
          then lower(btrim(sort_value))
        else 'relevance'
      end as mode,
      -- Distancia sem posicao do usuario nao ordena nada; volta a relevancia,
      -- igual ao que o app faz quando o GPS e negado.
      (user_latitude is not null
        and user_longitude is not null
        and user_latitude between -90 and 90
        and user_longitude between -180 and 180) as tem_posicao
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
    select
      ranked.*,
      -- MESMO Haversine do aparelho (raio 6371.0 km, lib/utils/geo_distance
      -- .dart): se o servidor ordenasse por uma formula e a tela escrevesse
      -- "2,3 km" por outra, a lista apareceria fora de ordem para quem le.
      case
        when sorting.tem_posicao
          and ranked.latitude is not null
          and ranked.longitude is not null
        then 2 * 6371.0 * asin(sqrt(
          power(sin(radians(ranked.latitude - user_latitude) / 2), 2)
          + cos(radians(user_latitude)) * cos(radians(ranked.latitude))
            * power(sin(radians(ranked.longitude - user_longitude) / 2), 2)
        ))
      end as distancia_km
    from ranked
    cross join search
    cross join sorting
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
  --
  -- O slot vale SO na relevancia. Quando o cliente pede distancia ou
  -- avaliacao, ele pediu um criterio objetivo, e patrocinado nao fura criterio
  -- pedido (mesma decisao ja escrita em lib/utils/office_sorting.dart). O SELO
  -- (is_featured) continua aparecendo: pagou, e identificado.
  --
  -- is_sponsored_slot tambem tem que ficar falso fora da relevancia — e ele
  -- que atribui a impressao a vaga paga no painel de alcance, e contar uma
  -- entrega que a vaga nao fez infla justamente o numero que justifica a
  -- renovacao.
  featured_slots as (
    select eligible.id
    from eligible
    cross join sorting
    where eligible.is_featured
      and sorting.mode = 'relevance'
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
  cross join sorting
  left join featured_slots on featured_slots.id = eligible.id
  order by
    -- Relevancia: o de sempre (slot, intencao da busca, casamento, nota).
    (featured_slots.id is not null) desc,
    case when sorting.mode = 'relevance' then eligible.intent_weight end desc,
    case when sorting.mode = 'relevance' then eligible.direct_match end desc,
    -- Distancia: mais perto primeiro; sem coordenada vai para o fim, nunca
    -- some (hoje 39 dos 40 escritorios estao sem, e some-los esvaziaria a
    -- lista de quem escolhesse este criterio).
    case
      when sorting.mode = 'distance' and sorting.tem_posicao
        then eligible.distancia_km
    end asc nulls last,
    -- Avaliacao: nota, depois VOLUME (5,0 com 40 avaliacoes vale mais que
    -- 5,0 com uma).
    case when sorting.mode = 'rating' then eligible.rating end desc nulls last,
    case
      when sorting.mode = 'rating' then eligible.reviews_count
    end desc nulls last,
    eligible.rating desc,
    eligible.created_at desc,
    -- Desempate ESTÁVEL: sem ele, empate em created_at pode duplicar ou
    -- pular um escritório entre páginas consecutivas (offset).
    eligible.id
  limit least(greatest(coalesce(limit_value, 10), 1), 30)
  offset greatest(coalesce(offset_value, 0), 0);
$function$
;

-- drop + create ZERA os grants (create or replace preservaria, mas a lista de
-- argumentos mudou e ele nao aceita). Sem estas duas linhas a funcao ficaria
-- executavel por PUBLIC, inclusive anon.
revoke all on function public.fetch_recommended_law_firms(
  int, text, int, text, double precision, double precision
) from public, anon;

grant execute on function public.fetch_recommended_law_firms(
  int, text, int, text, double precision, double precision
) to authenticated;

notify pgrst, 'reload schema';
