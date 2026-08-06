-- A taxonomia de areas do direito passa de 10 para 39, com tabela de apelidos.
--
-- MEDIDO EM PRODUCAO (06/08/2026), antes desta migration:
--
--     33 dos 41 advogados e 39 dos 40 escritorios tinham ao menos uma area
--     fora da lista — 31 valores distintos:
--
--       83x "Direito do Trabalho"      (a lista tem "Direito Trabalhista")
--       52x "Direito Civil"            (a lista tem "Direito Civel")
--       12x "Direito Bancario"          nao existia
--       12x "Direito das Sucessoes"     nao existia (+ "Direito Sucessorio")
--        8x "Direito de Familia e Sucessoes"  = DUAS areas num campo so
--        6x "Direito Administrativo"    nao existia
--        5x "Direito Agrario"           nao existia
--        5x "Direito Ambiental"         nao existia
--       ... e mais 23 valores
--
-- Sao DOIS problemas diferentes com a mesma cara, e a migration anterior
-- (20260815120000) so tratou o sintoma:
--
--   (a) APELIDO. "Direito do Trabalho" e "Direito Trabalhista" sao a MESMA
--       area escrita de dois jeitos. Guardar as duas grafias nao da opcao a
--       ninguem: quebra o casamento por area da busca (o cliente que filtra
--       "Direito Trabalhista" nao ve o advogado gravado como "Direito do
--       Trabalho") e faz a lista da tela mentir sobre o que o cadastro tem.
--
--   (b) AREA QUE FALTAVA. "Direito Bancario", "Ambiental", "Administrativo",
--       "Agrario", "Eleitoral", "Medico" sao areas legitimas que a lista de 10
--       simplesmente nao tinha. O cadastro empurrava todo mundo para dez
--       caixas que nao descrevem o que a pessoa faz.
--
-- (a) vira DADO: legal_practice_area_aliases mapeia grafia -> area canonica,
-- inclusive um-para-dois ("Direito de Familia e Sucessoes"). O mapa e aplicado
-- (1) uma vez sobre o que ja esta gravado e (2) em TODA escrita futura, nas
-- tres RPCs e no gatilho da verificacao de escritorio. Sem o (2) o problema
-- volta no proximo cadastro: ou e automatizado, ou e esquecido.
--
-- (b) vira lista: 29 areas novas, com termos de busca em linguagem de CLIENTE
-- ("meu pai morreu" -> Sucessoes, "seguradora negou" -> Securitario). Area sem
-- termo so seria achavel por quem digitasse o nome exato dela.
--
-- A lista do app (lib/data/legal_practice_areas.dart) e o seed daqui sao
-- GERADOS da mesma fonte; barreira de teste garante que nao divergem.

-- ---------------------------------------------------------------------------
-- 1. As 29 areas que faltavam.
-- ---------------------------------------------------------------------------
insert into public.legal_practice_areas (name) values
  ('Direito das Sucessões'),
  ('Direito Bancário'),
  ('Direito Médico e da Saúde'),
  ('Direito Administrativo'),
  ('Direito Securitário'),
  ('Direito da Criança e do Adolescente'),
  ('Direito do Idoso'),
  ('Direito Ambiental'),
  ('Direito Agrário'),
  ('Direito Urbanístico'),
  ('Direito Sindical'),
  ('Direito Eleitoral'),
  ('Direito Militar'),
  ('Direito Educacional'),
  ('Direito da Propriedade Intelectual'),
  ('Direito Notarial e Registral'),
  ('Direito Imigratório'),
  ('Direito Internacional'),
  ('Direito Constitucional'),
  ('Direito Penal Empresarial'),
  ('Direito Concorrencial'),
  ('Direito Aduaneiro'),
  ('Direito Regulatório'),
  ('Direito do Terceiro Setor'),
  ('Direito Cooperativo'),
  ('Direito Desportivo'),
  ('Direito Animal'),
  ('Direito Marítimo'),
  ('Direito Aeronáutico')
on conflict (name) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Apelidos: a grafia que o profissional escreveu -> a area canonica.
--
-- Um apelido pode virar DUAS areas: "Direito de Familia e Sucessoes" e um
-- campo so com duas areas dentro, e quebra-lo em duas e o unico jeito de o
-- profissional aparecer nas duas buscas.
-- ---------------------------------------------------------------------------
create table if not exists public.legal_practice_area_aliases (
  alias text primary key,
  normalized_alias text not null,
  canonical_names text[] not null,
  created_at timestamptz not null default now()
);

create unique index if not exists legal_practice_area_aliases_normalized_idx
on public.legal_practice_area_aliases (normalized_alias);

-- O gatilho normaliza a chave de busca e recusa apelido que aponte para area
-- inexistente. Sem ele, um typo no seed viraria um apelido que mapeia para o
-- nada — e o nada nao aparece em busca nenhuma, em silencio.
create or replace function public.legal_practice_area_alias_guard()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  alvo_invalido text;
begin
  new.alias := btrim(new.alias);
  if nullif(new.alias, '') is null then
    raise exception 'Alias cannot be empty';
  end if;

  new.normalized_alias := public.normalize_practice_area_search(new.alias);
  if nullif(new.normalized_alias, '') is null then
    raise exception 'Alias normalizes to empty: %', new.alias;
  end if;

  if cardinality(coalesce(new.canonical_names, array[]::text[])) = 0 then
    raise exception 'Alias % has no canonical target', new.alias;
  end if;

  select alvo into alvo_invalido
  from unnest(new.canonical_names) as alvo
  where not exists (
    select 1 from public.legal_practice_areas lpa where lpa.name = alvo
  )
  limit 1;

  if alvo_invalido is not null then
    raise exception 'Alias % points to unknown area: %',
      new.alias, alvo_invalido;
  end if;

  return new;
end;
$$;

drop trigger if exists legal_practice_area_aliases_guard
on public.legal_practice_area_aliases;
create trigger legal_practice_area_aliases_guard
before insert or update on public.legal_practice_area_aliases
for each row execute function public.legal_practice_area_alias_guard();

alter table public.legal_practice_area_aliases enable row level security;

drop policy if exists legal_practice_area_aliases_read
on public.legal_practice_area_aliases;
create policy legal_practice_area_aliases_read
on public.legal_practice_area_aliases for select
to authenticated
using (true);

revoke all on table public.legal_practice_area_aliases from public, anon;
grant select on table public.legal_practice_area_aliases to authenticated;

-- normalized_alias sai do gatilho: repetir a normalizacao aqui seria
-- convite a divergir da funcao que a busca usa.
insert into public.legal_practice_area_aliases (alias, canonical_names)
values
  ('Direito do Trabalho', array['Direito Trabalhista']),
  ('Direito Civil', array['Direito Cível']),
  ('Direito de Família e Sucessões', array['Direito de Família', 'Direito das Sucessões']),
  ('Direito Sucessório', array['Direito das Sucessões']),
  ('Direito Penal', array['Direito Criminal']),
  ('Direito Sindical e Coletivo', array['Direito Sindical']),
  ('Direito Processual Civil', array['Direito Cível']),
  ('Direito Societário', array['Direito Empresarial']),
  ('Direito Criminal Empresarial', array['Direito Penal Empresarial']),
  ('Ações Indenizatórias', array['Direito Cível']),
  ('Assessoria Jurídica Empresarial', array['Direito Empresarial']),
  ('Consultoria Jurídica Empresarial', array['Direito Empresarial']),
  ('Contratos', array['Direito Cível']),
  ('Direito à Saúde', array['Direito Médico e da Saúde']),
  ('Direito Médico', array['Direito Médico e da Saúde']),
  ('Direito Civil e de Família', array['Direito Cível', 'Direito de Família']),
  ('Direito Corporativo', array['Direito Empresarial']),
  ('Direito Patrimonial', array['Direito Cível']),
  ('Recuperação Judicial', array['Direito Empresarial']),
  ('Revisional de Juros', array['Direito Bancário']),
  ('Direito Processual do Trabalho', array['Direito Trabalhista']),
  ('Direito do Trabalho e Previdenciário', array['Direito Trabalhista', 'Direito Previdenciário']),
  ('Direito Trabalhista Empresarial', array['Direito Trabalhista']),
  ('Direito Coletivo do Trabalho', array['Direito Sindical']),
  ('Direito Processual Penal', array['Direito Criminal']),
  ('Direito Penal Econômico', array['Direito Penal Empresarial']),
  ('Direito das Famílias', array['Direito de Família']),
  ('Direito da Família', array['Direito de Família']),
  ('Sucessões', array['Direito das Sucessões']),
  ('Inventários', array['Direito das Sucessões']),
  ('Direito Consumerista', array['Direito do Consumidor']),
  ('Direito do Consumidor e Bancário', array['Direito do Consumidor', 'Direito Bancário']),
  ('Direito Bancário e Financeiro', array['Direito Bancário']),
  ('Direito Contratual', array['Direito Cível']),
  ('Responsabilidade Civil', array['Direito Cível']),
  ('Direito de Trânsito', array['Direito Cível']),
  ('Acidente de Trânsito', array['Direito Cível']),
  ('Direito Condominial', array['Direito Imobiliário']),
  ('Direito Locatício', array['Direito Imobiliário']),
  ('Direito Imobiliário e Urbanístico', array['Direito Imobiliário', 'Direito Urbanístico']),
  ('Direito Fiscal', array['Direito Tributário']),
  ('Direito Empresarial e Societário', array['Direito Empresarial']),
  ('Direito das Startups', array['Direito Empresarial']),
  ('Compliance', array['Direito Empresarial']),
  ('Direito Público', array['Direito Administrativo']),
  ('Direito Ambiental e Urbanístico', array['Direito Ambiental', 'Direito Urbanístico']),
  ('Direito Rural', array['Direito Agrário']),
  ('Direito do Agronegócio', array['Direito Agrário']),
  ('Direito da Saúde', array['Direito Médico e da Saúde']),
  ('Direito Hospitalar', array['Direito Médico e da Saúde']),
  ('Direito Odontológico', array['Direito Médico e da Saúde']),
  ('Direito da Infância e Juventude', array['Direito da Criança e do Adolescente']),
  ('Direito da Infância e da Juventude', array['Direito da Criança e do Adolescente']),
  ('Direito do Menor', array['Direito da Criança e do Adolescente']),
  ('Direito da Pessoa Idosa', array['Direito do Idoso']),
  ('Direito Migratório', array['Direito Imigratório']),
  ('Direito de Imigração', array['Direito Imigratório']),
  ('Direito Autoral', array['Direito da Propriedade Intelectual']),
  ('Direito Marcário', array['Direito da Propriedade Intelectual']),
  ('Propriedade Industrial', array['Direito da Propriedade Intelectual']),
  ('Marcas e Patentes', array['Direito da Propriedade Intelectual']),
  ('Direito Notarial', array['Direito Notarial e Registral']),
  ('Direito Registral', array['Direito Notarial e Registral']),
  ('Direito Eleitoral e Partidário', array['Direito Eleitoral']),
  ('Direito Penal Militar', array['Direito Militar']),
  ('Direito da Educação', array['Direito Educacional']),
  ('Direito Portuário', array['Direito Marítimo']),
  ('Direito Aeroviário', array['Direito Aeronáutico']),
  ('Direito dos Animais', array['Direito Animal']),
  ('Direito Securitário e de Seguros', array['Direito Securitário']),
  ('Direito de Seguros', array['Direito Securitário']),
  ('Direito da Concorrência', array['Direito Concorrencial']),
  ('Direito Antitruste', array['Direito Concorrencial']),
  ('Comércio Exterior', array['Direito Aduaneiro']),
  ('Direito Energético', array['Direito Regulatório']),
  ('Terceiro Setor', array['Direito do Terceiro Setor']),
  ('Cooperativismo', array['Direito Cooperativo']),
  ('Direito Digital e Proteção de Dados', array['Direito Digital']),
  ('Proteção de Dados', array['Direito Digital']),
  ('LGPD', array['Direito Digital']),
  ('Direito da Tecnologia', array['Direito Digital'])
on conflict (alias) do update set
  canonical_names = excluded.canonical_names;

-- ---------------------------------------------------------------------------
-- 3. A traducao, num lugar so.
--
-- Resolve nesta ordem: apelido conhecido -> area canonica com a grafia certa
-- (case/acento tolerante) -> o valor como veio. O ultimo caso e de proposito:
-- canonicalizar nao e validar. Quem decide se um valor desconhecido entra ou
-- nao e a allowlist, na RPC — aqui so traduzimos.
-- ---------------------------------------------------------------------------
create or replace function public.canonical_practice_areas(
  practice_areas_value text[]
)
returns text[]
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    array_agg(area order by primeira_posicao, primeira_subposicao, area),
    array[]::text[]
  )
  from (
    select
      area,
      min(posicao) as primeira_posicao,
      min(subposicao) as primeira_subposicao
    from (
      select
        coalesce(apelido.nome, canonica.name, entrada.area) as area,
        entrada.posicao,
        -- Desempate DENTRO do apelido: "Direito de Familia e Sucessoes" vira
        -- duas areas na mesma posicao, e a ordem tem que ser a que o apelido
        -- escreveu — primary_area/specialty ficam com a PRIMEIRA, e sortear
        -- qual das duas seria trocar a area principal de quem so corrigiu o
        -- telefone.
        coalesce(apelido.subposicao, 1) as subposicao
      from (
        select nullif(btrim(valor), '') as area, posicao
        from unnest(coalesce(practice_areas_value, array[]::text[]))
          with ordinality as t(valor, posicao)
      ) entrada
      left join lateral (
        select nomes.nome, nomes.subposicao
        from public.legal_practice_area_aliases a
        cross join unnest(a.canonical_names)
          with ordinality as nomes(nome, subposicao)
        where a.normalized_alias =
          public.normalize_practice_area_search(entrada.area)
      ) apelido on true
      left join lateral (
        select lpa.name
        from public.legal_practice_areas lpa
        where public.normalize_practice_area_search(lpa.name) =
          public.normalize_practice_area_search(entrada.area)
        limit 1
      ) canonica on apelido.nome is null
      where entrada.area is not null
    ) resolvido
    group by area
  ) distinto;
