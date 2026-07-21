-- Destaque pago na descoberta (monetizacao, fase 1: infraestrutura)
--
-- O modelo de negocio do Jurii e advogado/escritorio pagarem por destaque na
-- descoberta — e ate hoje nao havia NADA disso no produto. Esta migration cria
-- a infraestrutura tecnica; a cobranca (gateway) e uma fase separada. Com isso
-- o back-office ja pode ativar destaque manualmente para os primeiros
-- parceiros do piloto (cortesia/contrato por fora) e medir se o boost gera
-- contatos, antes de investir no encanamento de pagamento.
--
-- Desenho:
--   1. featured_placements: tabela-razao (e dinheiro: cada concessao e uma
--      linha, revogacao e soft, nada se apaga). RLS ligado sem policy — tudo
--      por RPC.
--   2. grant/revoke_featured_placement: service_role only (back-office),
--      mesmo padrao das verificacoes.
--   3. fetch_recommended_lawyers / fetch_recommended_law_firms passam a
--      devolver is_featured e a dar ate 2 POSICOES patrocinadas no topo —
--      respeitando o filtro da busca (patrocinado irrelevante nao fura) e
--      com rotacao horaria quando ha mais pagantes que vagas.
--
-- Corpos das funcoes extraidos VERBATIM das definicoes vigentes
-- (20260718180000 e 20260718200000); somente o destaque foi somado — o
-- avatar_url/safe_profile_avatar_url dessas versoes esta preservado.

-- ---------------------------------------------------------------------------
-- 1. Tabela-razao de destaques
-- ---------------------------------------------------------------------------

create table if not exists public.featured_placements (
  id uuid primary key default gen_random_uuid(),
  target_type text not null check (target_type in ('lawyer', 'law_firm')),
  lawyer_id uuid references public.lawyer_profiles(id) on delete cascade,
  law_firm_id uuid references public.law_firms(id) on delete cascade,
  starts_at timestamptz not null default now(),
  ends_at timestamptz not null,
  note text,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  -- Exatamente um alvo, coerente com target_type (mesmo padrao de
  -- professional_reviews).
  constraint featured_placements_target_chk check (
    (target_type = 'lawyer' and lawyer_id is not null and law_firm_id is null)
    or
    (target_type = 'law_firm' and law_firm_id is not null and lawyer_id is null)
  ),
  constraint featured_placements_period_chk check (ends_at > starts_at)
);

create index if not exists featured_placements_lawyer_active_idx
  on public.featured_placements (lawyer_id, ends_at)
  where lawyer_id is not null and revoked_at is null;

create index if not exists featured_placements_firm_active_idx
  on public.featured_placements (law_firm_id, ends_at)
  where law_firm_id is not null and revoked_at is null;

-- RLS ligado e SEM policy: cliente nao le nem escreve direto. O selo chega ao
-- app pelos RPCs de descoberta (is_featured); concessao/revogacao e so
-- back-office.
alter table public.featured_placements enable row level security;

-- Duas camadas, como nas demais tabelas-razao do projeto: alem do RLS sem
-- policy, revoga os privilegios de tabela — um "disable row level security"
-- acidental ou uma policy permissiva futura nao expoe o razao de monetizacao.
revoke all on table public.featured_placements from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Conceder destaque (back-office / service_role)
--
-- Sempre INSERE uma linha nova (renovacao = nova linha; o ranking considera
-- destacado se EXISTS alguma ativa). Nada de update em concessao — o razao
-- fica integro para virar historico de cobranca depois.
-- ---------------------------------------------------------------------------

