-- Vínculos múltiplos: uma pessoa, vários escritórios, um cargo por vínculo.
--
-- O QUE JÁ ERA VERDADE, e por isso esta migration é menor do que parece:
-- law_firm_members já é a tabela de vínculo, com único por par
-- (law_firm_id, profile_id) e nunca por pessoa; o cargo já mora na linha, em
-- `roles`; e toda a autorização já recebe law_firm_id e confere o vínculo de
-- auth.uid(). O banco nunca impediu N vínculos. Quem estreitava eram os dois
-- clientes, cada um com um `order by joined_at limit 1` e o mesmo comentário:
-- "até existir um seletor de escritório".
--
-- O QUE FALTAVA no banco é o que está aqui: um jeito de PERGUNTAR os vínculos,
-- a Seccional do escritório (que não existia em coluna nenhuma), a regra do
-- sócio, e duas correções de escopo que só doem quando alguém tem dois
-- escritórios.
--
-- NÃO existe "escritório ativo" aqui, de propósito. Escolha de contexto é do
-- cliente; o banco continua exigindo o id em cada chamada e conferindo o
-- vínculo. Guardar o ativo no servidor criaria um estado global que duas abas
-- abertas quebram, e pior, tentaria dizer autoridade a partir de preferência.

-- ---------------------------------------------------------------------------
-- 1. A Seccional da OAB do escritório
-- ---------------------------------------------------------------------------
--
-- Não existia em nenhuma coluna dos dois repositórios. O que existe é o CEP, e
-- a UF dele já era lida a cada consulta de endereço e descartada (cep.ts e
-- cep_service.dart leem `state`/`uf` da BrasilAPI).
--
-- A coluna guarda o que a pessoa DECLARA, não o que o CEP sugere: a sede pode
-- ficar numa UF e a sociedade estar registrada em outra, e é o registro que a
-- regra do sócio persegue. O CEP entra como valor inicial do campo, e a equipe
-- confirma na revisão.
alter table public.law_firms
  add column if not exists oab_state char(2);

alter table public.law_firm_verifications
  add column if not exists oab_state char(2);

alter table public.law_firms
  drop constraint if exists law_firms_oab_state_check;
alter table public.law_firms
  add constraint law_firms_oab_state_check
  check (oab_state is null or oab_state ~ '^[A-Z]{2}$');

alter table public.law_firm_verifications
  drop constraint if exists law_firm_verifications_oab_state_check;
alter table public.law_firm_verifications
  add constraint law_firm_verifications_oab_state_check
  check (oab_state is null or oab_state ~ '^[A-Z]{2}$');

/**
 * A UF de um CEP, pelas faixas dos Correios.
 *
 * Serve para PREENCHER o campo, não para decidir a regra: o valor que vale é o
 * declarado em oab_state. IMMUTABLE porque só depende do argumento, o que
 * permite usá-la em backfill e em default de formulário sem custo.
 *
 * CEP fora de faixa ou malformado devolve null, e null nunca é chute.
 */
create or replace function public.uf_do_cep(cep_value text)
returns char(2)
language sql
immutable
set search_path = public
as $$
  with digitos as (
    select nullif(regexp_replace(coalesce(cep_value, ''), '\D', '', 'g'), '') as cep
  ),
  prefixo as (
    select case when length(cep) = 8 then left(cep, 5)::int end as faixa from digitos
  )
  select case
    when faixa is null then null
    when faixa between  1000 and 19999 then 'SP'
    when faixa between 20000 and 28999 then 'RJ'
    when faixa between 29000 and 29999 then 'ES'
    when faixa between 30000 and 39999 then 'MG'
    when faixa between 40000 and 48999 then 'BA'
    when faixa between 49000 and 49999 then 'SE'
    when faixa between 50000 and 56999 then 'PE'
    when faixa between 57000 and 57999 then 'AL'
    when faixa between 58000 and 58999 then 'PB'
    when faixa between 59000 and 59999 then 'RN'
    when faixa between 60000 and 63999 then 'CE'
    when faixa between 64000 and 64999 then 'PI'
    when faixa between 65000 and 65999 then 'MA'
    when faixa between 66000 and 68899 then 'PA'
    when faixa between 68900 and 68999 then 'AP'
    when faixa between 69000 and 69299 then 'AM'
    when faixa between 69300 and 69399 then 'RR'
    when faixa between 69400 and 69899 then 'AM'
    when faixa between 69900 and 69999 then 'AC'
    when faixa between 70000 and 72799 then 'DF'
    when faixa between 72800 and 72999 then 'GO'
    when faixa between 73000 and 73699 then 'DF'
    when faixa between 73700 and 76799 then 'GO'
    when faixa between 76800 and 76999 then 'RO'
    when faixa between 77000 and 77999 then 'TO'
    when faixa between 78000 and 78899 then 'MT'
    when faixa between 78900 and 78999 then 'RO'
    when faixa between 79000 and 79999 then 'MS'
    when faixa between 80000 and 87999 then 'PR'
    when faixa between 88000 and 89999 then 'SC'
    when faixa between 90000 and 99999 then 'RS'
  end::char(2)
  from prefixo;
