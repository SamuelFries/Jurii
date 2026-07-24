-- Localizacao dos escritorios: CEP + coordenadas (distancia real no app)
--
-- A "distancia" exibida ate hoje era FAKE: law_firms.distance_label e um texto
-- que so os 3 escritorios demo do seed possuem ("1,8 km" fixo); toda firma
-- real nasce com '' e nada nunca calculou nada. Esta migration cria a base
-- real:
--
--   1. cep + latitude/longitude em law_firm_verifications (o dono informa o
--      CEP no cadastro; o app geocodifica via BrasilAPI no submit) e em
--      law_firms (a aprovacao copia).
--   2. approve_law_firm_verification copia cep/lat/lng (INSERT e UPDATE).
--   3. fetch_recommended_law_firms devolve latitude/longitude.
--
-- PRIVACIDADE (decisao de arquitetura): a posicao do CLIENTE nunca sai do
-- aparelho. O banco guarda apenas as coordenadas do ESCRITORIO (dado publico
-- de estabelecimento); o app calcula a distancia localmente (Haversine).
-- Nenhuma localizacao de usuario e trafegada ou armazenada.
--
-- As coordenadas sao auto-declaradas (derivadas do CEP que o dono informa),
-- como o endereco ja e — e a verificacao exige comprovante de endereco, que o
-- back-office confere.
--
-- Corpos das RPCs extraidos VERBATIM das definicoes vigentes (approve da
-- 20260718200000; fetch da 20260721120000 — preservando avatar e destaque).

-- ---------------------------------------------------------------------------
-- 1. Colunas (com sanidade: cep = 8 digitos; lat/lng em faixa e aos pares)
-- ---------------------------------------------------------------------------

alter table public.law_firm_verifications
  add column if not exists cep text,
  add column if not exists latitude double precision,
  add column if not exists longitude double precision;

alter table public.law_firm_verifications
  add constraint law_firm_verifications_cep_chk
    check (cep is null or cep ~ '^[0-9]{8}$'),
  add constraint law_firm_verifications_lat_chk
    check (latitude is null or (latitude between -90 and 90)),
  add constraint law_firm_verifications_lng_chk
    check (longitude is null or (longitude between -180 and 180)),
  add constraint law_firm_verifications_coords_pair_chk
    check ((latitude is null) = (longitude is null));

alter table public.law_firms
  add column if not exists cep text,
  add column if not exists latitude double precision,
  add column if not exists longitude double precision;

alter table public.law_firms
  add constraint law_firms_cep_chk
    check (cep is null or cep ~ '^[0-9]{8}$'),
  add constraint law_firms_lat_chk
    check (latitude is null or (latitude between -90 and 90)),
  add constraint law_firms_lng_chk
    check (longitude is null or (longitude between -180 and 180)),
  add constraint law_firms_coords_pair_chk
    check ((latitude is null) = (longitude is null));

-- ---------------------------------------------------------------------------
-- 2. O formulario pode gravar os campos novos (grants por coluna sao
--    aditivos; o restante do modelo da 20260718200000 fica intacto)
-- ---------------------------------------------------------------------------

grant insert (cep, latitude, longitude)
on public.law_firm_verifications to authenticated;

grant update (cep, latitude, longitude)
on public.law_firm_verifications to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Aprovacao copia cep/lat/lng para law_firms
-- ---------------------------------------------------------------------------

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
      cep,
      latitude,
      longitude,
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
      nullif(verification_row.cep, ''),
      verification_row.latitude,
      verification_row.longitude,
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
      cep = coalesce(nullif(verification_row.cep, ''), firm.cep),
      latitude = coalesce(verification_row.latitude, firm.latitude),
      longitude = coalesce(verification_row.longitude, firm.longitude),
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


-- ---------------------------------------------------------------------------
-- 4. Descoberta devolve as coordenadas do escritorio (return type muda:
--    drop + create + re-grant)
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
    eligible.created_at desc
  limit least(greatest(coalesce(limit_value, 10), 1), 30);
$$;


revoke all on function public.fetch_recommended_law_firms(int, text)
from public, anon;

grant execute on function public.fetch_recommended_law_firms(int, text)
to authenticated;

notify pgrst, 'reload schema';