$$;

revoke all on function public.canonical_practice_areas(text[]) from public, anon;
grant execute on function public.canonical_practice_areas(text[]) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. O que ja esta gravado passa pelo mapa, uma vez.
--
-- Sem este passo os 33 advogados e 39 escritorios continuariam invisiveis para
-- quem filtra pela area canonica — a lista nova so serviria para quem se
-- cadastrasse depois. As colunas escalares (primary_area, specialty,
-- practice_area) ficam com a PRIMEIRA area do apelido: um campo que so cabe
-- uma nao pode receber duas.
--
-- NAO sao tocadas: conversations.specialty e legal_cases.area. Aquilo e
-- registro historico do caso, nao cadastro do profissional — reescrever a area
-- de um caso ja atendido e reescrever o que foi combinado. Nenhuma das duas
-- alimenta busca ou filtro.
-- ---------------------------------------------------------------------------
update public.lawyer_profiles
set practice_areas = public.canonical_practice_areas(practice_areas)
where practice_areas is not null
  and public.canonical_practice_areas(practice_areas)
      is distinct from practice_areas;

update public.lawyer_profiles
set primary_area = (public.canonical_practice_areas(array[primary_area]))[1]
where primary_area is not null
  and (public.canonical_practice_areas(array[primary_area]))[1]
      is distinct from primary_area;

