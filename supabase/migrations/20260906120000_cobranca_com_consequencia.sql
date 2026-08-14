-- Cobranca com consequencia.
--
-- A cobranca ja sabia CRIAR assinatura (20260821120000), separar licenca de
-- banca (20260904120000) e receber o dinheiro (20260905120000). O que faltava
-- era a outra metade: o que acontece com quem NAO paga. Sem ela o produto
-- tinha status de assinatura sem que status de assinatura significasse nada.
--
-- Tres furos, e todos davam no mesmo lugar:
--
--   1. 'trialing' nunca vencia. O teste de 30 dias tinha data de fim e nada
--      no banco olhava para ela. Trinta dias eram para sempre.
--
--   2. Sem assinatura viva, o teto de advogados sumia. A consulta do teto
--      filtrava por status; quando nao achava linha, `plan_max` ficava null e
--      a trava inteira era pulada. Cancelar a assinatura, deixar o teste
--      vencer ou estornar a cobranca nao fechava a porta: ABRIA. Cancelamento
--      era o upgrade mais barato do produto.
--
--   3. Uma licenca abria N escritorios. O portao e conferido quando a pessoa
--      PEDE a abertura; com uma licenca so dava para pedir duas bancas, e a
--      segunda aprovacao amarrava zero linhas em silencio. A banca nascia sem
--      assinatura, o que pelo furo 2 significava equipe ilimitada de graca.
--
-- E, de quebra, a troca de plano: um UPDATE no nosso banco que nao fala com o
-- provedor. Ela e simetrica, e o lado que assusta nao e o que parece: subir
-- de plano da 25 advogados pelo preco de 3, mas DESCER continua cobrando
-- R$ 699 de quem pediu para pagar R$ 149.
--
-- A CONSEQUENCIA ESCOLHIDA e congelar o crescimento, nao sequestrar processo.
-- Quem esta sem assinatura viva nao convida mais ninguem, e a equipe que ja
-- existe continua trabalhando normalmente. Escritorio de advocacia guarda
-- prazo e documento de cliente que nao tem nada a ver com a nossa fatura, e
-- tranca-los seria cobrar do cliente do nosso cliente.
--
-- E teste vencido tem a MESMA consequencia que inadimplencia de quem paga:
-- sao a mesma coisa vista de dois lados, e dar tratamento diferente seria
-- premiar quem nunca comecou a pagar.

-- ---------------------------------------------------------------------------
-- 1. A assinatura esta viva?
-- ---------------------------------------------------------------------------
--
-- O vencimento do teste e DERIVADO, e nao agendado. Nao existe processo que
-- passe de madrugada mudando linha de 'trialing' para 'past_due', entao a
-- pergunta e respondida na hora em que alguem pergunta. Assim nao ha janela
-- entre o teste vencer e alguem notar, e o banco continua a unica fonte da
-- verdade sem depender de um agendador estar de pe.
--
-- `past_due` NAO esta vivo de proposito. Era isso que faltava para o furo 1:
-- se inadimplencia ainda desse teto cheio, derivar o vencimento do teste nao
-- mudaria nada, porque o teste vencido viraria past_due e seguiria valendo.
create or replace function public.assinatura_esta_viva(
  status_value text,
  trial_ends_at_value timestamptz
)
returns boolean
language sql
stable
set search_path = public
as $$
  select status_value = 'active'
      or (
        status_value = 'trialing'
        -- Teste sem data de fim seria teste eterno. Nao deveria existir (a
        -- coluna e preenchida na criacao), e se existir vale como vencido:
        -- entre errar para o lado de cobrar e errar para o lado de liberar
        -- para sempre, este e o lado seguro.
        and trial_ends_at_value is not null
        and trial_ends_at_value > now()
      );
$$;

comment on function public.assinatura_esta_viva(text, timestamptz) is
  'Assinatura viva: ativa, ou em teste que ainda nao venceu. past_due e canceled nao estao vivas.';

-- ---------------------------------------------------------------------------
-- 2. O teto de advogados de um escritorio
-- ---------------------------------------------------------------------------
--
-- Tres respostas, e a do meio e a que nao existia:
--
--   null  sem teto. Ou a banca nunca teve licenca (as aprovadas antes do
--         licenciamento, que seguem sem trava retroativa), ou o plano dela e
--         negociado e nao tem teto mesmo.
--   0     teve licenca e nao tem mais: teste vencido, inadimplencia ou
--         cancelamento. NAO convida mais ninguem.
--   N     o teto do plano contratado.
--
-- A diferenca entre null e 0 e a correcao inteira. Antes as duas caiam no
-- mesmo balde, e "nao tem assinatura" era lido como "nao tem limite".
create or replace function public.teto_de_advogados(law_firm_id_value uuid)
returns int
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  sub public.law_firm_license_subscriptions%rowtype;
  plan_max int;
