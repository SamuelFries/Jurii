-- Numero e complemento do endereco em campos proprios.
--
-- POR QUE. O endereco do escritorio e um campo de texto livre que o CEP
-- preenche com "Rua, Bairro, Cidade - UF". O que o CEP nao sabe — numero e
-- complemento — ficava enfiado no meio da mesma frase, do jeito que cada um
-- escreveu: "70 - 1102", "n 70 sala 1102", "70/1102". Tres problemas nisso:
--
--   1. O cliente precisa do numero para CHEGAR no escritorio. Numero escrito
--      de forma ambigua e cliente na porta errada.
--   2. Reeditar o cadastro nao conseguia separar o que era rua do que era
--      numero, entao o CEP nunca podia recorrigir a rua sem apagar o numero
--      junto (e por isso o preenchimento automatico so age em campo vazio).
--   3. 18 dos 39 escritorios de producao dividem CEP com outro. Para quase
--      metade da base, numero e complemento sao a UNICA coisa que distingue
--      um escritorio do outro.
--
-- MEDIDO (07/08/2026): o numero tambem melhora a coordenada. Para o CEP
-- 90540140, o centroide da rua e o numero 70 ficam a 305 m um do outro. Nao
-- muda a decisao de ninguem num rotulo de "2,3 km", mas e de graca: quando o
-- numero existe, a geocodificacao passa a usa-lo (com queda para a rua se o
-- numero nao estiver mapeado — testado, 4 de 5 resolvem dos dois jeitos).
--
-- OPCIONAIS. Existe "s/n", existe "Km 12", existe escritorio rural. Exigir o
-- numero faria a pessoa inventar um para o formulario deixar salvar, e numero
-- inventado e pior que ausente porque parece certo.
--
-- SEM MIGRACAO DE DADOS. `address` continua sendo o que e hoje; as colunas
-- novas nascem nulas. Os 40 cadastros existentes continuam exibindo
-- exatamente o que exibem — quem quiser separar o numero faz na proxima
-- edicao. Nao ha parser de texto livre aqui de proposito: com metade da base
-- dividindo CEP, um parser errado nao produz endereco feio, produz endereco
-- de OUTRO escritorio.

alter table public.law_firms
  add column if not exists address_number text,
  add column if not exists address_complement text;

alter table public.law_firm_verifications
  add column if not exists address_number text,
  add column if not exists address_complement text;

-- law_firm_verifications tem INSERT coluna a coluna (20260718200000): coluna
-- nova sem grant e "permission denied" no primeiro cadastro real, e teste de
-- widget nao pega isso porque nem chega no banco.
grant insert (address_number, address_complement)
on public.law_firm_verifications to authenticated;

-- ---------------------------------------------------------------------------
-- A RPC de edicao passa a gravar os dois campos. drop + create porque o
-- RETURNS TABLE mudou (create or replace nao aceita) — e drop ZERA os grants,
-- restaurados no fim.
-- ---------------------------------------------------------------------------
drop function public.update_law_firm_profile(
  uuid, text, text, text, text, text, text, double precision, double precision,
  text, text[], text, text
);

create function public.update_law_firm_profile(law_firm_id_value uuid, name_value text, phone_value text DEFAULT NULL::text, email_value text DEFAULT NULL::text, website_url_value text DEFAULT NULL::text, address_value text DEFAULT NULL::text, cep_value text DEFAULT NULL::text, latitude_value double precision DEFAULT NULL::double precision, longitude_value double precision DEFAULT NULL::double precision, primary_area_value text DEFAULT NULL::text, practice_areas_value text[] DEFAULT NULL::text[], avatar_action_value text DEFAULT 'preserve'::text, avatar_storage_path_value text DEFAULT NULL::text, address_number_value text DEFAULT NULL::text, address_complement_value text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, name text, initials text, specialty text, practice_areas text[], description text, phone text, email text, website_url text, address text, address_number text, address_complement text, cep text, latitude double precision, longitude double precision, avatar_url text, avatar_type text, rating numeric, reviews_count integer)
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
  clean_number text;
  clean_complement text;
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

  -- Numero e complemento sao OPCIONAIS de proposito: existe "s/n", existe
  -- "Km 12", e existe escritorio rural sem numero nenhum. Exigi-los faria a
  -- pessoa inventar um numero para o formulario deixar salvar — e numero
  -- inventado e pior que numero ausente, porque parece certo.
  clean_number := nullif(btrim(coalesce(address_number_value, '')), '');
  clean_complement := nullif(btrim(coalesce(address_complement_value, '')), '');
  if length(coalesce(clean_number, '')) > 20 then
    raise exception 'Address number is too long';
  end if;
  if length(coalesce(clean_complement, '')) > 60 then
    raise exception 'Address complement is too long';
  end if;

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

  -- Traduz apelido antes de validar (mesmo movimento do advogado): sem isto,
  -- o escritorio gravado como "Direito do Trabalho" continuaria fora da busca
  -- de quem filtra "Direito Trabalhista", que e a mesma area.
  clean_areas := public.canonical_practice_areas(clean_areas);
  clean_primary := (public.canonical_practice_areas(array[clean_primary]))[1];

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
  select public.canonical_practice_areas(
           coalesce(firm.practice_areas, array[]::text[])
         )
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
    address_number = clean_number,
    address_complement = clean_complement,
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
    firm.address_number,
    firm.address_complement,
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
$function$
;

revoke all on function public.update_law_firm_profile(
  uuid, text, text, text, text, text, text, double precision, double precision,
  text, text[], text, text, text, text
) from public, anon;

grant execute on function public.update_law_firm_profile(
  uuid, text, text, text, text, text, text, double precision, double precision,
  text, text[], text, text, text, text
) to authenticated;

-- ---------------------------------------------------------------------------
-- A aprovacao copia os campos novos para o escritorio. Sem isto, todo
-- escritorio aprovado nasceria sem numero — e a aprovacao devolveria sucesso.
-- ---------------------------------------------------------------------------
create or replace function public.approve_law_firm_verification(verification_id_value uuid, reviewer_id_value uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
      address_number,
      address_complement,
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
      nullif(verification_row.address_number, ''),
      nullif(verification_row.address_complement, ''),
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
      address_number = nullif(verification_row.address_number, ''),
      address_complement = nullif(verification_row.address_complement, ''),
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
$function$
;

notify pgrst, 'reload schema';