update public.law_firms
set practice_areas = public.canonical_practice_areas(practice_areas)
where practice_areas is not null
  and public.canonical_practice_areas(practice_areas)
      is distinct from practice_areas;

update public.law_firms
set specialty = (public.canonical_practice_areas(array[specialty]))[1]
where specialty is not null
  and (public.canonical_practice_areas(array[specialty]))[1]
      is distinct from specialty;

update public.lawyer_verifications
set practice_areas = public.canonical_practice_areas(practice_areas)
where practice_areas is not null
  and public.canonical_practice_areas(practice_areas)
      is distinct from practice_areas;

update public.lawyer_verifications
set practice_area = (public.canonical_practice_areas(array[practice_area]))[1]
where practice_area is not null
  and (public.canonical_practice_areas(array[practice_area]))[1]
      is distinct from practice_area;

update public.law_firm_verifications
set practice_areas = public.canonical_practice_areas(practice_areas)
where practice_areas is not null
  and public.canonical_practice_areas(practice_areas)
      is distinct from practice_areas;

-- ---------------------------------------------------------------------------
-- 5. Toda escrita passa pelo mapa.
--
-- O passo 4 conserta o passado uma vez; sem este passo 5 o problema volta na
-- proxima verificacao enviada. Corpos VERBATIM das definicoes vigentes; muda
-- so o bloco de canonicalizacao.
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
  current_areas text[];
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

  -- Traduz apelido antes de validar: "Direito do Trabalho" e "Direito
  -- Trabalhista" sao a mesma area, e recusar a segunda grafia so ensinaria o
  -- advogado a evitar o formulario.
  clean_areas := public.canonical_practice_areas(clean_areas);
  clean_primary := (public.canonical_practice_areas(array[clean_primary]))[1];

  -- A area principal SEMPRE faz parte da lista: sem isso o advogado poderia
  -- ter primaria fora das areas atendidas e sumir da propria busca.
  if not (clean_primary = any(clean_areas)) then
    clean_areas := clean_areas || clean_primary;
  end if;

  -- Allowlist so para area NOVA — mesma regra do escritorio
  -- (20260815120000). Depois da migracao do passo 4 nenhum advogado deveria
  -- ter area fora da lista, mas se sobrar alguma ela nao pode travar a
  -- correcao das OUTRAS areas: seria pedir que a pessoa consertasse algo que
  -- a tela nem oferece.
  select coalesce(perfil.practice_areas, array[]::text[])
  into current_areas
  from public.lawyer_profiles perfil
  where perfil.id = auth.uid();

  current_areas := coalesce(current_areas, array[]::text[]);

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
$function$;

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

-- A verificacao de escritorio e o unico caminho de escrita que NAO passa por
-- RPC: o app insere direto na tabela, sob RLS. Gatilho, entao — deixar so este
-- caminho sem traducao seria manter a porta pela qual o problema entrou.
create or replace function public.law_firm_verification_canonical_areas()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.practice_areas := public.canonical_practice_areas(new.practice_areas);
  return new;
end;
$$;

drop trigger if exists law_firm_verifications_canonical_areas
on public.law_firm_verifications;
create trigger law_firm_verifications_canonical_areas
before insert or update of practice_areas on public.law_firm_verifications
for each row execute function public.law_firm_verification_canonical_areas();

