-- Licenciamento do escritorio: planos por tamanho de equipe, com paywall
-- ANTES da verificacao.
--
-- MODELO DE PRECO (decisao de produto, 08/08/2026): o valor acompanha o numero
-- de ADVOGADOS do escritorio. Todos os planos incluem tudo — o que muda e o
-- teto de advogados na equipe. Precos sao LINHAS nesta tabela: mudar preco e
-- um UPDATE, nao um release.
--
--     essencial   ate 3 advogados    R$ 149/mes   (~R$ 50/advogado)
--     escritorio  ate 10 advogados   R$ 349/mes   (~R$ 35/advogado)
--     banca       ate 25 advogados   R$ 699/mes   (~R$ 28/advogado)
--     acima de 25: contato direto (sem plano self-service)
--
-- Ancoragem: ferramentas de gestao cobram ~R$ 90+/usuario/mes so pela gestao;
-- aqui o valor e presenca onde o cliente procura + gestao, com preco por
-- advogado DECRESCENTE para nao punir escritorio que cresce.
--
-- TESTE GRATIS de 30 dias, sem cartao. Nao existe gateway de pagamento ainda;
-- a assinatura nasce 'trialing' e a COBRANCA sera feita fora do app (web),
-- quando o gateway existir — inclusive para nao entregar 30% do faturamento a
-- App Store. Por isso este MVP NAO expira teste automaticamente: bloquear
-- alguem sem oferecer caminho de pagamento seria beco sem saida. O modelo de
-- status ja preve o futuro (trialing/active/past_due/canceled).
--
-- A PAYWALL DE VERDADE fica no banco: a policy de INSERT de
-- law_firm_verifications passa a exigir assinatura. Tela e so convite; portao
-- que so existe na tela nao e portao.
--
-- ESCRITORIOS JA APROVADOS (40 em producao) NAO sao travados: entraram antes
-- da regra, e trava retroativa e quebra de acordo. O teto de advogados so vale
-- para quem TEM assinatura.

