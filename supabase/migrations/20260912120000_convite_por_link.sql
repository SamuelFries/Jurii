-- Convite por link de uso único: a porta de entrada de quem não tem OAB.
--
-- O ÚNICO convite que existia exigia advogado verificado
-- (invite_verified_lawyer_to_law_firm). Secretária e estagiário, que são
-- metade da operação de um escritório real, não tinham COMO entrar: o papel
-- existia no modelo, a tela de equipe sabia exibi-lo, e nenhum caminho o
-- criava. Este link fecha o buraco: o gestor gera, manda pelo canal que
-- quiser, e a pessoa entra com a própria conta.
--
-- AS DECISÕES QUE GUARDAM A PORTA:
--
--   Uso único, de verdade. O aceite tranca a linha (FOR UPDATE) e marca
--   used_at no mesmo passo: duas pessoas com o mesmo link, a segunda vê
--   "já usado", nunca duas entradas.
--
--   O token é guardado COMO SENHA. Só o hash SHA-256 fica na tabela; o link
--   inteiro aparece UMA vez, na criação. Se a tabela vazar por um erro de
--   RLS futuro, o que vaza não abre porta nenhuma.
--
--   Só secretária e estagiário. Advogado continua entrando pela OAB, porque
--   é lá que mora o teto pago do plano; admin e sócio por link seriam
--   escalação de privilégio se o link cair num grupo de WhatsApp. Quem
--   quiser promover, promove depois, pelo caminho que já exige sócio.
--
--   As regras da casa valem na porta nova: gestor cria, escritório com
--   assinatura parada não inclui NINGUÉM (teto_de_advogados = 0 recusa;
--   null, das bancas pré-licenciamento, passa), e o limitador é o MESMO
--   orçamento dos convites por OAB — abrir uma segunda porta não pode
--   dobrar o teto de tentativas.

-- ---------------------------------------------------------------------------
-- 1. A tabela
-- ---------------------------------------------------------------------------
create table if not exists public.law_firm_invite_links (
  id uuid primary key default gen_random_uuid(),
  law_firm_id uuid not null references public.law_firms (id) on delete cascade,
  created_by uuid not null references public.profiles (id) on delete cascade,
  member_role text not null check (member_role in ('secretary', 'intern')),
  token_hash text not null unique,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_by uuid references public.profiles (id) on delete set null,
  used_at timestamptz,
  revoked_at timestamptz
);

create index if not exists law_firm_invite_links_firm_idx
  on public.law_firm_invite_links (law_firm_id, created_at desc);
create index if not exists law_firm_invite_links_created_by_idx
  on public.law_firm_invite_links (created_by);
create index if not exists law_firm_invite_links_used_by_idx
  on public.law_firm_invite_links (used_by);