-- ---------------------------------------------------------------------------
-- 6. Termos de busca livre das areas novas.
--
-- Espelho server-side de legalSearchIntentRules (o app filtra a demo com as
-- mesmas regras). Sem termo, a area nova so seria achavel por quem digitasse o
-- nome exato dela — e ninguem procura advogado digitando "Direito Securitario";
-- procura digitando "seguradora nao pagou".
--
-- O upsert reescreve tambem os termos que ja estavam: e o mesmo conteudo do
-- Dart, entao rodar de novo so faz o banco convergir para ele.
-- ---------------------------------------------------------------------------
with seed(practice_areas, weight, terms) as (
  values
    (
      array['Direito Trabalhista']::text[],
      120,
      array[
        'advogado trabalhista',
        'direito trabalhista',
        'trabalho',
        'emprego',
        'patrão',
        'empresa não pagou',
        'patrão não pagou',
        'chefe',
        'demissão',
        'fui demitido',
        'fui demitida',
        'me mandaram embora',
        'mandaram embora',
        'demitido sem receber',
        'demitida sem receber',
        'não recebi acerto',
        'acerto trabalhista',
        'acordo trabalhista',
        'rescisão',
        'rescisão trabalhista',
        'fgts',
        'fgts atrasado',
        'fgts não depositado',
        'não depositaram fgts',
        'horas extras',
        'hora extra',
        'banco de horas',
        'jornada de trabalho',
        'intervalo',
        'não tenho intervalo',
        'trabalho demais',
        'assédio moral',
        'humilhação no trabalho',
        'chefe humilha',
        'chefe grita',
        'perseguição no trabalho',
        'assédio sexual no trabalho',
        'chefe me assedia',
        'salário atrasado',
        'salário não pago',
        'pagamento atrasado',
        'décimo terceiro',
        '13 atrasado',
        'férias',
        'férias vencidas',
        'férias não pagas',
        'verbas rescisórias',
        'justa causa',
        'demissão por justa causa',
        'reverter justa causa',
        'carteira assinada',
        'trabalho sem carteira',
        'não assinaram carteira',
        'vínculo empregatício',
        'pejotização',
        'mei obrigado',
        'sou mei mas sou empregado',
        'autônomo mas empregado',
        'desvio de função',
        'acúmulo de função',
        'equiparação salarial',
        'adicional noturno',
        'periculosidade',
        'insalubridade',
        'acidente de trabalho',
        'doença ocupacional',
        'estabilidade gestante',
        'licença maternidade',
        'cipa',
        'sindicato',
        'doméstica',
        'empregada doméstica',
        'diarista',
        'motorista de aplicativo',
        'entregador de aplicativo',
        'processo trabalhista',
        'reclamação trabalhista',
        'direito do trabalho',
        'advogado do trabalho',
        'direito processual do trabalho',
        'justiça do trabalho'
      ]::text[]
    ),
    (
      array['Direito de Família']::text[],
      125,
      array[
        'advogado de família',
        'direito de família',
        'divórcio',
        'divorciar',
        'quero divorciar',
        'quero me separar',
        'separação',
        'separação amigável',
        'separação litigiosa',
        'divórcio amigável',
        'divórcio litigioso',
        'fim do casamento',
        'casamento acabou',
        'pensão alimentícia',
        'pensão',
        'pensão atrasada',
        'não paga pensão',
        'não pagou pensão',
        'pai não paga pensão',
        'mãe não paga pensão',
        'aumentar pensão',
        'diminuir pensão',
        'revisão de pensão',
        'execução de alimentos',
        'alimentos',
        'alimentos gravídicos',
        'guarda',
        'guarda compartilhada',
        'guarda unilateral',
        'guarda dos filhos',
        'pegar guarda',
        'perder guarda',
        'visitas',
        'direito de visita',
        'regulamentação de visitas',
        'mãe não deixa ver filho',
        'pai não deixa ver filho',
        'não consigo ver meu filho',
        'união estável',
        'dissolução de união estável',
        'contrato de união estável',
        'alienação parental',
        'partilha',
        'partilha de bens',
        'dividir bens',
        'bens do casal',
        'regime de bens',
        'pacto antenupcial',
        'paternidade',
        'reconhecimento de paternidade',
        'exame de dna',
        'dna',
        'nome do pai',
        'adoção',
        'adotar',
        'tutela',
        'curatela',
        'interdição familiar',
        'inventário familiar',
        'herança de família',
        'briga de herança',
        'testamento da família',
        'direito das famílias',
        'advogado familiarista'
      ]::text[]
    ),
    (
      array['Direito do Consumidor']::text[],
      115,
      array[
        'advogado consumidor',
        'direito do consumidor',
        'procon',
        'juizado consumidor',
        'pequenas causas consumidor',
        'produto defeituoso',
        'produto com defeito',
        'produto quebrado',
        'comprei e não chegou',
        'compra não chegou',
        'pedido não chegou',
        'loja não entregou',
        'atraso na entrega',
        'loja não troca',
        'troca negada',
        'garantia',
        'garantia negada',
        'cobrança indevida',
        'cobraram errado',
        'boleto indevido',
        'fatura errada',
        'cobrança abusiva',
        'juros abusivos',
        'nome sujo',
        'negativação',
        'negativação indevida',
        'serasa',
        'spc',
        'protesto indevido',
        'cartão de crédito',
        'cartão clonado',
        'plano de saúde',
        'convênio médico',
        'plano negou cirurgia',
        'plano negou tratamento',
        'plano negou exame',
        'cirurgia negada',
        'tratamento negado',
        'banco',
        'banco bloqueou conta',
        'conta bloqueada',
        'empréstimo não contratado',
        'empréstimo consignado',
        'desconto indevido',
        'financiamento',
        'consórcio',
        'seguro',
        'seguradora não paga',
        'viagem cancelada',
        'passagem cancelada',
        'voo cancelado',
        'voo atrasado',
        'bagagem extraviada',
        'overbooking',
        'hotel cancelado',
        'mensalidade',
        'faculdade',
        'escola',
        'curso online',
        'assinatura',
        'cancelar assinatura',
        'cobrança de assinatura',
        'telefone',
        'internet',
        'operadora',
        'energia elétrica',
        'conta de luz',
        'água',
        'conta de água',
        'marketplace',
        'app de entrega',
        'compra online',
        'propaganda enganosa',
        'fraude bancária',
        'pix errado',
        'golpe do pix',
        'direito consumerista'
      ]::text[]
    ),
    (
      array['Direito Previdenciário']::text[],
      115,
      array[
        'advogado previdenciário',
        'direito previdenciário',
        'previdência',
        'inss',
        'meu inss',
        'aposentadoria',
        'aposentadoria negada',
        'aposentar',
        'aposentadoria por idade',
        'aposentadoria por tempo',
        'aposentadoria especial',
        'tempo de contribuição',
        'revisão da aposentadoria',
        'revisão da vida toda',
        'auxílio doença',
        'auxílio por incapacidade',
        'benefício por incapacidade',
        'bpc',
        'loas',
        'benefício negado',
        'benefício cortado',
        'meu benefício foi cortado',
        'pente fino',
        'perícia',
        'perícia negada',
        'perícia médica',
        'laudo médico',
        'incapacidade',
        'auxílio acidente',
        'pensão por morte',
        'salário maternidade',
        'salario maternidade',
        'recurso inss',
        'indeferido inss',
        'pedido indeferido',
        'cnis',
        'contribuição não aparece',
        'tempo rural',
        'trabalhador rural',
        'segurado especial',
        'ppp',
        'insalubridade inss',
        'aposentadoria rural',
        'deficiente',
        'idoso bpc',
        'aposentadoria pessoa com deficiência'
      ]::text[]
    ),
    (
      array['Direito Cível']::text[],
      105,
      array[
        'advogado de trânsito',
        'direito de trânsito',
        'acidente de trânsito',
        'batida',
        'bati o carro',
        'bateram no meu carro',
        'bateram na minha moto',
        'colisão',
        'engavetamento',
        'acidente de carro',
        'acidente de moto',
        'acidente de ônibus',
        'acidente com uber',
        'acidente aplicativo',
        'atropelamento',
        'fui atropelado',
        'fui atropelada',
        'trânsito',
        'seguradora',
        'seguro do carro',
        'seguro não pagou',
        'indenização acidente',
        'danos no carro',
        'conserto do carro',
        'perda total',
        'dpvat',
        'boletim de acidente',
        'culpa no acidente',
        'motorista bêbado',
        'multa de trânsito',
        'multa de transito',
        'cnh suspensa',
        'cnh cassada',
        'pontos na carteira',
        'bafômetro',
        'recusei bafômetro',
        'lei seca',
        'carro apreendido',
        'guincho',
        'licenciamento',
        'recurso de multa',
        'advogado cível',
        'direito civil',
        'processo civil',
        'juizado especial',
        'pequenas causas',
        'indenização',
        'danos morais',
        'dano moral',
        'danos materiais',
        'dano material',
        'cobrança',
        'cobrar dívida',
        'alguém me deve',
        'me devem dinheiro',
        'calote',
        'levei calote',
        'emprestei dinheiro',
        'não me pagaram',
        'contrato',
        'quebra de contrato',
        'descumprimento de contrato',
        'rescisão de contrato',
        'responsabilidade civil',
        'erro médico',
        'erro odontológico',
        'acidente em loja',
        'queda em estabelecimento',
        'queda no mercado',
        'herança',
        'inventário',
        'testamento',
        'partilha de herança',
        'briga de herança',
        'registro civil',
        'alterar nome',
        'alteração de nome',
        'retificar documento',
        'retificação de registro',
        'interdição',
        'curatela',
        'vizinho',
        'briga com vizinho',
        'barulho de vizinho',
        'direito de imagem',
        'uso indevido de imagem',
        'calúnia',
        'injúria',
        'difamação',
        'cobrança judicial',
        'notificação extrajudicial',
        'contrato de compra e venda',
        'contrato de prestação de serviço',
        'advogado civil',
        'direito processual civil',
        'direito contratual',
        'direito patrimonial',
        'ações indenizatórias'
      ]::text[]
    ),
    (
      array['Direito Criminal']::text[],
      130,
      array[
        'advogado criminal',
        'advogado criminalista',
        'direito penal',
        'processo criminal',
        'processo penal',
        'acusado',
        'acusação',
        'acusaram',
        'réu',
        'réu primário',
        'vítima de crime',
        'crime',
        'crime grave',
        'denúncia criminal',
        'queixa crime',
        'Maria da Penha',
        'Lei Maria da Penha',
        'violência doméstica',
        'violência contra mulher',
        'violência contra a mulher',
        'violência familiar',
        'mulher agredida',
        'apanhei do marido',
        'marido bateu',
        'marido me bateu',
        'meu marido me bateu',
        'namorado me bateu',
        'ex me bateu',
        'ex me ameaça',
        'ex me ameaçou',
        'meu ex me persegue',
        'perseguição',
        'stalking',
        'medida protetiva',
        'descumpriu medida protetiva',
        'quebrou medida protetiva',
        'estupro',
        'estupro de vulnerável',
        'abuso sexual',
        'assédio sexual',
        'importunação sexual',
        'crime sexual',
        'violência sexual',
        'toque sem consentimento',
        'fui abusada',
        'fui abusado',
        'ameaça',
        'ameaçaram',
        'fui ameaçado',
        'fui ameaçada',
        'ameaça pelo whatsapp',
        'agressão',
        'agressão física',
        'fui agredido',
        'fui agredida',
        'me bateram',
        'lesão corporal',
        'homicídio',
        'tentativa de homicídio',
        'briga',
        'briga de rua',
        'roubo',
        'furto',
        'assalto',
        'fui assaltado',
        'fui assaltada',
        'me roubaram',
        'roubaram meu celular',
        'invadiram minha casa',
        'arrombamento',
        'receptação',
        'estelionato',
        'golpe',
        'caí em golpe',
        'fraude',
        'extorsão',
        'chantagem',
        'sequestro',
        'cárcere privado',
        'prisão',
        'preso',
        'foi preso',
        'prenderam',
        'flagrante',
        'prisão em flagrante',
        'audiência de custódia',
        'habeas corpus',
        'fiança',
        'tornozeleira eletrônica',
        'regime aberto',
        'regime semiaberto',
        'execução penal',
        'delegacia',
        'intimação policial',
        'depoimento na delegacia',
        'inquérito policial',
        'boletim de ocorrência',
        'b o',
        'fazer boletim',
        'trafico de drogas',
        'tráfico de drogas',
        'porte de droga',
        'porte de maconha',
        'drogas',
        'lei seca',
        'embriaguez ao volante',
        'calúnia',
        'injúria',
        'difamação',
        'falsa acusação',
        'nudes vazados',
        'vazaram nudes',
        'pornografia de vingança',
        'advogado penalista',
        'direito processual penal'
      ]::text[]
    ),
    (
      array['Direito Imobiliário']::text[],
      110,
      array[
        'advogado imobiliário',
        'direito imobiliário',
        'imóvel',
        'casa',
        'apartamento',
        'terreno',
        'lote',
        'aluguel',
        'aluguel atrasado',
        'contrato de aluguel',
        'despejo',
        'ordem de despejo',
        'ação de despejo',
        'inquilino não paga',
        'inquilino não sai',
        'proprietário',
        'locador',
        'locatário',
        'condomínio',
        'taxa de condomínio',
        'síndico',
        'locação',
        'compra de imóvel',
        'venda de imóvel',
        'escritura',
        'registro de imóvel',
        'matrícula do imóvel',
        'regularizar imóvel',
        'habite-se',
        'usucapião',
        'posse',
        'posse de terreno',
        'invasão de terreno',
        'invasão de imóvel',
        'construtora',
        'obra atrasada',
        'atraso na obra',
        'imóvel na planta',
        'distrato imobiliário',
        'financiamento imobiliário',
        'financiamento caixa',
        'corretor',
        'comissão de corretagem',
        'caução',
        'fiador',
        'vistoria',
        'infiltração',
        'vício construtivo',
        'reforma',
        'vizinho barulhento',
        'barulho de vizinho',
        'direito condominial',
        'direito locatício'
      ]::text[]
    ),
    (
      array['Direito das Sucessões']::text[],
      110,
      array[
        'advogado de inventário',
        'advogado de herança',
        'direito das sucessões',
        'direito sucessório',
        'sucessões',
        'inventário',
        'inventário extrajudicial',
        'inventário judicial',
        'abrir inventário',
        'arrolamento de bens',
        'espólio',
        'herança',
        'herdeiro',
        'herdeiros',
        'briga de herança',
        'partilha de herança',
        'dividir a herança',
        'renúncia de herança',
        'meu pai morreu',
        'minha mãe morreu',
        'meu marido morreu',
        'minha esposa morreu',
        'faleceu',
        'falecimento',
        'bens do falecido',
        'imóvel do falecido',
        'conta do falecido',
        'testamento',
        'fazer testamento',
        'deixar testamento',
        'contestar testamento',
        'deserdação',
        'sonegação de bens',
        'doação em vida',
        'planejamento sucessório',
        'holding familiar',
        'itcmd de herança',
        'usufruto',
        'meação'
      ]::text[]
    ),
    (
      array['Direito Bancário']::text[],
      110,
      array[
        'advogado bancário',
        'direito bancário',
        'contra o banco',
        'problema com banco',
        'dívida com o banco',
        'renegociar dívida',
        'empréstimo',
        'empréstimo consignado',
        'consignado indevido',
        'empréstimo que não fiz',
        'desconto no benefício',
        'desconto na aposentadoria',
        'juros abusivos',
        'ação revisional',
        'revisional de juros',
        'revisão de contrato bancário',
        'financiamento de veículo',
        'financiamento de carro',
        'busca e apreensão do carro',
        'alienação fiduciária',
        'cheque especial',
        'rotativo do cartão',
        'superendividamento',
        'tarifa bancária',
        'tarifas indevidas',
        'venda casada do banco',
        'seguro embutido no empréstimo',
        'consórcio não contemplado',
        'carta de crédito',
        'penhora na conta',
        'bloqueio judicial da conta',
        'banco negou empréstimo',
        'contrato bancário'
      ]::text[]
    ),
    (
      array['Direito Empresarial']::text[],
      105,
      array[
        'advogado empresarial',
        'direito empresarial',
        'empresa',
        'abrir empresa',
        'fechar empresa',
        'cnpj',
        'contrato social',
        'alteração contrato social',
        'alterar contrato social',
        'sócio',
        'sócios',
        'briga de sócios',
        'briga com sócio',
        'tirar sócio',
        'retirada de sócio',
        'entrada de sócio',
        'sociedade',
        'dissolução de sociedade',
        'acordo de sócios',
        'quotas',
        'ltda',
        'mei',
        'microempresa',
        'holding',
        'startup',
        'franquia',
        'contrato empresarial',
        'fornecedor',
        'cliente não pagou empresa',
        'cobrança empresarial',
        'recuperação judicial',
        'falência',
        'marca',
        'registro de marca',
        'pro labore',
        'compliance',
        'licitação',
        'contrato de prestação de serviço',
        'contrato com fornecedor',
        'contrato de parceria',
        'distribuição',
        'representação comercial',
        'direito societário',
        'direito corporativo',
        'assessoria jurídica empresarial',
        'consultoria empresarial',
        'direito das startups'
      ]::text[]
    ),
    (
      array['Direito Tributário']::text[],
      105,
      array[
        'advogado tributário',
        'direito tributário',
        'imposto',
        'impostos',
        'tributo',
        'tributos',
        'dívida ativa',
        'execução fiscal',
        'cobrança da prefeitura',
        'cobrança do estado',
        'cobrança da receita',
        'iptu',
        'ipva',
        'icms',
        'iss',
        'irpf',
        'irpj',
        'imposto de renda',
        'receita federal',
        'malha fina',
        'simples nacional',
        'mei imposto',
        'pis',
        'cofins',
        'darf',
        'parcelamento fiscal',
        'multa fiscal',
        'autuação fiscal',
        'fiscalização',
        'nota fiscal',
        'sonegação',
        'cnd',
        'certidão negativa',
        'recuperar imposto',
        'restituição',
        'taxa',
        'itcmd',
        'itbi',
        'protesto da prefeitura',
        'regularizar imposto',
        'direito fiscal'
      ]::text[]
    ),
    (
      array['Direito Médico e da Saúde']::text[],
      110,
      array[
        'advogado médico',
        'direito médico',
        'direito da saúde',
        'direito à saúde',
        'erro médico',
        'erro cirúrgico',
        'erro de diagnóstico',
        'negligência médica',
        'imperícia médica',
        'imprudência médica',
        'cirurgia deu errado',
        'sequela de cirurgia',
        'infecção hospitalar',
        'morte no hospital',
        'hospital',
        'médico',
        'crm',
        'conselho de medicina',
        'processo no crm',
        'plano de saúde negou',
        'negativa de cobertura',
        'medicamento negado',
        'remédio de alto custo',
        'sus negou',
        'fila do sus',
        'liminar para cirurgia',
        'liminar para remédio',
        'internação negada',
        'uti negada',
        'home care',
        'tratamento fora de domicílio',
        'exame negado',
        'reajuste do plano de saúde',
        'plano de saúde cancelado',
        'carência do plano',
        'prontuário médico',
        'consentimento informado',
        'erro odontológico',
        'cirurgia plástica deu errado',
        'tratamento negado pelo plano'
      ]::text[]
    ),
    (
      array['Direito Administrativo']::text[],
      105,
      array[
        'advogado administrativo',
        'direito administrativo',
        'contra a prefeitura',
        'contra o município',
        'contra o estado',
        'poder público',
        'processo administrativo',
        'servidor público',
        'servidor estadual',
        'servidor municipal',
        'concurso público',
        'eliminado do concurso',
        'reprovado no concurso',
        'nomeação em concurso',
        'posse em concurso',
        'preterido no concurso',
        'sindicância',
        'processo administrativo disciplinar',
        'demissão de servidor',
        'reajuste de servidor',
        'aposentadoria de servidor',
        'licitação',
        'pregão',
        'contrato administrativo',
        'improbidade administrativa',
        'multa administrativa',
        'desapropriação',
        'alvará',
        'licença da prefeitura',
        'fiscalização da prefeitura',
        'auto de infração',
        'interdição do estabelecimento',
        'precatório',
        'mandado de segurança'
      ]::text[]
    ),
    (
      array['Direito Securitário']::text[],
      85,
      array[
        'advogado securitário',
        'direito securitário',
        'seguradora negou',
        'seguradora não pagou',
        'seguro negado',
        'indenização do seguro',
        'sinistro',
        'negativa de sinistro',
        'seguro de vida',
        'seguro de vida negado',
        'seguro residencial',
        'seguro empresarial',
        'seguro prestamista',
        'seguro do celular',
        'apólice',
        'cláusula de exclusão',
        'prêmio do seguro',
        'susep',
        'capitalização',
        'título de capitalização',
        'dpvat',
        'perda total do carro',
        'vistoria da seguradora'
      ]::text[]
    ),
    (
      array['Direito Digital']::text[],
      115,
      array[
        'advogado digital',
        'direito digital',
        'crime virtual',
        'crime na internet',
        'internet',
        'rede social',
        'lgpd',
        'vazamento de dados',
        'dados vazados',
        'privacidade',
        'proteção de dados',
        'perfil hackeado',
        'conta hackeada',
        'instagram hackeado',
        'facebook hackeado',
        'whatsapp clonado',
        'clonaram whatsapp',
        'conta invadida',
        'golpe do pix',
        'pix',
        'pix errado',
        'fraude online',
        'golpe online',
        'loja falsa',
        'site falso',
        'cyberbullying',
        'nudes vazados',
        'vazaram nudes',
        'fotos vazadas',
        'vídeo vazado',
        'pornografia de vingança',
        'difamação na internet',
        'post ofensivo',
        'comentário ofensivo',
        'fake news',
        'deepfake',
        'remover conteúdo',
        'tirar conteúdo do ar',
        'remover foto',
        'remover vídeo',
        'uso indevido de imagem',
        'direito autoral',
        'plágio',
        'software',
        'contrato de software',
        'aplicativo',
        'termos de uso',
        'e-commerce',
        'direito da tecnologia'
      ]::text[]
    ),
    (
      array['Direito da Criança e do Adolescente']::text[],
      100,
      array[
        'advogado da criança',
        'direito da criança e do adolescente',
        'direito da infância e juventude',
        'eca',
        'estatuto da criança',
        'conselho tutelar',
        'ato infracional',
        'menor infrator',
        'medida socioeducativa',
        'internação de menor',
        'apreensão de adolescente',
        'acolhimento institucional',
        'abrigo',
        'destituição do poder familiar',
        'perda do poder familiar',
        'adoção de criança',
        'trabalho infantil',
        'abuso infantil',
        'maus tratos a criança',
        'negligência com criança',
        'vaga em creche',
        'criança sem escola',
        'matrícula negada a criança'
      ]::text[]
    ),
    (
      array['Direito do Idoso']::text[],
      90,
      array[
        'advogado do idoso',
        'direito do idoso',
        'estatuto do idoso',
        'idoso',
        'pessoa idosa',
        'maus tratos ao idoso',
        'violência contra idoso',
        'abandono de idoso',
        'abuso financeiro do idoso',
        'golpe contra idoso',
        'casa de repouso',
        'asilo de idosos',
        'curatela de idoso',
        'interdição de idoso',
        'prioridade para idoso',
        'gratuidade no transporte para idoso',
        'reajuste de plano por idade',
        'consignado de idoso'
      ]::text[]
    ),
    (
      array['Direito Ambiental']::text[],
      100,
      array[
        'advogado ambiental',
        'direito ambiental',
        'meio ambiente',
        'multa ambiental',
        'ibama',
        'multa do ibama',
        'licenciamento ambiental',
        'licença ambiental',
        'crime ambiental',
        'desmatamento',
        'área de preservação permanente',
        'reserva legal',
        'cadastro ambiental rural',
        'embargo ambiental',
        'auto de infração ambiental',
        'poluição',
        'poluição sonora',
        'descarte irregular',
        'contaminação do solo',
        'corte de árvore',
        'cortaram uma árvore',
        'queimada',
        'esgoto irregular',
        'agrotóxico',
        'mineração',
        'área degradada',
        'termo de ajustamento de conduta'
      ]::text[]
    ),
    (
      array['Direito Agrário']::text[],
      100,
      array[
        'advogado agrário',
        'direito agrário',
        'direito rural',
        'agronegócio',
        'fazenda',
        'sítio',
        'chácara',
        'propriedade rural',
        'posse de terra',
        'grilagem',
        'usucapião rural',
        'incra',
        'georreferenciamento',
        'itr',
        'reforma agrária',
        'assentamento',
        'invasão de fazenda',
        'arrendamento rural',
        'parceria rural',
        'contrato de arrendamento',
        'crédito rural',
        'financiamento agrícola',
        'cédula de produto rural',
        'venda de safra',
        'safra',
        'gado',
        'dívida rural',
        'seguro agrícola',
        'demarcação de terras'
      ]::text[]
    ),
    (
      array['Direito Urbanístico']::text[],
      95,
      array[
        'advogado urbanístico',
        'direito urbanístico',
        'plano diretor',
        'zoneamento',
        'uso do solo',
        'loteamento',
        'loteamento irregular',
        'regularização fundiária',
        'reurb',
        'construção irregular',
        'obra embargada',
        'embargo de obra',
        'prefeitura embargou a obra',
        'alvará de construção',
        'habite-se',
        'recuo da construção',
        'parcelamento do solo',
        'condomínio de lotes',
        'desapropriação urbana'
      ]::text[]
    ),
    (
      array['Direito Sindical']::text[],
      85,
      array[
        'advogado sindical',
        'direito sindical',
        'sindicato',
        'contribuição sindical',
        'convenção coletiva',
        'acordo coletivo',
        'dissídio',
        'dissídio coletivo',
        'greve',
        'direito de greve',
        'negociação coletiva',
        'representação sindical',
        'eleição sindical',
        'estabilidade de dirigente sindical',
        'homologação no sindicato',
        'enquadramento sindical',
        'categoria profissional',
        'ação coletiva trabalhista'
      ]::text[]
    ),
    (
      array['Direito Eleitoral']::text[],
      95,
      array[
        'advogado eleitoral',
        'direito eleitoral',
        'eleição',
        'eleições',
        'candidato',
        'candidatura',
        'registro de candidatura',
        'ficha limpa',
        'inelegibilidade',
        'inelegível',
        'prestação de contas eleitoral',
        'contas rejeitadas',
        'propaganda eleitoral',
        'propaganda irregular',
        'boca de urna',
        'compra de votos',
        'partido político',
        'filiação partidária',
        'convenção partidária',
        'cassação de mandato',
        'diploma cassado',
        'justiça eleitoral',
        'multa eleitoral',
        'título de eleitor',
        'impugnação de candidatura',
        'tse',
        'tre'
      ]::text[]
    ),
    (
      array['Direito Militar']::text[],
      95,
      array[
        'advogado militar',
        'direito militar',
        'militar',
        'exército',
        'marinha',
        'polícia militar',
        'bombeiro militar',
        'conselho de disciplina',
        'conselho de justificação',
        'transgressão disciplinar',
        'punição disciplinar',
        'prisão disciplinar',
        'justiça militar',
        'crime militar',
        'deserção',
        'licenciamento do militar',
        'exclusão a bem da disciplina',
        'reforma militar',
        'pensão militar',
        'incapacidade do militar',
        'concurso militar',
        'reintegração de militar',
        'promoção de militar',
        'inquérito policial militar',
        'quartel'
      ]::text[]
    ),
    (
      array['Direito Educacional']::text[],
      85,
      array[
        'advogado educacional',
        'direito educacional',
        'direito da educação',
        'mensalidade escolar',
        'reajuste de mensalidade',
        'jubilamento',
        'reprovação',
        'transferência de curso',
        'diploma não sai',
        'diploma negado',
        'reconhecimento de curso',
        'mec',
        'fies',
        'prouni',
        'bolsa de estudos',
        'cancelamento de bolsa',
        'matrícula negada',
        'recusa de matrícula',
        'bullying na escola',
        'expulsão da escola',
        'aluno com deficiência na escola',
        'educação inclusiva',
        'colação de grau',
        'estágio obrigatório'
      ]::text[]
    ),
    (
      array['Direito da Propriedade Intelectual']::text[],
      95,
      array[
        'advogado de propriedade intelectual',
        'direito da propriedade intelectual',
        'propriedade intelectual',
        'propriedade industrial',
        'registro de marca',
        'marca registrada',
        'minha marca',
        'copiaram minha marca',
        'uso indevido de marca',
        'inpi',
        'patente',
        'registrar patente',
        'invenção',
        'desenho industrial',
        'direito autoral',
        'direitos autorais',
        'plágio',
        'copiaram meu texto',
        'copiaram minha foto',
        'copiaram meu produto',
        'música sem autorização',
        'ecad',
        'registro de software',
        'nome empresarial',
        'concorrência desleal',
        'pirataria',
        'contrafação',
        'licenciamento de marca'
      ]::text[]
    ),
    (
      array['Direito Notarial e Registral']::text[],
      85,
      array[
        'advogado notarial',
        'direito notarial',
        'direito registral',
        'cartório',
        'problema no cartório',
        'escritura pública',
        'lavrar escritura',
        'procuração pública',
        'reconhecimento de firma',
        'registro de imóveis',
        'averbação',
        'retificação de área',
        'retificação de matrícula',
        'dúvida registral',
        'certidão de nascimento',
        'certidão de casamento',
        'certidão de óbito',
        'registro tardio de nascimento',
        'protesto de título',
        'cancelar protesto',
        'tabelionato',
        'usucapião extrajudicial',
        'inventário em cartório',
        'divórcio em cartório'
      ]::text[]
    ),
    (
      array['Direito Imigratório']::text[],
      90,
      array[
        'advogado de imigração',
        'direito imigratório',
        'direito migratório',
        'imigração',
        'imigrar',
        'visto de trabalho',
        'visto de estudante',
        'visto negado',
        'tirar visto',
        'residência permanente',
        'autorização de residência',
        'registro de estrangeiro',
        'carteira de estrangeiro',
        'naturalização',
        'naturalizar',
        'estrangeiro no brasil',
        'refúgio',
        'refugiado',
        'asilo político',
        'deportação',
        'expulsão de estrangeiro',
        'reunião familiar',
        'polícia federal imigração'
      ]::text[]
    ),
    (
      array['Direito Internacional']::text[],
      90,
      array[
        'advogado internacional',
        'direito internacional',
        'no exterior',
        'fora do país',
        'divórcio no exterior',
        'casamento no exterior',
        'documento estrangeiro',
        'apostilamento',
        'apostila de haia',
        'tradução juramentada',
        'homologação de sentença estrangeira',
        'sentença estrangeira',
        'herança no exterior',
        'bens no exterior',
        'contrato internacional',
        'arbitragem internacional',
        'cidadania italiana',
        'cidadania portuguesa',
        'cidadania espanhola',
        'dupla cidadania',
        'subtração internacional de menor',
        'pensão do exterior'
      ]::text[]
    ),
    (
      array['Direito Constitucional']::text[],
      90,
      array[
        'advogado constitucional',
        'direito constitucional',
        'constituição',
        'direito fundamental',
        'direitos fundamentais',
        'habeas data',
        'ação popular',
        'inconstitucional',
        'liberdade de expressão',
        'recurso extraordinário',
        'supremo tribunal federal',
        'repercussão geral',
        'direito de manifestação'
      ]::text[]
    ),
    (
      array['Direito Penal Empresarial']::text[],
      85,
      array[
        'advogado penal empresarial',
        'direito penal empresarial',
        'direito penal econômico',
        'crime empresarial',
        'crime tributário',
        'sonegação fiscal',
        'crime contra a ordem econômica',
        'crime falimentar',
        'lavagem de dinheiro',
        'corrupção',
        'peculato',
        'fraude em licitação',
        'apropriação indébita previdenciária',
        'responsabilidade penal do sócio',
        'busca e apreensão na empresa',
        'operação da polícia federal',
        'acordo de leniência',
        'colaboração premiada',
        'compliance criminal'
      ]::text[]
    ),
    (
      array['Direito Concorrencial']::text[],
      75,
      array[
        'advogado concorrencial',
        'direito concorrencial',
        'direito da concorrência',
        'antitruste',
        'cartel',
        'abuso de poder econômico',
        'ato de concentração',
        'concorrência desleal',
        'preço predatório',
        'exclusividade abusiva',
        'denúncia ao cade',
        'conselho administrativo de defesa econômica'
      ]::text[]
    ),
    (
      array['Direito Aduaneiro']::text[],
      80,
      array[
        'advogado aduaneiro',
        'direito aduaneiro',
        'aduana',
        'alfândega',
        'importação',
        'exportação',
        'comércio exterior',
        'mercadoria retida',
        'retenção de mercadoria',
        'produto retido na alfândega',
        'encomenda taxada',
        'pena de perdimento',
        'imposto de importação',
        'despachante aduaneiro',
        'drawback',
        'classificação fiscal',
        'multa aduaneira',
        'siscomex'
      ]::text[]
    ),
    (
      array['Direito Regulatório']::text[],
      80,
      array[
        'advogado regulatório',
        'direito regulatório',
        'agência reguladora',
        'anatel',
        'aneel',
        'anvisa',
        'antt',
        'agência nacional de saúde',
        'concessão pública',
        'permissão pública',
        'setor elétrico',
        'telecomunicações',
        'saneamento',
        'transporte regulado',
        'registro na anvisa',
        'multa de agência reguladora',
        'tarifa regulada'
      ]::text[]
    ),
    (
      array['Direito do Terceiro Setor']::text[],
      75,
      array[
        'advogado do terceiro setor',
        'direito do terceiro setor',
        'terceiro setor',
        'ong',
        'organização não governamental',
        'associação sem fins lucrativos',
        'fundação privada',
        'oscip',
        'utilidade pública',
        'cebas',
        'imunidade tributária de entidade',
        'estatuto de associação',
        'assembleia de associação',
        'prestação de contas de ong',
        'termo de fomento',
        'termo de colaboração',
        'captação de recursos',
        'entidade religiosa'
      ]::text[]
    ),
    (
      array['Direito Cooperativo']::text[],
      75,
      array[
        'advogado cooperativo',
        'direito cooperativo',
        'cooperativa',
        'cooperativismo',
        'cooperado',
        'assembleia de cooperativa',
        'estatuto de cooperativa',
        'cooperativa de crédito',
        'cooperativa agrícola',
        'cooperativa de trabalho',
        'exclusão de cooperado',
        'sobras da cooperativa',
        'ato cooperativo',
        'liquidação de cooperativa'
      ]::text[]
    ),
    (
      array['Direito Desportivo']::text[],
      85,
      array[
        'advogado desportivo',
        'direito desportivo',
        'esporte',
        'futebol',
        'atleta',
        'jogador',
        'contrato de atleta',
        'passe do jogador',
        'transferência de jogador',
        'clube',
        'federação esportiva',
        'confederação',
        'tribunal desportivo',
        'doping',
        'punição no esporte',
        'lei pelé',
        'salário de atleta',
        'empresário de jogador',
        'direito de imagem do atleta',
        'formação de atleta'
      ]::text[]
    ),
    (
      array['Direito Animal']::text[],
      80,
      array[
        'advogado de animais',
        'direito animal',
        'direito dos animais',
        'maus tratos a animais',
        'crueldade contra animal',
        'envenenaram meu cachorro',
        'mataram meu pet',
        'erro veterinário',
        'clínica veterinária',
        'morte do pet',
        'guarda do pet',
        'guarda do animal no divórcio',
        'condomínio proibiu animal',
        'aluguel com pet',
        'ataque de cachorro',
        'cachorro mordeu',
        'abandono de animal',
        'resgate de animais'
      ]::text[]
    ),
    (
      array['Direito Marítimo']::text[],
      80,
      array[
        'advogado marítimo',
        'direito marítimo',
        'direito portuário',
        'navio',
        'embarcação',
        'carga marítima',
        'avaria de carga',
        'afretamento',
        'armador',
        'tripulante de navio',
        'marítimo embarcado',
        'acidente com embarcação',
        'naufrágio',
        'seguro marítimo',
        'sobreestadia',
        'capitania dos portos',
        'registro de embarcação',
        'terminal portuário'
      ]::text[]
    ),
    (
      array['Direito Aeronáutico']::text[],
      80,
      array[
        'advogado aeronáutico',
        'direito aeronáutico',
        'aviação',
        'aeronave',
        'piloto de avião',
        'tripulante de voo',
        'comissário de bordo',
        'anac',
        'acidente aéreo',
        'queda de avião',
        'compra de aeronave',
        'registro de aeronave',
        'táxi aéreo',
        'drone',
        'hangar'
      ]::text[]
    )
),
expanded_terms as (
  select
    areas.practice_area,
    terms.phrase,
    public.normalize_practice_area_search(terms.phrase) as normalized_phrase,
    seed.weight
  from seed
  cross join unnest(seed.practice_areas) as areas(practice_area)
  cross join unnest(seed.terms) as terms(phrase)
  where nullif(trim(terms.phrase), '') is not null
),
deduplicated_terms as (
  select
    expanded_terms.practice_area,
    expanded_terms.normalized_phrase,
    min(expanded_terms.phrase) as phrase,
    max(expanded_terms.weight) as weight
  from expanded_terms
  where expanded_terms.normalized_phrase <> ''
  group by
    expanded_terms.practice_area,
    expanded_terms.normalized_phrase
)
insert into public.legal_search_intents (
  phrase,
  normalized_phrase,
  practice_area,
  related_tags,
  weight
)
select
  deduplicated_terms.phrase,
  deduplicated_terms.normalized_phrase,
  deduplicated_terms.practice_area,
  '{}'::text[],
  deduplicated_terms.weight
