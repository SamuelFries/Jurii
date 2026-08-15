-- O teto nao pode ter porta dos fundos, e a assinatura nao pode ter duas vidas.
--
-- A 20260906120000 deu consequencia a status de assinatura. Uma revisao
-- adversarial das PROPRIAS correcoes achou quatro furos nelas, e tres sao do
-- tipo que faz o resto do trabalho nao valer nada.
--
--   1. O teto de advogados so existia no caminho do CONVITE. Promover um
--      secretario a advogado nao passava por trava nenhuma: com a assinatura
--      vencida (teto zero) a banca ganhava advogados de graca, e com a
--      assinatura viva dava para furar o teto do plano rebaixando um advogado,
--      convidando outro e repromovendo o primeiro. A consequencia que a
--      migration anterior inteira existe para criar era contornavel em dois
--      cliques na tela de equipe.
--
--   2. O caminho de volta depois do cancelamento inseria uma LINHA NOVA, com
--      id novo. Como o id da nossa assinatura e o `externalReference` que
--      amarra tudo no provedor, a busca de idempotencia do checkout nao
--      encontrava a assinatura que ainda estava viva la, e criava a segunda:
--      duas mensalidades recorrentes ao mesmo tempo, e so uma com efeito
--      aqui. O caminho de volta que a migration abriu era ele mesmo uma porta
--      de cobranca dupla.
--
--   3. O teste infinito foi fechado so de um lado. O ramo COM escritorio
--      passou a nascer 'past_due', mas o ramo da LICENCA NAO GASTA seguia
--      dando 30 dias novos a cada recontratacao. Cancelar e recontratar em
--      loop rendia teste eterno no plano Banca, que e o de 25 advogados.
--
-- O quarto furo e a corrida entre a busca e a criacao no provedor, e ele se
-- fecha aqui embaixo com uma coluna e um compare-and-set (secao 4).

