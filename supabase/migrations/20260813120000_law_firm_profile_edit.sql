-- Editar o perfil do escritorio, como o advogado ja edita o dele.
--
-- Ate aqui "Dados do escritorio" era um item de menu que abria um aviso de "em
-- breve": depois de aprovado, nada do cadastro podia ser corrigido. Telefone
-- trocado, mudanca de endereco ou erro de digitacao no nome ficavam para
-- sempre — e o endereco alimenta a ordenacao por distancia da descoberta.
--
-- O QUE NAO ENTRA, de proposito:
--   CNPJ  vive em law_firm_verifications e e a identidade verificada. Mesmo
--         tratamento do CPF da pessoa fisica, que a tela de perfil ja trata
--         como imutavel: mudar exigiria nova verificacao, nao um formulario.

-- ---------------------------------------------------------------------------
-- 1. Logo do escritorio: caminho por FIRMA, nao por verificacao
--
--    O logo antigo vive em {dono}/{verificacao}/{arquivo} — endereco que so
--    faz sentido durante o cadastro, e que a policy de escrita fecha assim que
--    a verificacao sai de draft/pending. Para editar depois de aprovado, o
--    caminho passa a ser {escritorio}/{arquivo}: quem manda e o vinculo com a
--    FIRMA, nao quem por acaso abriu o cadastro. Isso tambem deixa um admin
--    trocar o logo — antes so o dono conseguiria, porque o proprio uid estava
--    no caminho.
-- ---------------------------------------------------------------------------

-- O CHECK de avatar_url so aceitava o caminho do CADASTRO
-- ({dono}/{verificacao}/{arquivo}). O caminho por firma tem uma pasta so, e
-- sem esta mudanca a gravacao estouraria no constraint. As duas formas passam
-- a valer: a antiga porque ja ha logo gravado assim, a nova para a edicao.
alter table public.law_firms
  drop constraint if exists law_firms_avatar_url_chk;

alter table public.law_firms
  add constraint law_firms_avatar_url_chk check (
    avatar_url is null
    or avatar_url ~ '^/storage/v1/object/public/law-firm-avatars/[0-9a-fA-F-]{36}/[0-9a-fA-F-]{36}/[A-Za-z0-9._-]{1,160}$'
    or avatar_url ~ '^/storage/v1/object/public/law-firm-avatars/[0-9a-fA-F-]{36}/[A-Za-z0-9._-]{1,160}$'
  );

create or replace function public.safe_law_firm_logo_url(
  law_firm_id_value uuid,
  storage_path_value text
)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when nullif(btrim(storage_path_value), '') is not null
      and storage_path_value ~ '^[0-9a-fA-F-]{36}/[A-Za-z0-9._-]{1,160}$'
      and split_part(storage_path_value, '/', 1) = law_firm_id_value::text
      and exists (
        select 1
        from storage.objects stored_object
        where stored_object.bucket_id = 'law-firm-avatars'
          and stored_object.name = storage_path_value
      )
    then '/storage/v1/object/public/law-firm-avatars/' || storage_path_value
    else null
  end;
$$;

revoke all on function public.safe_law_firm_logo_url(uuid, text)
from public, anon;
grant execute on function public.safe_law_firm_logo_url(uuid, text)
to authenticated;

drop policy if exists law_firm_logo_manager_insert on storage.objects;

create policy law_firm_logo_manager_insert
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'law-firm-avatars'
  and name ~ '^[0-9a-fA-F-]{36}/[A-Za-z0-9._-]{1,160}$'
  -- Gestor ATIVO da firma dona da pasta. Nao e "o dono": secretaria promovida
  -- a admin tambem cuida do cadastro, e o servidor ja usa este mesmo portao
  -- para a apresentacao e para o painel de alcance.
  and public.is_active_law_firm_manager(
    ((storage.foldername(name))[1])::uuid
  )
);

drop policy if exists law_firm_logo_manager_delete on storage.objects;

create policy law_firm_logo_manager_delete
on storage.objects for delete
to authenticated
using (
  bucket_id = 'law-firm-avatars'
  and name ~ '^[0-9a-fA-F-]{36}/[A-Za-z0-9._-]{1,160}$'
  and public.is_active_law_firm_manager(
    ((storage.foldername(name))[1])::uuid
  )
);

-- ---------------------------------------------------------------------------
-- 2. Edicao do cadastro
-- ---------------------------------------------------------------------------

drop function if exists public.update_law_firm_profile(
  uuid, text, text, text, text, text, text, double precision, double precision,
  text, text[], text, text
);

create function public.update_law_firm_profile(
  law_firm_id_value uuid,
  name_value text,
  phone_value text default null,
  email_value text default null,
  website_url_value text default null,
  address_value text default null,
  cep_value text default null,
  latitude_value double precision default null,
  longitude_value double precision default null,
  primary_area_value text default null,
  practice_areas_value text[] default null,
  avatar_action_value text default 'preserve',
  avatar_storage_path_value text default null
)
-- Devolve a linha COMPLETA do escritorio, e nao so o que mudou: o app
-- reconstroi o LawFirm com o mesmo parser da descoberta, que exige rating,
-- reviews_count e avatar_type. Devolver parcial daria erro de cast nulo na
-- tela logo depois de salvar com sucesso.
returns table (
  id uuid,
  name text,
  initials text,
  specialty text,
  practice_areas text[],
  description text,
  phone text,
  email text,
  website_url text,
  address text,
  cep text,
  latitude double precision,
  longitude double precision,
  avatar_url text,
  avatar_type text,
  rating numeric,
  reviews_count integer
)
language plpgsql
volatile
security definer
set search_path = public
as $$
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

  if cardinality(clean_areas) > 0 then
    select area into invalid_area
    from unnest(clean_areas) as area
    where not exists (
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
$$;

revoke all on function public.update_law_firm_profile(
  uuid, text, text, text, text, text, text, double precision, double precision,
  text, text[], text, text
) from public, anon;

grant execute on function public.update_law_firm_profile(
  uuid, text, text, text, text, text, text, double precision, double precision,
  text, text[], text, text
) to authenticated;

notify pgrst, 'reload schema';