from deduplicated_terms
on conflict (normalized_phrase, practice_area) do update
set
  phrase = excluded.phrase,
  weight = excluded.weight,
  is_active = true;

-- Termo apontando para area que nao existe mais nao pode continuar
-- ranqueando: traduz o que der, desliga o resto.
update public.legal_search_intents
set practice_area =
  (public.canonical_practice_areas(array[practice_area]))[1]
where not exists (
  select 1 from public.legal_practice_areas lpa
  where lpa.name = public.legal_search_intents.practice_area
);

update public.legal_search_intents
set is_active = false
where is_active
  and not exists (
    select 1 from public.legal_practice_areas lpa
    where lpa.name = public.legal_search_intents.practice_area
  );

-- ---------------------------------------------------------------------------
-- 7. Categorias populares: porta de entrada para quem NAVEGA em vez de digitar.
--
-- A grade da home e de 3 colunas e tinha 6 categorias. Sem categoria, a area
-- nova so aparece para quem digita — e uma boa parte dos clientes nao digita,
-- toca. As tres escolhidas sao as areas novas de maior demanda no cadastro
-- real: Sucessoes (12 usos), Bancario (12) e Medico/Saude (4).
--
-- Espelhado em lib/data/mock/mock_categories.dart, que e o placeholder
-- instantaneo enquanto o fetch nao chega.
-- ---------------------------------------------------------------------------
insert into public.legal_categories
  (id, title, icon_name, practice_area, is_highlighted, sort_order)
values
  ('inventario-heranca', 'Inventário e Herança', 'balance_outlined',
   'Direito das Sucessões', false, 70),
  ('plano-de-saude', 'Plano de Saúde', 'medical_services_outlined',
   'Direito Médico e da Saúde', false, 80),
  ('dividas-e-banco', 'Dívidas e Banco', 'account_balance_outlined',
   'Direito Bancário', false, 90)
on conflict (id) do update set
  title = excluded.title,
  icon_name = excluded.icon_name,
  practice_area = excluded.practice_area,
  sort_order = excluded.sort_order;

notify pgrst, 'reload schema';