-- ---------------------------------------------------------------------------
-- 1. Planos: dados, nao codigo.
-- ---------------------------------------------------------------------------
create table if not exists public.law_firm_license_plans (
  code text primary key,
  name text not null,
  -- NULL = sem teto (reservado para negociacao direta; nenhum plano
  -- self-service nasce ilimitado).
  max_lawyers int check (max_lawyers is null or max_lawyers > 0),
  monthly_price_cents int not null check (monthly_price_cents >= 0),
  sort_order int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.law_firm_license_plans
  (code, name, max_lawyers, monthly_price_cents, sort_order)
values
  ('essencial',  'Essencial',  3,  14900, 10),
  ('escritorio', 'Escritório', 10, 34900, 20),
  ('banca',      'Banca',      25, 69900, 30)
on conflict (code) do nothing;

alter table public.law_firm_license_plans enable row level security;

drop policy if exists law_firm_license_plans_read
on public.law_firm_license_plans;
create policy law_firm_license_plans_read
on public.law_firm_license_plans for select
to authenticated
using (is_active = true);

revoke all on table public.law_firm_license_plans from public, anon;
grant select on table public.law_firm_license_plans to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Assinaturas.
--
-- Nascem ANTES do escritorio existir (a paywall vem antes da verificacao),
-- entao a chave e quem contratou; law_firm_id e vinculado na aprovacao.
-- ---------------------------------------------------------------------------
create table if not exists public.law_firm_license_subscriptions (
  id uuid primary key default gen_random_uuid(),
  owner_profile_id uuid not null references public.profiles(id)
    on delete cascade,
  law_firm_id uuid references public.law_firms(id) on delete set null,
  plan_code text not null references public.law_firm_license_plans(code),
  status text not null default 'trialing'
    check (status in ('trialing', 'active', 'past_due', 'canceled')),
  trial_ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Toda FK com indice (invariante do perf_invariants_test): sem eles, o
-- delete de um profile/plano/firma varreria a tabela inteira.
create index if not exists law_firm_license_subscriptions_owner_idx
on public.law_firm_license_subscriptions (owner_profile_id);

create index if not exists law_firm_license_subscriptions_firm_idx
on public.law_firm_license_subscriptions (law_firm_id);

create index if not exists law_firm_license_subscriptions_plan_idx
on public.law_firm_license_subscriptions (plan_code);

-- Uma assinatura viva por contratante, e uma por escritorio.
create unique index if not exists law_firm_license_one_per_owner
on public.law_firm_license_subscriptions (owner_profile_id)
where status <> 'canceled';

create unique index if not exists law_firm_license_one_per_firm
on public.law_firm_license_subscriptions (law_firm_id)
where law_firm_id is not null and status <> 'canceled';

alter table public.law_firm_license_subscriptions enable row level security;

-- Quem le: o contratante, e quem fala pelo escritorio vinculado (o plano
-- aparece no perfil do escritorio para socio/admin).
drop policy if exists law_firm_license_subscriptions_read
on public.law_firm_license_subscriptions;
create policy law_firm_license_subscriptions_read
on public.law_firm_license_subscriptions for select
to authenticated
using (
  owner_profile_id = (select auth.uid())
  or (
    law_firm_id is not null
    and public.is_active_law_firm_manager(law_firm_id)
  )
);

-- Escrita SO pela RPC.
revoke all on table public.law_firm_license_subscriptions from public, anon;
grant select on table public.law_firm_license_subscriptions to authenticated;

-- ---------------------------------------------------------------------------
-- 3. O portao, reutilizavel: tem licenca viva?
-- ---------------------------------------------------------------------------
create or replace function public.has_law_firm_license(profile_id_value uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.law_firm_license_subscriptions sub
    where sub.owner_profile_id = profile_id_value
      and sub.status in ('trialing', 'active')
  );
$$;

revoke all on function public.has_law_firm_license(uuid) from public, anon;
grant execute on function public.has_law_firm_license(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. A PAYWALL: verificar escritorio exige assinatura.
--
-- E a policy de INSERT que muda, nao a tela: portao que so existe na tela nao
-- e portao. A policy anterior (20260718200000) segue identica no resto.
-- ---------------------------------------------------------------------------
drop policy if exists law_firm_verifications_insert_own
on public.law_firm_verifications;
create policy law_firm_verifications_insert_own
on public.law_firm_verifications for insert
to authenticated
with check (
  owner_profile_id = (select auth.uid())
  and status in ('draft', 'pending')
  and law_firm_id is null
  and avatar_storage_path is null
  and reviewer_id is null
  and reviewed_at is null
  and rejection_reason is null
  -- A linha nova: sem plano escolhido, o cadastro nem entra.
  and public.has_law_firm_license((select auth.uid()))
);

-- ---------------------------------------------------------------------------
-- 5. Escolher plano (e trocar de plano).
-- ---------------------------------------------------------------------------
create or replace function public.choose_law_firm_plan(plan_code_value text)
returns table (
  id uuid,
  plan_code text,
  status text,
  trial_ends_at timestamptz,
  law_firm_id uuid
)
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  plan public.law_firm_license_plans%rowtype;
  sub public.law_firm_license_subscriptions%rowtype;
begin
  if caller is null then
    raise exception 'Not authenticated';
  end if;

  select * into plan
  from public.law_firm_license_plans p
  where p.code = plan_code_value and p.is_active;
  if not found then
    raise exception 'Unknown plan: %', coalesce(plan_code_value, '(null)');
  end if;

  select * into sub
  from public.law_firm_license_subscriptions s
  where s.owner_profile_id = caller and s.status <> 'canceled'
  limit 1;

  if found then
    -- Troca de plano NAO renova o teste: pular de plano em plano nao pode
    -- virar teste infinito.
    update public.law_firm_license_subscriptions s
    set plan_code = plan.code, updated_at = now()
    where s.id = sub.id;

    return query
    select s.id, s.plan_code, s.status, s.trial_ends_at, s.law_firm_id
    from public.law_firm_license_subscriptions s
    where s.id = sub.id;
    return;
  end if;

  -- Membro de um escritorio que JA tem assinatura (de outra pessoa) nao abre
  -- uma segunda: um escritorio, um plano, um pagante.
  if exists (
    select 1
    from public.law_firm_members m
    join public.law_firm_license_subscriptions s
      on s.law_firm_id = m.law_firm_id and s.status <> 'canceled'
    where m.profile_id = caller and m.status = 'active'
  ) then
    raise exception 'Firm already has a subscription';
  end if;

  return query
  insert into public.law_firm_license_subscriptions
    (owner_profile_id, plan_code, status, trial_ends_at)
  values
    -- 30 dias sem cartao: prazo para o escritorio VER movimento (caso
    -- juridico tem cadencia lenta; 7 dias nao mostrariam nada).
    (caller, plan.code, 'trialing', now() + interval '30 days')
  returning
    law_firm_license_subscriptions.id,
    law_firm_license_subscriptions.plan_code,
    law_firm_license_subscriptions.status,
    law_firm_license_subscriptions.trial_ends_at,
    law_firm_license_subscriptions.law_firm_id;
end;
$$;

revoke all on function public.choose_law_firm_plan(text) from public, anon;
grant execute on function public.choose_law_firm_plan(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. A aprovacao vincula a assinatura ao escritorio criado.
--    Corpo VERBATIM da definicao vigente; entra so o UPDATE do vinculo.
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- 7. O teto de advogados morde no CONVITE.
--    Corpo VERBATIM da definicao vigente; entra so o bloco do teto.
--
--    So vale para escritorio COM assinatura: os 40 aprovados antes desta
--    migration seguem convidando como sempre (sem trava retroativa).
--    Conta advogado ativo E convidado — convite pendente ocupa vaga, senao
--    daria para convidar 50 e deixa-los pingar por cima do teto.
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
  -- equipe respeita o plano. A troca de plano (upgrade) libera na hora.
  declare
    plan_max int;
    lawyer_count int;
  begin
    select p.max_lawyers into plan_max
    from public.law_firm_license_subscriptions s
    join public.law_firm_license_plans p on p.code = s.plan_code
    where s.law_firm_id = law_firm_id_value
      and s.status in ('trialing', 'active', 'past_due')
    limit 1;

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

notify pgrst, 'reload schema';