create or replace function public.grant_featured_placement(
  target_type_value text,
  target_id_value uuid,
  days_value int default 30,
  note_value text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $fn$
declare
  placement_id uuid;
begin
  if target_type_value not in ('lawyer', 'law_firm') then
    raise exception 'Invalid target type: %', target_type_value
      using errcode = '22023';
  end if;

  if days_value is null or days_value < 1 or days_value > 366 then
    raise exception 'Days must be between 1 and 366'
      using errcode = '22023';
  end if;

  if target_type_value = 'lawyer' then
    if not exists (
      select 1 from public.lawyer_profiles lp where lp.id = target_id_value
    ) then
      raise exception 'Lawyer profile not found: %', target_id_value;
    end if;

    -- Sucesso falso e proibido num razao de cobranca: destacar quem a
    -- descoberta nao exibe (indisponivel/conta excluida) cobraria por nada.
    -- Exception, nao notice — o PostgREST nao repassa notice ao chamador.
    if not exists (
      select 1
      from public.lawyer_profiles lp
      join public.profiles p on p.id = lp.id
      where lp.id = target_id_value
        and lp.is_available = true
        and p.deleted_at is null
    ) then
      raise exception
        'Lawyer % is not visible in discovery; fix visibility before granting',
        target_id_value
        using errcode = '22023';
    end if;

    insert into public.featured_placements (
      target_type, lawyer_id, starts_at, ends_at, note
    )
    values (
      'lawyer', target_id_value, now(),
      now() + make_interval(days => days_value),
      nullif(trim(coalesce(note_value, '')), '')
    )
    returning id into placement_id;
  else
    if not exists (
      select 1 from public.law_firms lf where lf.id = target_id_value
    ) then
      raise exception 'Law firm not found: %', target_id_value;
    end if;

    if not exists (
      select 1 from public.law_firms lf
      where lf.id = target_id_value and lf.is_active = true
    ) then
      raise exception
        'Law firm % is not active; activate it before granting',
        target_id_value
        using errcode = '22023';
    end if;

    insert into public.featured_placements (
      target_type, law_firm_id, starts_at, ends_at, note
    )
    values (
      'law_firm', target_id_value, now(),
      now() + make_interval(days => days_value),
      nullif(trim(coalesce(note_value, '')), '')
    )
    returning id into placement_id;
  end if;

  return placement_id;
end;
$fn$;

-- ---------------------------------------------------------------------------
-- 3. Revogar destaque (soft: revoked_at, o razao preserva o historico)
-- ---------------------------------------------------------------------------

create or replace function public.revoke_featured_placement(
  target_type_value text,
  target_id_value uuid
)
returns int
language plpgsql
security definer
set search_path = public
as $fn$
declare
  revoked_count int;
begin
  if target_type_value not in ('lawyer', 'law_firm') then
    raise exception 'Invalid target type: %', target_type_value
      using errcode = '22023';
  end if;

  update public.featured_placements
  set revoked_at = now()
  where revoked_at is null
    and now() < ends_at
    and (
      (target_type_value = 'lawyer' and lawyer_id = target_id_value)
      or (target_type_value = 'law_firm' and law_firm_id = target_id_value)
    );

  get diagnostics revoked_count = row_count;
  return revoked_count;
end;
$fn$;

-- ---------------------------------------------------------------------------
-- 4. Descoberta com destaque: fetch_recommended_lawyers
--
-- O return type muda (nova coluna is_featured), entao drop antes de recriar
-- (create or replace nao muda return type) e re-grant depois.
-- ---------------------------------------------------------------------------

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
    eligible.created_at desc
  limit least(greatest(coalesce(limit_value, 6), 1), 20);
$$;

-- ---------------------------------------------------------------------------
-- 5. Descoberta com destaque: fetch_recommended_law_firms
-- ---------------------------------------------------------------------------

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
    eligible.is_featured
  from eligible
  left join featured_slots on featured_slots.id = eligible.id
  order by
    (featured_slots.id is not null) desc,
    eligible.intent_weight desc,
    eligible.direct_match desc,
    eligible.rating desc,
    eligible.created_at desc
  limit least(greatest(coalesce(limit_value, 10), 1), 30);
$$;

-- ---------------------------------------------------------------------------
-- 6. Grants
-- ---------------------------------------------------------------------------

revoke all on function public.grant_featured_placement(text, uuid, int, text)
from public, anon, authenticated;

revoke all on function public.revoke_featured_placement(text, uuid)
from public, anon, authenticated;

grant execute on function public.grant_featured_placement(text, uuid, int, text)
to service_role;

grant execute on function public.revoke_featured_placement(text, uuid)
to service_role;

revoke all on function public.fetch_recommended_lawyers(int, text)
from public, anon;

grant execute on function public.fetch_recommended_lawyers(int, text)
to authenticated;

revoke all on function public.fetch_recommended_law_firms(int, text)
from public, anon;

grant execute on function public.fetch_recommended_law_firms(int, text)
to authenticated;

notify pgrst, 'reload schema';
