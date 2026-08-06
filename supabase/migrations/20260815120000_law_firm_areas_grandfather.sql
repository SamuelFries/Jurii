-- A allowlist de areas so vale para area NOVA.
--
-- REPRODUZIDO EM PRODUCAO: tentar salvar o cadastro de um escritorio devolvia
-- "Uma das areas escolhidas nao e valida" — e nao dava para consertar, porque
-- a area culpada nao aparecia na tela.
--
-- Causa: os escritorios foram cadastrados antes de legal_practice_areas
-- existir (20260805180000), com area em texto livre. Contando producao agora:
--
--     39 dos 40 escritorios tem ao menos uma area fora da lista
--     31x "Direito do Trabalho"   (a lista tem "Direito Trabalhista")
--     24x "Direito Civil"         (a lista tem "Direito Civel")
--      5x "Direito Bancario"      (nao existe na lista)
--     ... e mais 25 valores distintos
--
-- A validacao rodava sobre o array INTEIRO, no mesmo caminho que grava nome,
-- telefone e endereco. Resultado: para corrigir um telefone era preciso antes
-- consertar uma taxonomia que o usuario nao via — o seletor da tela desenha
-- so as areas canonicas, entao as antigas iam junto, invisiveis, e voltavam
-- recusadas.
--
-- A regra passa a ser: o que JA ESTAVA gravado passa; o que esta sendo
-- ACRESCENTADO tem que estar na lista. Ninguem fica preso, ninguem perde area
-- em silencio, e area nova continua entrando so pelo vocabulario canonico.
--
-- FICA REGISTRADO o que isto NAO resolve: a lista de 10 areas e pequena demais
-- para a realidade — "Direito Bancario", "Direito Ambiental", "Direito
-- Administrativo" e "Direito Agrario" sao areas legitimas e ficaram de fora.
-- Aumentar a lista e decisao de produto (mexe no casamento da busca e no fluxo
-- do advogado tambem), entao nao e feito aqui.