$$;

revoke all on function public.uf_do_cep(text) from public;
grant execute on function public.uf_do_cep(text) to authenticated;

-- Backfill: quem já tem CEP ganha a Seccional sugerida por ele. Quem não tem
-- fica nulo, e a regra do sócio simplesmente não se aplica a esse escritório
-- até alguém declarar. Nulo aqui é "não sei", não é "pode tudo" por descuido:
-- a consequência está escrita na função da regra, mais abaixo.
update public.law_firms
set oab_state = public.uf_do_cep(cep)
where oab_state is null and public.uf_do_cep(cep) is not null;

update public.law_firm_verifications
set oab_state = public.uf_do_cep(cep)
where oab_state is null and public.uf_do_cep(cep) is not null;

-- ---------------------------------------------------------------------------
-- 2. Perguntar os vínculos de quem está logado
-- ---------------------------------------------------------------------------
--
-- Não existia caminho para isso, e o select direto NÃO serve: a policy
-- law_firm_members_read_related entrega também as linhas dos COLEGAS (ela
-- existe para montar a lista da equipe). Foi exatamente esse detalhe que criou
-- um defeito vivo no webapp, onde `order by joined_at limit 1` sem filtro de
-- profile_id devolvia a linha do sócio para a secretária.
--
-- A RPC responde só sobre quem chama, e devolve o cargo junto do escritório
-- porque quem monta um seletor precisa dos dois na mesma consulta.
create or replace function public.fetch_law_firm_memberships()
returns table (
  law_firm_id uuid,
  law_firm_name text,
  law_firm_initials text,
  avatar_url text,
  oab_state char(2),
  roles text[],
  primary_role text,
  status text,
  joined_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    firm.id,
    firm.name,
    firm.initials,
    firm.avatar_url,
    firm.oab_state,
    public.normalize_law_firm_member_roles(member.roles),
    public.primary_law_firm_member_role(
      public.normalize_law_firm_member_roles(member.roles)
    )::text,
    member.status::text,
    member.joined_at
  from public.law_firm_members member
  join public.law_firms firm on firm.id = member.law_firm_id
  where member.profile_id = (select auth.uid())
    and member.status = 'active'
  -- Ordem estável e legível: o mais antigo primeiro, com o id de desempate.
  -- Sem o desempate, dois vínculos criados na mesma transação (joined_at é
  -- `default now()`) trocavam de lugar entre requisições, e o escritório que
  -- a pessoa via mudava sozinho.
  order by member.joined_at asc, member.law_firm_id asc;
$$;

revoke all on function public.fetch_law_firm_memberships() from public;
grant execute on function public.fetch_law_firm_memberships() to authenticated;

-- ---------------------------------------------------------------------------
-- 3. A regra do sócio: um por Seccional
-- ---------------------------------------------------------------------------
--
-- Três portas independentes criam ou promovem sócio, e nenhuma consultava os
-- outros escritórios da pessoa: approve_law_firm_verification (abertura),
-- update_law_firm_member_roles (promoção) e
-- transfer_owned_law_firms_for_deleted_profile (herança por conta apagada).
-- Trancar uma delas seria teatro, porque as outras duas continuam abertas.
--
-- Por isso a regra é um TRIGGER na tabela: não há caminho que não passe por
-- ela, nem RPC nova amanhã, nem SQL do dashboard.
create or replace function public.checa_socio_unico_por_seccional()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  seccional char(2);
  conflito text;
begin
  -- Só interessa quem VAI ficar sócio e ativo. Sair de sócio, mudar de
  -- secretária para advogado, desativar: nada disso é assunto desta regra.
  if not ('owner' = any(coalesce(new.roles, '{}'::text[]))) then
    return new;
  end if;
  if new.status <> 'active' then
    return new;
  end if;
  if new.profile_id is null then
    return new;
  end if;

  select firm.oab_state into seccional
  from public.law_firms firm
  where firm.id = new.law_firm_id;

  -- Escritório sem Seccional declarada não entra na regra. A alternativa
  -- seria bloquear por precaução, e isso travaria a operação de quem já
  -- existe (os cadastros antigos não tinham o campo) por causa de um dado
  -- que ninguém pediu na época.
  if seccional is null then
    return new;
  end if;

  select outro_firm.name into conflito
  from public.law_firm_members outro
  join public.law_firms outro_firm on outro_firm.id = outro.law_firm_id
  where outro.profile_id = new.profile_id
    and outro.law_firm_id <> new.law_firm_id
    and outro.status = 'active'
    and 'owner' = any(coalesce(outro.roles, '{}'::text[]))
    and outro_firm.oab_state = seccional
  limit 1;

  if conflito is not null then
    -- A mensagem nomeia o escritório em conflito: sem isso, quem recebe o
    -- erro não tem como saber de qual dos vínculos se trata.
    raise exception 'Already an owner in the % section (%)', seccional, conflito
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

drop trigger if exists law_firm_members_socio_unico on public.law_firm_members;
create trigger law_firm_members_socio_unico
  before insert or update on public.law_firm_members
  for each row
  execute function public.checa_socio_unico_por_seccional();

-- ---------------------------------------------------------------------------
-- 4. A abertura de escritório carrega a Seccional declarada
-- ---------------------------------------------------------------------------
--
-- `create or replace` preserva assinatura e grants. A única mudança é copiar
-- oab_state da verificação para o escritório, para que o trigger acima tenha
-- o que ler no exato momento em que o vínculo de sócio nasce.
CREATE OR REPLACE FUNCTION public.approve_law_firm_verification(verification_id_value uuid, reviewer_id_value uuid DEFAULT NULL::uuid)
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
      oab_state,
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
      -- A Seccional DECLARADA no pedido; sem declaracao, a que o CEP sugere.
      -- Nulo continua possivel, e o trigger do socio trata (nao aplica a regra).
      coalesce(verification_row.oab_state, public.uf_do_cep(verification_row.cep)),
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
      oab_state = coalesce(
        verification_row.oab_state,
        firm.oab_state,
        public.uf_do_cep(verification_row.cep)
      ),
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

  -- Vincula a assinatura de quem contratou ao escritorio que nasceu (ou ja
  -- existia). Sem isto o teto de advogados nao teria a que se ancorar, e o
  -- plano nao apareceria no perfil do escritorio.
  update public.law_firm_license_subscriptions sub
  set law_firm_id = firm_id_value, updated_at = now()
  where sub.owner_profile_id = verification_row.owner_profile_id
    and sub.law_firm_id is null
    and sub.status <> 'canceled';

  return firm_id_value;
end;
$function$;

revoke all on function public.approve_law_firm_verification(uuid, uuid) from public;
grant execute on function public.approve_law_firm_verification(uuid, uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 5. As métricas do painel paravam de ser deste escritório
-- ---------------------------------------------------------------------------
--
-- O CTE contava qualquer caso cujo advogado responsável fosse membro DESTE
-- escritório, sem exigir que o CASO fosse deste escritório. Advogado em duas
-- bancas fazia os casos de uma contarem no painel da outra: número de outro
-- lugar, dentro da tela que diz "a operação do escritório num olhar".
--
-- Agora todo ramo exige lc.law_firm_id = law_firm_id_value. O caso continua
-- alcançável por responsável e por participante, mas dentro da própria casa.
create or replace function public.fetch_law_firm_operation_metrics(
  law_firm_id_value uuid
)
returns table (
  client_messages integer,
  team_messages integer,
  active_cases integer,
  team_members integer
)
language sql
stable
security definer
set search_path = public
as $$
  with active_members as (
    select lfm.profile_id
    from public.law_firm_members lfm
    where lfm.law_firm_id = law_firm_id_value
      and lfm.profile_id is not null
      and lfm.status = 'active'
  ),
  scoped_cases as (
    select distinct lc.id
    from public.legal_cases lc
    where lc.status <> 'closed'
      and lc.law_firm_id = law_firm_id_value
  )
  select
    (
      select count(distinct c.id)::int
      from public.conversations c
      where c.law_firm_id = law_firm_id_value
        and c.type <> 'firm_internal'
    ),
    (
      select count(distinct c.id)::int
      from public.conversations c
      where c.law_firm_id = law_firm_id_value
        and c.type = 'firm_internal'
    ),
    (select count(*)::int from scoped_cases),
    (select count(*)::int from active_members);
$$;

revoke all on function public.fetch_law_firm_operation_metrics(uuid) from public;
grant execute on function public.fetch_law_firm_operation_metrics(uuid) to authenticated;