-- ---------------------------------------------------------------------------
-- 1. Uma vaga de advogado, uma pergunta
-- ---------------------------------------------------------------------------
--
-- A contagem morava DENTRO de invite_verified_lawyer_to_law_firm, e por isso o
-- teto era propriedade do convite em vez de propriedade do escritorio. Aqui
-- ela vira funcao, e as duas portas que criam advogado chamam a mesma.
--
-- Levanta em vez de devolver boolean: quem chama nao pode esquecer de olhar a
-- resposta, e as duas mensagens de erro sao diferentes de proposito, porque as
-- saidas sao diferentes. Teto cheio se resolve trocando de plano; assinatura
-- parada se resolve pagando.
create or replace function public.exige_vaga_de_advogado(law_firm_id_value uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  teto int;
  advogados int;
begin
  teto := public.teto_de_advogados(law_firm_id_value);

  -- Sem teto: banca aprovada antes do licenciamento, ou plano negociado.
  if teto is null then
    return;
  end if;

  if teto = 0 then
    raise exception 'Subscription is not active';
  end if;

  -- Convidado ocupa vaga junto com ativo, senao daria para convidar 50 e
  -- deixa-los pingar por cima do teto.
  select count(*) into advogados
  from public.law_firm_members m
  where m.law_firm_id = law_firm_id_value
    and m.status in ('active', 'invited')
    and 'lawyer' = any(coalesce(m.roles::text[], array[m.member_role::text]));

  if advogados >= teto then
    raise exception 'Lawyer seat limit reached for the current plan';
  end if;
end;
$$;

revoke all on function public.exige_vaga_de_advogado(uuid)
  from public, anon, authenticated;

comment on function public.exige_vaga_de_advogado(uuid) is
  'Levanta se a banca nao pode ganhar mais um advogado. Chamada pelo convite E pela promocao.';

-- ---------------------------------------------------------------------------
-- 2. O convite passa a perguntar em vez de contar sozinho
-- ---------------------------------------------------------------------------

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
  -- equipe respeita o plano.
  --
  -- A CONTAGEM SAIU DAQUI. Enquanto ela morava dentro desta funcao, o teto so
  -- existia no caminho do CONVITE, e promover um membro que ja esta dentro
  -- passava por fora dele inteiro. Agora as duas portas chamam a mesma
  -- funcao, e fechar uma sem fechar a outra deixa de ser possivel.
  perform public.exige_vaga_de_advogado(law_firm_id_value);

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
-- 3. E a promocao tambem pergunta
-- ---------------------------------------------------------------------------
--
-- Corpo verbatim, com UMA adicao: a checagem de vaga quando 'lawyer' entra.

CREATE OR REPLACE FUNCTION public.update_law_firm_member_roles(law_firm_id_value uuid, member_profile_id_value uuid, roles_value text[])
 RETURNS text[]
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  target_member public.law_firm_members%rowtype;
  normalized_roles text[];
  primary_role text;
  actor_is_owner boolean;
  target_has_owner boolean;
  target_will_have_owner boolean;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  if coalesce(array_length(roles_value, 1), 0) = 0 then
    raise exception 'At least one firm role is required';
  end if;

  if not public.is_active_law_firm_manager(law_firm_id_value) then
    raise exception 'Only active office owners and admins can edit member roles';
  end if;

  actor_is_owner := public.has_law_firm_role(law_firm_id_value, 'owner');
  normalized_roles := public.normalize_law_firm_member_roles(roles_value);
  primary_role := public.primary_law_firm_member_role(normalized_roles);

  select *
  into target_member
  from public.law_firm_members
  where law_firm_id = law_firm_id_value
    and profile_id = member_profile_id_value
    and status <> 'disabled'
  for update;

  if not found then
    raise exception 'Firm member not found';
  end if;

  target_has_owner := 'owner' = any(target_member.roles);
  target_will_have_owner := 'owner' = any(normalized_roles);

  if target_has_owner and not actor_is_owner then
    raise exception 'Only owners can grant or remove owner role';
  end if;

  if target_has_owner is distinct from target_will_have_owner
      and not actor_is_owner then
    raise exception 'Only owners can grant or remove owner role';
  end if;

  if target_has_owner and not target_will_have_owner and not exists (
    select 1
    from public.law_firm_members lfm
    where lfm.law_firm_id = law_firm_id_value
      and lfm.profile_id <> member_profile_id_value
      and lfm.status = 'active'
      and 'owner' = any(lfm.roles)
  ) then
    raise exception 'Office must keep at least one owner';
  end if;

  -- A PORTA DOS FUNDOS DO TETO.
  --
  -- O teto de advogados vivia so no convite, entao qualquer gestor promovia um
  -- secretario a advogado e a banca crescia sem passar por trava nenhuma. Com
  -- a assinatura vencida (teto zero) dava para encher a banca de advogados sem
  -- pagar; com a assinatura viva dava para furar o teto do plano rebaixando um
  -- advogado, convidando outro (a contagem caiu) e repromovendo o primeiro.
  --
  -- So confere quando 'lawyer' esta ENTRANDO: rebaixar, ou mexer em qualquer
  -- outro papel, nao ocupa vaga nova e nao pode ser bloqueado por teto cheio.
  if 'lawyer' = any(normalized_roles)
     and not (
       'lawyer' = any(
         coalesce(target_member.roles, array[target_member.member_role::text])
       )
     )
  then
    perform public.exige_vaga_de_advogado(law_firm_id_value);
  end if;

  update public.law_firm_members
  set
    roles = normalized_roles,
    role = primary_role,
    member_role = primary_role::public.law_firm_member_role
  where id = target_member.id;

  return normalized_roles;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 4. O id da assinatura no provedor, e a corrida que ele fecha
-- ---------------------------------------------------------------------------
--
-- A idempotencia do checkout era "procure no provedor antes de criar", e entre
-- procurar e criar cabem tres viagens de rede sem trava nenhuma. Dois cliques
-- ao mesmo tempo, ou um retry depois de timeout, e nascem duas assinaturas
-- recorrentes. Pior: nada no nosso banco registrava qual assinatura do
-- provedor e a nossa, entao a duplicata era invisivel daqui, e a reconciliacao
-- de plano acertava so uma das duas enquanto a outra seguia cobrando o valor
-- velho para sempre.
--
-- A coluna resolve os dois lados. O indice unico e o arbitro da corrida: quem
-- grava primeiro ganha, e quem perde descobre que perdeu e apaga a duplicata
-- que acabou de criar no provedor.
alter table public.law_firm_license_subscriptions
  add column if not exists provider_subscription_id text;

comment on column public.law_firm_license_subscriptions.provider_subscription_id is
  'Id da assinatura no provedor de pagamento. Escrito uma vez, por compare-and-set.';

create unique index if not exists law_firm_license_provider_subscription_unica
  on public.law_firm_license_subscriptions (provider_subscription_id)
  where provider_subscription_id is not null;

-- COMPARE-AND-SET, e nao um UPDATE qualquer.
--
-- Devolve SEMPRE o vencedor, que e o unico jeito de quem perdeu a corrida
-- descobrir isso: a resposta diferente do que ele mandou e o sinal de que a
-- assinatura dele e duplicata e precisa ser apagada no provedor.
--
-- Escreve UMA VEZ. Deixar reescrever daria a qualquer dono a chance de apontar
-- a propria linha para a assinatura de outra pessoa no provedor.
create or replace function public.registrar_assinatura_no_provedor(
  assinatura_id_value uuid,
  provider_id_value text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  vencedor text;
begin
  if caller is null then
    raise exception 'Not authenticated';
  end if;

  -- O formato medido dos ids do Asaas. Sem isto a coluna aceitaria qualquer
  -- texto vindo do cliente, e ela e lida de volta para montar caminho de URL.
  if provider_id_value is null or provider_id_value !~ '^[a-z]{3}_[a-zA-Z0-9]+$' then
    raise exception 'Invalid provider subscription id';
  end if;

  -- SO O DONO, e a pergunta e feita UMA vez, explicitamente.
  --
  -- Separada do compare-and-set de proposito. Juntar as duas num where so
  -- parecia mais enxuto, mas deixava a trava de dono impossivel de observar:
  -- o `raise` la embaixo desfazia a escrita indevida junto com o resto, entao
  -- remover a condicao de dono nao mudava nada que desse para medir. Trava que
  -- nao da para sabotar e trava em que nao da para confiar.
  if not exists (
    select 1
    from public.law_firm_license_subscriptions s
    where s.id = assinatura_id_value
      and s.owner_profile_id = caller
  ) then
    raise exception 'Subscription not found';
  end if;

  -- COMPARE-AND-SET: escreve so enquanto esta vazia. Esta e a linha que decide
  -- a corrida, e o indice unico da coluna e o juiz.
  update public.law_firm_license_subscriptions s
  set provider_subscription_id = provider_id_value, updated_at = now()
  where s.id = assinatura_id_value
    and s.provider_subscription_id is null;

  select s.provider_subscription_id into vencedor
  from public.law_firm_license_subscriptions s
  where s.id = assinatura_id_value;

  return vencedor;
end;
$$;

revoke all on function public.registrar_assinatura_no_provedor(uuid, text)
  from public, anon;
grant execute on function public.registrar_assinatura_no_provedor(uuid, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Contratar: o caminho de volta reaproveita a linha, e o teste e um por
--    pessoa
-- ---------------------------------------------------------------------------
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
  ja_teve boolean;
  status_novo text;
  fim_do_teste timestamptz;
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

  -- O TESTE E UM POR PESSOA, e nao um por linha de assinatura. Quem ja teve
  -- qualquer assinatura, inclusive cancelada, nao ganha teste de novo: senao
  -- cancelar e recontratar em loop rende trinta dias gratis para sempre, no
  -- plano que a pessoa escolher.
  select exists (
    select 1 from public.law_firm_license_subscriptions s
    where s.owner_profile_id = caller
  ) into ja_teve;

  if ja_teve then
    status_novo := 'past_due';
    fim_do_teste := null;
  else
    -- 30 dias sem cartao, qualquer que seja o ciclo: o teste e do produto,
    -- nao da forma de pagar.
    status_novo := 'trialing';
    fim_do_teste := now() + interval '30 days';
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

    if found then
      -- Nada cobrado ainda quer dizer status 'trialing'. Teste vencido
      -- continua sendo 'trialing' na coluna, e continua podendo trocar: quem
      -- deixou o teste vencer nao pagou nada, entao nao ha valor no provedor
      -- para divergir.
      if sub.status <> 'trialing' then
        raise exception 'Plan change requires billing update';
      end if;

      -- Troca de plano ou de ciclo NAO renova o teste.
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

    -- O CAMINHO DE VOLTA, REAPROVEITANDO A LINHA CANCELADA.
    --
    -- Reaproveitar, e nao inserir outra, porque o id DESTA linha e o
    -- `externalReference` que amarra a assinatura la no provedor. Uma linha
    -- nova teria id novo, a busca de idempotencia do checkout nao acharia a
    -- assinatura que ainda esta viva no Asaas, e nasceria a segunda: duas
    -- mensalidades recorrentes ao mesmo tempo, com uma so tendo efeito aqui.
    select * into sub
    from public.law_firm_license_subscriptions s
    where s.law_firm_id = law_firm_id_value
    order by s.created_at desc
    limit 1;

    if found then
      update public.law_firm_license_subscriptions s
      set plan_code = plan.code,
          billing_cycle = cycle,
          -- Sempre a pagar, nunca em teste: o teste ja foi usado nesta linha.
          status = 'past_due',
          trial_ends_at = null,
          -- Quem recontrata passa a ser o dono, porque e quem vai pagar.
          owner_profile_id = caller,
          updated_at = now()
      where s.id = sub.id;

      return query
      select s.id, s.plan_code, s.billing_cycle, s.status, s.trial_ends_at,
             s.law_firm_id
      from public.law_firm_license_subscriptions s
      where s.id = sub.id;
      return;
    end if;

    -- Banca que nunca teve assinatura (aprovada antes do licenciamento)
    -- contratando pela primeira vez.
    return query
    insert into public.law_firm_license_subscriptions
      (owner_profile_id, law_firm_id, plan_code, billing_cycle, status,
       trial_ends_at)
    values
      (caller, law_firm_id_value, plan.code, cycle, status_novo, fim_do_teste)
    returning
      law_firm_license_subscriptions.id,
      law_firm_license_subscriptions.plan_code,
      law_firm_license_subscriptions.billing_cycle,
      law_firm_license_subscriptions.status,
      law_firm_license_subscriptions.trial_ends_at,
      law_firm_license_subscriptions.law_firm_id;
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
    -- Licenca ja paga nao troca de plano por aqui.
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

  return query
  insert into public.law_firm_license_subscriptions
    (owner_profile_id, plan_code, billing_cycle, status, trial_ends_at)
  values
    (caller, plan.code, cycle, status_novo, fim_do_teste)
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
