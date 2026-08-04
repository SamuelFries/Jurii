-- Areas de atuacao: allowlist no banco e peso da area PRINCIPAL na busca.
--
-- DOIS PROBLEMAS DISTINTOS, so um deles e de produto:
--
-- (a) BUG. `authenticated` tinha UPDATE direto em lawyer_profiles.practice_areas
--     sem validacao nenhuma. Reproduzido no banco local: da para gravar
--     'QUALQUER COISA QUE EU QUISER' como area de atuacao. Isso nao e escolha
--     de ninguem, e defeito: quebra o casamento por area da busca e das
--     categorias populares, que comparam a area normalizada. A allowlist e
--     obrigatoria independente de quantas areas o advogado possa marcar.
--
-- (b) INCENTIVO. Marcar todas as areas fazia o advogado aparecer em todas as
--     buscas sem custo. NAO limitamos a quantidade de propósito: advogado
--     generalista e realidade, principalmente fora das capitais, e um teto
--     puniria quem de fato atende varias areas. O que muda e o RANKING: entre
--     os relevantes, quem tem a area buscada como PRINCIPAL vem antes de quem
--     apenas a incluiu na lista. Generalista continua achavel; especialista
--     ganha a posicao que merece na sua area.
--
-- A tabela de areas vira DADO, nao codigo: adicionar area passa a ser INSERT,
-- e o app segue com a mesma lista em legal_practice_areas.dart (barreira de
-- teste garante que as duas nao divergem).

create table if not exists public.legal_practice_areas (
  name text primary key,
  created_at timestamptz not null default now()
);

insert into public.legal_practice_areas (name) values
  ('Direito Trabalhista'),
  ('Direito de Família'),
  ('Direito do Consumidor'),
  ('Direito Previdenciário'),
  ('Direito Imobiliário'),
  ('Direito Criminal'),
  ('Direito Empresarial'),
  ('Direito Tributário'),
  ('Direito Cível'),
  ('Direito Digital')
on conflict (name) do nothing;

alter table public.legal_practice_areas enable row level security;

drop policy if exists legal_practice_areas_read on public.legal_practice_areas;
create policy legal_practice_areas_read
on public.legal_practice_areas for select
to authenticated
using (true);

revoke all on table public.legal_practice_areas from public, anon;
grant select on table public.legal_practice_areas to authenticated;

-- ---------------------------------------------------------------------------
-- Escrita por RPC: a coluna perde o UPDATE direto.
-- ---------------------------------------------------------------------------
create or replace function public.update_lawyer_practice_areas(
  primary_area_value text,
  practice_areas_value text[]
)
returns text[]
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  clean_primary text := nullif(btrim(coalesce(primary_area_value, '')), '');
  clean_areas text[];
  invalid_area text;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if clean_primary is null then
    raise exception 'Primary area is required';
  end if;

  -- Apara CADA valor (não só descarta os vazios: sem o btrim aqui,
  -- '  Direito Cível  ' chegaria cru na allowlist e seria recusado como
  -- área inválida), remove duplicatas e ordena alfabeticamente.
  select array_agg(distinct btrim(area) order by btrim(area))
  into clean_areas
  from unnest(coalesce(practice_areas_value, array[]::text[])) as area
  where nullif(btrim(area), '') is not null;

  clean_areas := coalesce(clean_areas, array[]::text[]);

  -- A area principal SEMPRE faz parte da lista: sem isso o advogado poderia
  -- ter primaria fora das areas atendidas e sumir da propria busca.
  if not (clean_primary = any(clean_areas)) then
    clean_areas := clean_areas || clean_primary;
  end if;

  -- Allowlist: qualquer valor fora da tabela derruba a chamada inteira,
  -- nomeando o culpado (o app precisa saber qual recusar).
  select area into invalid_area
  from unnest(clean_areas) as area
  where not exists (
    select 1 from public.legal_practice_areas lpa where lpa.name = area
  )
  limit 1;

  if invalid_area is not null then
    raise exception 'Invalid practice area: %', invalid_area;
  end if;

  update public.lawyer_profiles
  set primary_area = clean_primary,
      practice_areas = clean_areas
  where id = auth.uid();

  if not found then
    raise exception 'Lawyer profile not found';
  end if;

  return clean_areas;
end;
$$;

-- A RPC passa a ser o unico caminho de escrita (mesmo movimento da bio).
revoke update (practice_areas) on public.lawyer_profiles from authenticated;

revoke all on function public.update_lawyer_practice_areas(text, text[])
from public, anon;
grant execute on function public.update_lawyer_practice_areas(text, text[])
to authenticated;

-- ---------------------------------------------------------------------------
-- Ranking: especialista antes de generalista, dentro dos relevantes.
-- Corpo VERBATIM da definicao vigente; muda so o campo novo e o ORDER BY.
-- ---------------------------------------------------------------------------
drop function public.fetch_recommended_lawyers(int, text, int);

create function public.fetch_recommended_lawyers(limit_value integer DEFAULT 6, search_value text DEFAULT NULL::text, offset_value integer DEFAULT 0)
 RETURNS TABLE(id uuid, full_name text, initials text, oab_number text, oab_state text, primary_area text, practice_areas text[], bio text, rating numeric, reviews_count integer, avatar_type text, avatar_url text, is_featured boolean)
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
    eligible.is_featured
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


-- ---------------------------------------------------------------------------
-- A porta da VERIFICACAO tambem valida: submit_lawyer_verification so aparava
-- e desduplicava, aceitando qualquer string. Corpo verbatim; entra so o
-- bloco da allowlist.
-- ---------------------------------------------------------------------------
create or replace function public.submit_lawyer_verification(oab_number_value text, oab_state_value text, practice_area_value text, practice_areas_value text[] DEFAULT NULL::text[])
 RETURNS TABLE(id uuid, user_id uuid, oab_number text, oab_state character, practice_area text, practice_areas text[], status verification_status, submitted_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  -- Allowlist tambem AQUI: fechar so a RPC de edicao deixaria a porta da
  -- verificacao aberta para o mesmo stuffing, e approve_lawyer_verification
  -- copia estas areas para lawyer_profiles.
  if exists (
    select 1
    from unnest(normalized_practice_areas) as area
    where not exists (
      select 1 from public.legal_practice_areas lpa where lpa.name = area
    )
  ) then
    raise exception 'Invalid practice area: %', (
      select area from unnest(normalized_practice_areas) as area
      where not exists (
        select 1 from public.legal_practice_areas lpa where lpa.name = area
      )
      limit 1
    );
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
$function$;

notify pgrst, 'reload schema';