create or replace function public.update_law_firm_profile(law_firm_id_value uuid, name_value text, phone_value text DEFAULT NULL::text, email_value text DEFAULT NULL::text, website_url_value text DEFAULT NULL::text, address_value text DEFAULT NULL::text, cep_value text DEFAULT NULL::text, latitude_value double precision DEFAULT NULL::double precision, longitude_value double precision DEFAULT NULL::double precision, primary_area_value text DEFAULT NULL::text, practice_areas_value text[] DEFAULT NULL::text[], avatar_action_value text DEFAULT 'preserve'::text, avatar_storage_path_value text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, name text, initials text, specialty text, practice_areas text[], description text, phone text, email text, website_url text, address text, cep text, latitude double precision, longitude double precision, avatar_url text, avatar_type text, rating numeric, reviews_count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  clean_name text;
  clean_initials text;
  clean_phone text;
  clean_email text;
  clean_website text;
  clean_address text;
  clean_cep text;
  clean_primary text;
  clean_areas text[];
  invalid_area text;
  current_areas text[];
  next_avatar_url text;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  -- Mesmo portao da apresentacao e do painel: quem fala pelo escritorio.
  if not public.is_active_law_firm_manager(law_firm_id_value) then
    raise exception 'Not allowed';
  end if;

  clean_name := nullif(btrim(coalesce(name_value, '')), '');
  if clean_name is null then
    raise exception 'Firm name is required';
  end if;
  if length(clean_name) > 120 then
    raise exception 'Firm name is too long';
  end if;

  -- As iniciais acompanham o nome. Sem isto, corrigir o nome deixaria o
  -- avatar de letras mostrando as iniciais antigas para sempre.
  clean_initials := upper(
    coalesce(
      substr(split_part(clean_name, ' ', 1), 1, 1) ||
        nullif(
          substr(
            split_part(clean_name, ' ', greatest(
              array_length(string_to_array(btrim(clean_name), ' '), 1), 1
            )),
            1, 1
          ),
          substr(split_part(clean_name, ' ', 1), 1, 1)
        ),
      substr(clean_name, 1, 2)
    )
  );

  clean_phone := nullif(regexp_replace(coalesce(phone_value, ''), '\D', '', 'g'), '');
  if clean_phone is not null and length(clean_phone) not in (10, 11) then
    raise exception 'Invalid phone';
  end if;

  clean_email := lower(nullif(btrim(coalesce(email_value, '')), ''));
  if clean_email is not null and clean_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'Invalid email';
  end if;

  clean_website := nullif(btrim(coalesce(website_url_value, '')), '');
  clean_address := nullif(btrim(coalesce(address_value, '')), '');

  clean_cep := nullif(regexp_replace(coalesce(cep_value, ''), '\D', '', 'g'), '');
  if clean_cep is not null and length(clean_cep) <> 8 then
    raise exception 'Invalid cep';
  end if;

  -- Coordenada e par ou nada: meia coordenada quebraria a ordenacao por
  -- distancia da descoberta em vez de simplesmente nao ordenar.
  if (latitude_value is null) <> (longitude_value is null) then
    raise exception 'Coordinates must come in pairs';
  end if;
  if latitude_value is not null
     and (latitude_value not between -90 and 90
          or longitude_value not between -180 and 180) then
    raise exception 'Coordinates out of range';
  end if;

  -- Areas: mesma allowlist do advogado (20260805180000). Sem ela, area
  -- inventada quebraria o casamento por area da busca e das categorias.
  clean_primary := nullif(btrim(coalesce(primary_area_value, '')), '');

  select array_agg(distinct area order by area)
  into clean_areas
  from unnest(coalesce(practice_areas_value, array[]::text[])) as area
  where nullif(btrim(area), '') is not null;

  clean_areas := coalesce(clean_areas, array[]::text[]);

  if clean_primary is not null and not (clean_primary = any(clean_areas)) then
    clean_areas := clean_areas || clean_primary;
  end if;

  -- A allowlist vale para area NOVA, nao para a que ja estava.
  --
  -- Os escritorios foram cadastrados antes de legal_practice_areas existir, com
  -- area em texto livre: "Direito do Trabalho", "Direito Bancario", "Direito
  -- Agrario". Validar o array inteiro travava 39 dos 40 escritorios em
  -- producao — e travava em TUDO, porque a checagem roda no mesmo caminho que
  -- grava telefone e endereco. Corrigir o telefone exigia primeiro consertar
  -- uma taxonomia que o usuario nem via na tela.
  --
  -- Entao: o que ja estava gravado passa; o que esta sendo ACRESCENTADO tem
  -- que estar na lista. Assim ninguem fica preso, ninguem perde area em
  -- silencio, e area nova continua entrando so pelo vocabulario canonico.
  select coalesce(firm.practice_areas, array[]::text[])
  into current_areas
  from public.law_firms firm
  where firm.id = law_firm_id_value;

  current_areas := coalesce(current_areas, array[]::text[]);

  if cardinality(clean_areas) > 0 then
    select area into invalid_area
    from unnest(clean_areas) as area
    where not (area = any(current_areas))
      and not exists (
        select 1 from public.legal_practice_areas lpa where lpa.name = area
      )
    limit 1;

    if invalid_area is not null then
      raise exception 'Invalid practice area: %', invalid_area;
    end if;
  end if;

  if avatar_action_value not in ('preserve', 'replace', 'remove') then
    raise exception 'Invalid avatar action';
  end if;

  if avatar_action_value = 'remove' then
    next_avatar_url := null;
  elsif avatar_action_value = 'replace' then
    next_avatar_url := public.safe_law_firm_logo_url(
      law_firm_id_value,
      avatar_storage_path_value
    );
    -- Caminho que nao passa na validacao (pasta de outra firma, arquivo que
    -- nao subiu) nao pode virar avatar_url quebrado no cartao de todo mundo.
    if next_avatar_url is null then
      raise exception 'Invalid avatar path';
    end if;
  else
    select firm.avatar_url into next_avatar_url
    from public.law_firms firm
    where firm.id = law_firm_id_value;
  end if;

  update public.law_firms firm
  set
    name = clean_name,
    initials = clean_initials,
    phone = clean_phone,
    email = clean_email,
    website_url = clean_website,
    address = clean_address,
    cep = clean_cep,
    latitude = latitude_value,
    longitude = longitude_value,
    specialty = coalesce(clean_primary, firm.specialty),
    practice_areas = case
      when cardinality(clean_areas) > 0 then clean_areas
      else firm.practice_areas
    end,
    avatar_url = next_avatar_url,
    updated_at = now()
  where firm.id = law_firm_id_value;

  if not found then
    raise exception 'Law firm not found';
  end if;

  return query
  select
    firm.id,
    firm.name,
    firm.initials,
    firm.specialty,
    firm.practice_areas,
    firm.description,
    firm.phone,
    firm.email,
    firm.website_url,
    firm.address,
    firm.cep,
    firm.latitude,
    firm.longitude,
    firm.avatar_url,
    firm.avatar_type,
    firm.rating,
    firm.reviews_count
  from public.law_firms firm
  where firm.id = law_firm_id_value;
end;
$function$;

notify pgrst, 'reload schema';