begin
  -- law_firm_license_one_per_firm garante no maximo UMA nao cancelada por
  -- banca, entao a ordenacao so desempata entre canceladas: preferimos a viva
  -- e, na falta dela, a cancelada mais recente (que ainda prova que um dia
  -- houve licenca aqui).
  select * into sub
  from public.law_firm_license_subscriptions s
  where s.law_firm_id = law_firm_id_value
  order by (s.status <> 'canceled') desc, s.created_at desc
  limit 1;

  if not found then
    return null;
  end if;

  if not public.assinatura_esta_viva(sub.status, sub.trial_ends_at) then
    return 0;
  end if;

  select p.max_lawyers into plan_max
  from public.law_firm_license_plans p
  where p.code = sub.plan_code;

  return plan_max;
end;
$$;

revoke all on function public.teto_de_advogados(uuid)
  from public, anon, authenticated;

comment on function public.teto_de_advogados(uuid) is
  'Teto de advogados da banca: null sem teto, 0 sem assinatura viva, N do plano.';

-- ---------------------------------------------------------------------------
-- 3. Convidar advogado passa a olhar o teto de verdade
-- ---------------------------------------------------------------------------
--
-- Corpo verbatim da 20260821120000, com UMA mudanca: de onde vem `plan_max`.

CREATE OR REPLACE FUNCTION public.invite_verified_lawyer_to_law_firm(law_firm_id_value uuid, oab_state_value text, oab_number_value text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  latest_verification public.lawyer_verifications%rowtype;
  existing_member public.law_firm_members%rowtype;
  firm_name_value text;
  normalized_oab_state text;
  normalized_oab_number text;
  membership_id_value uuid;
  target_profile_id uuid;
  existing_is_manager boolean;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  if not public.is_active_law_firm_manager(law_firm_id_value) then
    raise exception 'Only active office owners and admins can invite lawyers';
  end if;

  -- Teto do plano: o preco acompanha o tamanho da equipe, entao o tamanho da
  -- equipe respeita o plano. A troca de plano (upgrade) libera na hora.
  --
  -- QUEM RESPONDE O TETO agora e teto_de_advogados, e a diferenca esta em
  -- quem NAO tem assinatura viva. A consulta antiga filtrava por status e,
  -- quando nao achava linha, plan_max ficava null e o `if` inteiro era
  -- pulado: cancelamento, teste vencido e inadimplencia davam teto INFINITO,
  -- e estornar a cobranca virava upgrade. Ver a secao 1 desta migration.
  declare
    plan_max int;
    lawyer_count int;
  begin
    plan_max := public.teto_de_advogados(law_firm_id_value);

    if plan_max = 0 then
      -- Teve licenca e nao tem mais. Erro PROPRIO, e nao o de teto cheio:
      -- "limite do plano" mandaria a pessoa fazer upgrade quando o que
      -- resolve o caso dela e pagar.
      raise exception 'Subscription is not active';
    end if;

    if plan_max is not null then
      select count(*) into lawyer_count
      from public.law_firm_members m
      where m.law_firm_id = law_firm_id_value
        and m.status in ('active', 'invited')
        and 'lawyer' = any(coalesce(m.roles::text[], array[m.member_role::text]));

      if lawyer_count >= plan_max then
        raise exception 'Lawyer seat limit reached for the current plan';
      end if;
    end if;
  end;

  normalized_oab_state := upper(trim(coalesce(oab_state_value, '')));
  normalized_oab_number := regexp_replace(
    upper(coalesce(oab_number_value, '')),
    '[^A-Z0-9]',
    '',
    'g'
  );

  if length(normalized_oab_state) <> 2 or normalized_oab_number = '' then
    raise exception 'Invalid OAB';
  end if;

  -- Serializa tentativas do mesmo ator para que chamadas concorrentes nao
  -- atravessem juntas o contador antes do INSERT.
  perform pg_catalog.pg_advisory_xact_lock(
    17001,
    pg_catalog.hashtext(auth.uid()::text)
  );

  if (
    select count(*)
    from public.law_firm_invitation_attempts attempt
    where attempt.actor_profile_id = auth.uid()
      and attempt.attempted_at >= now() - interval '1 hour'
  ) >= 20 then
    raise exception 'Too many invite attempts. Try again later';
  end if;

  insert into public.law_firm_invitation_attempts (
    actor_profile_id,
    law_firm_id
  )
  values (auth.uid(), law_firm_id_value);

  -- Dois managers do mesmo escritorio tambem podem tentar a mesma OAB ao
  -- mesmo tempo. Este lock torna a criacao/reutilizacao do convite atomica;
  -- colisoes de hash apenas serializam escopos independentes, sem liberar dado.
  perform pg_catalog.pg_advisory_xact_lock(
    17002,
    pg_catalog.hashtext(
      law_firm_id_value::text || ':' ||
      normalized_oab_state || ':' ||
      normalized_oab_number
    )
  );

  -- Primeiro resolve o perfil profissional aprovado pela OAB unica. Assim uma
  -- solicitacao posterior feita por terceiro com OAB alheia nao bloqueia o
  -- profissional legitimo.
  select lp.id
  into target_profile_id
  from public.lawyer_profiles lp
  join public.profiles p on p.id = lp.id
  where p.lawyer_status = 'approved'
    and p.deleted_at is null
    and upper(trim(lp.oab_state)) = normalized_oab_state
    and regexp_replace(
      upper(coalesce(lp.oab_number, '')),
      '[^A-Z0-9]',
      '',
      'g'
    ) = normalized_oab_number
  order by lp.approved_at desc nulls last, lp.created_at desc, lp.id
  limit 1;

  if not found then
    return gen_random_uuid();
  end if;

  -- Em seguida considera a decisao mais recente somente daquele titular. Uma
  -- recusa posterior nunca pode reutilizar uma aprovacao antiga.
  select lv.*
  into latest_verification
  from public.lawyer_verifications lv
  where lv.user_id = target_profile_id
    and upper(trim(lv.oab_state)) = normalized_oab_state
    and regexp_replace(
      upper(coalesce(lv.oab_number, '')),
      '[^A-Z0-9]',
      '',
      'g'
    ) = normalized_oab_number
  order by
    coalesce(lv.reviewed_at, lv.submitted_at, lv.created_at) desc,
    lv.created_at desc,
    lv.id desc
  limit 1;

  if not found or latest_verification.status <> 'approved' then
    return gen_random_uuid();
  end if;

  select *
  into existing_member
  from public.law_firm_members
  where law_firm_id = law_firm_id_value
    and (
      profile_id = target_profile_id
      or lawyer_id = target_profile_id
      or pending_lawyer_id = target_profile_id
    )
  limit 1;

  -- Resposta idempotente e indistinguivel: nao revela se o alvo ja esta ativo
  -- ou se ja recebeu convite.
  if found
      and existing_member.lawyer_id = target_profile_id
      and existing_member.lawyer_invite_status = 'active' then
    return gen_random_uuid();
  end if;

  if found
      and existing_member.lawyer_invite_status = 'invited'
      and (
        existing_member.lawyer_id = target_profile_id
        or existing_member.pending_lawyer_id = target_profile_id
      ) then
    return gen_random_uuid();
  end if;

  if not found then
    insert into public.law_firm_members (
      law_firm_id,
      lawyer_id,
      profile_id,
      role,
      member_role,
      roles,
      status,
      lawyer_invite_status,
      pending_lawyer_id
    )
    values (
      law_firm_id_value,
      target_profile_id,
      target_profile_id,
      'lawyer',
      'lawyer',
      array['lawyer']::text[],
      'invited',
      'invited',
      null
    )
    returning id into membership_id_value;
  else
    existing_is_manager :=
      existing_member.status = 'active'
      and existing_member.roles && array['owner', 'admin', 'secretary']::text[];

    update public.law_firm_members
    set
      profile_id = target_profile_id,
      lawyer_id = case
        when existing_is_manager then lawyer_id
        else target_profile_id
      end,
      pending_lawyer_id = case
        when existing_is_manager then target_profile_id
        else null
      end,
      lawyer_invite_status = 'invited',
      roles = case
        when existing_is_manager then roles
        else array['lawyer']::text[]
      end,
      status = case
        when existing_is_manager then status
        else 'invited'::public.law_firm_member_status
      end
    where id = existing_member.id
    returning id into membership_id_value;
  end if;

  select name
  into firm_name_value
  from public.law_firms
  where id = law_firm_id_value;

  insert into public.notifications (
    recipient_profile_id,
    actor_profile_id,
    law_firm_id,
    type,
    title,
    body,
    metadata
  )
  values (
    target_profile_id,
    auth.uid(),
    law_firm_id_value,
    'team_invite',
    'Convite para escritorio',
    coalesce(firm_name_value, 'Um escritorio') ||
      ' convidou voce para integrar a equipe.',
    jsonb_build_object(
      'membership_id', membership_id_value,
      'invite_status', null,
      'lawyer_invite_status', 'invited'
    )
  );

  return gen_random_uuid();
end;
$function$;

-- ---------------------------------------------------------------------------
-- 4. Aprovar escritorio passa a exigir licenca nao gasta
-- ---------------------------------------------------------------------------
--
-- Corpo verbatim da 20260902120000, com UMA mudanca: o bloco final, que
-- amarrava a licenca ao escritorio sem conferir se havia licenca para
-- amarrar.

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
    and sub.status <> 'canceled'
    -- E SO se a banca ainda nao tiver a dela. Sem esta linha, reverificar um
    -- escritorio ja licenciado enquanto o dono guarda uma licenca nova
    -- amarraria a segunda licenca ao mesmo escritorio, e o indice
    -- law_firm_license_one_per_firm derrubaria a aprovacao inteira.
    and not exists (
      select 1
      from public.law_firm_license_subscriptions atual
      where atual.law_firm_id = firm_id_value
        and atual.status <> 'canceled'
    );

  -- BANCA NOVA EXIGE LICENCA NAO GASTA.
  --
  -- has_law_firm_license e conferido quando a pessoa PEDE a abertura, e nao
  -- quando a equipe aprova. Com uma licenca so dava para pedir duas bancas:
  -- a primeira aprovacao gastava a licenca, a segunda atualizava ZERO linhas
  -- em silencio, e o escritorio nascia sem assinatura nenhuma. Sem assinatura
  -- nao havia teto de advogados, entao a segunda banca saia de graca e sem
  -- limite de equipe.
  --
  -- So vale para a banca que NASCE aqui. Reverificacao de escritorio que ja
  -- existe nao exige licenca nova: a dele ja esta amarrada.
  if verification_row.law_firm_id is null and not found then
    raise exception 'Owner has no unspent license';
  end if;

  return firm_id_value;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 5. Trocar de plano, e o caminho de volta depois do cancelamento
-- ---------------------------------------------------------------------------
--
-- DUAS mudancas sobre a 20260904120000:
--
--   a) Trocar de plano so vale enquanto NADA foi cobrado. Depois que o
--      dinheiro entrou, mudar `plan_code` aqui nao muda o valor da assinatura
--      no provedor: o escritorio passaria a usar o plano caro pagando o
--      barato, ou (pior para nos, e pior juridicamente) a pagar o caro tendo
--      pedido o barato. Enquanto a troca nao souber conversar com o provedor,
--      ela nao acontece: recusar e honesto, cobrar errado nao e.
--
--   b) Banca cujo cancelamento passou (estorno, chargeback, desistencia) pode
--      contratar de novo. Antes o ramo do escritorio so enxergava assinatura
--      nao cancelada, entao 'Firm has no subscription' era definitivo e o
--      escritorio ficava congelado para sempre sem caminho de volta na
--      aplicacao. A assinatura nova nasce 'past_due', e nao em teste: teste
--      de novo seria teste infinito para quem cancela e recontrata.
create or replace function public.choose_law_firm_plan(
  plan_code_value text,
  billing_cycle_value text default 'monthly',
  law_firm_id_value uuid default null
)
returns table (
  id uuid,
  plan_code text,
  billing_cycle text,
  status text,
  trial_ends_at timestamptz,
  law_firm_id uuid
)
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  plan public.law_firm_license_plans%rowtype;
  sub public.law_firm_license_subscriptions%rowtype;
  cycle text;