-- RLS ligada e NENHUMA policy, nenhuma grant de tabela: tudo passa pelas
-- funções abaixo. É o padrão da casa para tabela sensível (featured, push).
alter table public.law_firm_invite_links enable row level security;
revoke all on public.law_firm_invite_links from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Criar
-- ---------------------------------------------------------------------------
create or replace function public.criar_link_de_convite(
  law_firm_id_value uuid,
  member_role_value text
)
returns table (id uuid, token text, member_role text, expires_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  teto int;
  token_novo text;
  link_id uuid;
  vence timestamptz;
begin
  if caller is null then
    raise exception 'User must be authenticated';
  end if;

  if not public.is_active_law_firm_manager(law_firm_id_value) then
    raise exception 'Only active office owners and admins can invite';
  end if;

  -- A LISTA FECHADA. Advogado tem a porta da OAB (com o teto do plano);
  -- admin e sócio não entram por link que circula fora do app.
  if member_role_value not in ('secretary', 'intern') then
    raise exception 'Invite links are for secretary or intern roles only';
  end if;

  -- Escritório congelado não inclui ninguém, nem quem não ocupa vaga paga:
  -- a consequência da 20260906120000 é "não cresce", e crescer é crescer.
  -- null (banca pré-licenciamento) segue isento, como em toda trava.
  teto := public.teto_de_advogados(law_firm_id_value);
  if teto = 0 then
    raise exception 'Subscription is not active';
  end if;

  -- O MESMO orçamento do convite por OAB: mesma tabela de tentativas, mesmo
  -- advisory lock, mesmo teto. Portas diferentes, orçamento único, senão
  -- cada porta nova dobra o que um gestor apressado consegue disparar.
  perform pg_catalog.pg_advisory_xact_lock(
    17001,
    pg_catalog.hashtext(caller::text)
  );

  if (
    select count(*)
    from public.law_firm_invitation_attempts attempt
    where attempt.actor_profile_id = caller
      and attempt.attempted_at >= now() - interval '1 hour'
  ) >= 20 then
    raise exception 'Too many invite attempts. Try again later';
  end if;

  insert into public.law_firm_invitation_attempts (actor_profile_id, law_firm_id)
  values (caller, law_firm_id_value);

  -- 24 bytes aleatórios = 48 hex. O que se guarda é o hash: o token cru só
  -- existe no retorno desta chamada, uma vez.
  token_novo := encode(extensions.gen_random_bytes(24), 'hex');
  vence := now() + interval '7 days';

  insert into public.law_firm_invite_links
    (law_firm_id, created_by, member_role, token_hash, expires_at)
  values
    (law_firm_id_value, caller, member_role_value,
     encode(extensions.digest(token_novo, 'sha256'), 'hex'), vence)
  returning law_firm_invite_links.id into link_id;

  return query select link_id, token_novo, member_role_value, vence;
end;
$$;

revoke all on function public.criar_link_de_convite(uuid, text) from public, anon;
grant execute on function public.criar_link_de_convite(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Espiar, sem consumir
-- ---------------------------------------------------------------------------
--
-- A página do convite precisa dizer a quem chegou "o escritório X te chamou
-- para ser Y" ANTES de a pessoa ter conta. Por isso anon também executa. O
-- que ela devolve é só o que o portador do link já sabe por tê-lo recebido:
-- nome da banca, papel e se o link ainda vale. Nada de ids internos.
create or replace function public.espiar_link_de_convite(token_value text)
returns table (situacao text, firm_name text, firm_initials text, member_role text)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  link public.law_firm_invite_links%rowtype;
  banca public.law_firms%rowtype;
begin
  select * into link
  from public.law_firm_invite_links l
  where l.token_hash = encode(extensions.digest(coalesce(token_value, ''), 'sha256'), 'hex');

  if not found then
    return query select 'inexistente'::text, null::text, null::text, null::text;
    return;
  end if;

  select * into banca from public.law_firms f where f.id = link.law_firm_id;

  return query select
    case
      when link.revoked_at is not null then 'revogado'
      when link.used_at is not null then 'usado'
      when link.expires_at <= now() then 'expirado'
      else 'valido'
    end::text,
    banca.name, banca.initials, link.member_role;
end;
$$;

revoke all on function public.espiar_link_de_convite(text) from public;
grant execute on function public.espiar_link_de_convite(text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Aceitar
-- ---------------------------------------------------------------------------
create or replace function public.aceitar_link_de_convite(token_value text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  link public.law_firm_invite_links%rowtype;
  membro public.law_firm_members%rowtype;
  teto int;
begin
  if caller is null then
    raise exception 'User must be authenticated';
  end if;

  -- O TRANCO DO USO ÚNICO. FOR UPDATE serializa dois aceites simultâneos do
  -- mesmo link: o segundo espera o primeiro commitar e então vê used_at.
  select * into link
  from public.law_firm_invite_links l
  where l.token_hash = encode(extensions.digest(coalesce(token_value, ''), 'sha256'), 'hex')
  for update;

  if not found then
    raise exception 'Invite link not found';
  end if;
  if link.revoked_at is not null then
    raise exception 'Invite link was revoked';
  end if;
  if link.used_at is not null then
    raise exception 'Invite link already used';
  end if;
  if link.expires_at <= now() then
    raise exception 'Invite link expired';
  end if;

  select * into membro
  from public.law_firm_members m
  where m.law_firm_id = link.law_firm_id
    and m.profile_id = caller
  limit 1;

  -- Já-membro responde ANTES do congelamento: quem está dentro não está
  -- tentando crescer, e "assinatura parada" para essa pessoa seria o erro
  -- errado apontando o caminho errado.
  if found and membro.status = 'active' then
    raise exception 'Already a member of this firm';
  end if;

  -- O congelamento vale também NO ACEITE: o link pode ter nascido antes de a
  -- assinatura parar, e a janela entre criar e aceitar não pode contornar a
  -- regra de "não cresce".
  teto := public.teto_de_advogados(link.law_firm_id);
  if teto = 0 then
    raise exception 'Subscription is not active';
  end if;

  if found then
    -- Ex-membro (desativado) voltando pela porta nova: reentra com o papel
    -- DO LINK, não com o que tinha. Quem o convidou de novo escolheu o papel
    -- ao gerar o link.
    update public.law_firm_members m
    set roles = array[link.member_role],
        member_role = link.member_role::public.law_firm_member_role,
        role = link.member_role,
        status = 'active'
    where m.id = membro.id;
  else
    insert into public.law_firm_members
      (law_firm_id, profile_id, roles, member_role, role, status)
    values
      (link.law_firm_id, caller, array[link.member_role],
       link.member_role::public.law_firm_member_role, link.member_role,
       'active');
  end if;

  update public.law_firm_invite_links l
  set used_by = caller, used_at = now()
  where l.id = link.id;

  -- Quem administra fica sabendo que a porta foi usada. Escopo 'firm' na
  -- seção 7: notificação de gestão cai no sino do escritório, nunca no do
  -- cliente (a armadilha do escopo derivado do tipo, de sempre).
  insert into public.notifications (recipient_profile_id, actor_profile_id, law_firm_id, type, title, body)
  select m.profile_id, caller, link.law_firm_id, 'firm_member_joined',
         'Alguém entrou na equipe',
         coalesce(
           (select p.full_name from public.profiles p where p.id = caller),
           'Uma pessoa'
         ) || ' entrou como ' ||
         case link.member_role
           when 'secretary' then 'secretária'
           else 'estagiário'
         end || ' pelo link de convite.'
  from public.law_firm_members m
  where m.law_firm_id = link.law_firm_id
    and m.status = 'active'
    and m.profile_id <> caller
    and (m.roles && array['owner', 'admin']::text[]);

  return link.law_firm_id;
end;
$$;

revoke all on function public.aceitar_link_de_convite(text) from public, anon;
grant execute on function public.aceitar_link_de_convite(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Revogar
-- ---------------------------------------------------------------------------
create or replace function public.revogar_link_de_convite(link_id_value uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  link public.law_firm_invite_links%rowtype;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  select * into link
  from public.law_firm_invite_links l
  where l.id = link_id_value
  for update;

  if not found then
    raise exception 'Invite link not found';
  end if;

  if not public.is_active_law_firm_manager(link.law_firm_id) then
    raise exception 'Only active office owners and admins can revoke';
  end if;

  -- Revogar o já usado não desfaz a entrada (remover gente é outra tela,
  -- outra decisão); revogar duas vezes é no-op.
  update public.law_firm_invite_links l
  set revoked_at = coalesce(l.revoked_at, now())
  where l.id = link_id_value;
end;
$$;

revoke all on function public.revogar_link_de_convite(uuid) from public, anon;
grant execute on function public.revogar_link_de_convite(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Listar os links em aberto
-- ---------------------------------------------------------------------------
--
-- SEM O TOKEN, porque ele não existe mais: só o hash está guardado. O link
-- se copia na hora da criação ou se gera outro; é o mesmo contrato dos
-- tokens de API do GitHub, e é o que torna o vazamento da listagem inócuo.
create or replace function public.listar_links_de_convite(law_firm_id_value uuid)
returns table (
  id uuid,
  member_role text,
  created_at timestamptz,
  expires_at timestamptz,
  criado_por text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;
  if not public.is_active_law_firm_manager(law_firm_id_value) then
    raise exception 'Only active office owners and admins can list invites';
  end if;

  return query
  select l.id, l.member_role, l.created_at, l.expires_at,
         coalesce(p.full_name, 'Alguém da equipe')
  from public.law_firm_invite_links l
  left join public.profiles p on p.id = l.created_by
  where l.law_firm_id = law_firm_id_value
    and l.used_at is null
    and l.revoked_at is null
    and l.expires_at > now()
  order by l.created_at desc;
end;
$$;

revoke all on function public.listar_links_de_convite(uuid) from public, anon;
grant execute on function public.listar_links_de_convite(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. O escopo da notificação nova
-- ---------------------------------------------------------------------------
--
-- Corpo verbatim do vigente, com 'firm_member_joined' junto de
-- 'firm_case_started'. A armadilha de sempre: o sino filtra por escopo e o
-- escopo deriva do tipo — sem esta linha, o aviso de gestão cairia no sino
-- de CLIENTE do gestor e ninguém o veria.
create or replace function public.infer_notification_scope(
  type_value text,
  current_scope notification_scope default null::notification_scope
)
returns notification_scope
language sql
immutable
set search_path to 'public'
as $$
  select case
    when type_value in (
      'team_invite',
      'case_request_response',
      'lawyer_recommended',
      'appointment_reminder',
      'case_movement'
    ) then 'lawyer'::public.notification_scope
    when type_value in (
      'firm_case_started',
      'firm_member_joined'
    ) then 'firm'::public.notification_scope
    when type_value in (
      'case_request',
      'message',
      'case_update',
      'case_closed',
      'lawyer_recommendation'
    ) then 'client'::public.notification_scope
    else coalesce(current_scope, 'client'::public.notification_scope)
  end;
$$;

notify pgrst, 'reload schema';
