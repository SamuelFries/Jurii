-- A fila da revisão tem teto.
--
-- A 20260919120000 revogou a escrita direta em lawyer_verifications, e com
-- isso submit_lawyer_verification virou a ÚNICA porta da fila que a equipe
-- Jurii revisa à mão. Ela não tinha teto: nem trava por usuário, nem
-- contagem de envios recentes, nem constraint que impedisse repetição. Uma
-- conta autenticada enfileirava milhares de verificações em minutos, e a
-- fila deixava de ser trabalhável. Não é invasão, é negar o serviço a quem
-- está esperando aprovação para trabalhar.
--
-- O teto segue o desenho que já existe em criar_link_de_convite: trava
-- (pg_advisory_xact_lock) antes da contagem, para chamadas simultâneas não
-- passarem todas pela conferência antes de qualquer uma gravar. Cinco por
-- hora é folgado para quem digita a OAB errada e refaz, e curto para quem
-- está automatizando.
--
-- O corpo abaixo é o vigente com o bloco novo inserido logo depois da
-- checagem de sessão; nada mais mudou.

CREATE OR REPLACE FUNCTION public.submit_lawyer_verification(oab_number_value text, oab_state_value text, practice_area_value text, practice_areas_value text[] DEFAULT NULL::text[])
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

  -- ANTIFLOOD. Depois que a escrita direta em lawyer_verifications foi
  -- revogada (20260919120000), esta função virou a ÚNICA porta da fila que a
  -- equipe Jurii revisa à mão. Sem teto, uma conta enfileira milhares de
  -- envios em minutos e a fila deixa de ser trabalhável, que é negar o
  -- serviço sem invadir nada.
  --
  -- Mesmo desenho de criar_link_de_convite: trava por usuário primeiro, para
  -- N chamadas simultâneas não passarem todas pela contagem antes de
  -- qualquer uma gravar.
  perform pg_catalog.pg_advisory_xact_lock(
    17002,
    pg_catalog.hashtext(user_id_value::text)
  );

  -- Cinco por hora é folgado para quem erra a OAB e refaz, e curto para quem
  -- está automatizando.
  if (
    select count(*)
    from public.lawyer_verifications recente
    where recente.user_id = user_id_value
      and recente.submitted_at >= now() - interval '1 hour'
  ) >= 5 then
    raise exception 'Too many verification attempts. Try again later';
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

  -- Traduz apelido antes de validar. Aqui NAO ha clausula de avo: verificacao
  -- e cadastro novo, e cadastro novo entra so no vocabulario canonico.
  normalized_practice_areas :=
    public.canonical_practice_areas(normalized_practice_areas);
  normalized_practice_area :=
    (public.canonical_practice_areas(array[normalized_practice_area]))[1];

  if normalized_practice_area is not null
      and not (normalized_practice_area = any(normalized_practice_areas)) then
    normalized_practice_areas :=
      array[normalized_practice_area] || normalized_practice_areas;
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
$function$

;