begin
  if caller is null then
    raise exception 'Not authenticated';
  end if;

  cycle := lower(btrim(coalesce(billing_cycle_value, 'monthly')));
  if cycle not in ('monthly', 'annual') then
    raise exception 'Unknown billing cycle: %', billing_cycle_value;
  end if;

  select * into plan
  from public.law_firm_license_plans p
  where p.code = plan_code_value and p.is_active;
  if not found then
    raise exception 'Unknown plan: %', coalesce(plan_code_value, '(null)');
  end if;

  -- Plano sem preco anual nao pode ser contratado no anual: cobrar um valor
  -- que a tabela nao tem seria inventar preco na hora.
  if cycle = 'annual' and plan.annual_price_cents is null then
    raise exception 'Plan has no annual price: %', plan.code;
  end if;

  -- ---------------------------------------------------------------------
  -- COM escritorio: trocar o plano DAQUELA banca
  -- ---------------------------------------------------------------------
  if law_firm_id_value is not null then
    -- Quem troca o plano de um escritorio e quem o administra, e quem
    -- responde isso e o mesmo helper de sempre. Sem esta linha, o id no
    -- corpo da requisicao trocaria o plano da banca dos outros.
    if not public.is_active_law_firm_manager(law_firm_id_value) then
      raise exception 'Only active office owners and admins can change the plan';
    end if;

    select * into sub
    from public.law_firm_license_subscriptions s
    where s.law_firm_id = law_firm_id_value
      and s.status <> 'canceled'
    order by s.created_at asc
    limit 1;

    if not found then
      -- O CAMINHO DE VOLTA (b). Nasce 'past_due' e sem teste: nada foi pago
      -- ainda, entao nada e liberado ate o webhook confirmar o dinheiro. Ate
      -- la teto_de_advogados responde 0, que e o mesmo que o escritorio ja
      -- vinha tendo desde o cancelamento.
      return query
      insert into public.law_firm_license_subscriptions
        (owner_profile_id, law_firm_id, plan_code, billing_cycle, status,
         trial_ends_at)
      values
        (caller, law_firm_id_value, plan.code, cycle, 'past_due', null)
      returning
        law_firm_license_subscriptions.id,
        law_firm_license_subscriptions.plan_code,
        law_firm_license_subscriptions.billing_cycle,
        law_firm_license_subscriptions.status,
        law_firm_license_subscriptions.trial_ends_at,
        law_firm_license_subscriptions.law_firm_id;
      return;
    end if;

    -- (a) Nada cobrado ainda quer dizer status 'trialing'. Teste vencido
    -- continua sendo 'trialing' na coluna, e continua podendo trocar: quem
    -- deixou o teste vencer nao pagou nada, entao nao ha valor no provedor
    -- para divergir.
    if sub.status <> 'trialing' then
      raise exception 'Plan change requires billing update';
    end if;

    -- Troca de plano ou de ciclo NAO renova o teste: pular de opcao em opcao
    -- nao pode virar teste infinito.
    update public.law_firm_license_subscriptions s
    set plan_code = plan.code, billing_cycle = cycle, updated_at = now()
    where s.id = sub.id;

    return query
    select s.id, s.plan_code, s.billing_cycle, s.status, s.trial_ends_at,
           s.law_firm_id
    from public.law_firm_license_subscriptions s
    where s.id = sub.id;
    return;
  end if;

  -- ---------------------------------------------------------------------
  -- SEM escritorio: uma licenca nova, para abrir uma banca
  -- ---------------------------------------------------------------------
  --
  -- Procura uma licenca JA COMPRADA E NAO GASTA antes de criar outra: e a
  -- pessoa mudando de ideia sobre o plano antes de abrir o escritorio, e ela
  -- nao pode virar duas cobrancas.
  select * into sub
  from public.law_firm_license_subscriptions s
  where s.owner_profile_id = caller
    and s.law_firm_id is null
    and s.status <> 'canceled'
  order by s.created_at asc
  limit 1;

  if found then
    -- A mesma trava de (a): licenca ja paga nao troca de plano por aqui.
    if sub.status <> 'trialing' then
      raise exception 'Plan change requires billing update';
    end if;

    update public.law_firm_license_subscriptions s
    set plan_code = plan.code, billing_cycle = cycle, updated_at = now()
    where s.id = sub.id;

    return query
    select s.id, s.plan_code, s.billing_cycle, s.status, s.trial_ends_at,
           s.law_firm_id
    from public.law_firm_license_subscriptions s
    where s.id = sub.id;
    return;
  end if;

  -- A trava antiga era "Firm already has a subscription": ela existia para
  -- dizer "uma pessoa, um plano", e caiu junto com essa premissa. O que ela
  -- protegia continua protegido pelo ramo de cima: cada escritorio tem a
  -- assinatura dele, e trocar o plano exige ser gestor daquela banca.
  return query
  insert into public.law_firm_license_subscriptions
    (owner_profile_id, plan_code, billing_cycle, status, trial_ends_at)
  values
    -- 30 dias sem cartao, qualquer que seja o ciclo: o teste e do produto,
    -- nao da forma de pagar.
    (caller, plan.code, cycle, 'trialing', now() + interval '30 days')
  returning
    law_firm_license_subscriptions.id,
    law_firm_license_subscriptions.plan_code,
    law_firm_license_subscriptions.billing_cycle,
    law_firm_license_subscriptions.status,
    law_firm_license_subscriptions.trial_ends_at,
    law_firm_license_subscriptions.law_firm_id;
end;
$$;

revoke all on function public.choose_law_firm_plan(text, text, uuid) from public, anon;
grant execute on function public.choose_law_firm_plan(text, text, uuid) to authenticated;

notify pgrst, 'reload schema';
