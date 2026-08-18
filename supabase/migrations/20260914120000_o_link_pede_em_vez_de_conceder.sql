-- O link de convite passa a PEDIR em vez de conceder.
--
-- O QUE O LINK NÃO FAZIA: verificar identidade. O gestor escolhia o papel e
-- mandava; quem abrisse primeiro virava membro. O uso único impedia a segunda
-- pessoa, mas não garantia que a primeira fosse a certa, e link circula em
-- WhatsApp, é encaminhado, cai em grupo, chega num celular emprestado.
--
-- POR QUE ISSO É GRAVE AQUI, e não é em produto qualquer: can_access_conversation
-- libera QUALQUER membro ativo do escritório a ler TODA conversa com cliente
-- da banca, sem filtro de papel e sem corte de data. Quem entra hoje lê o
-- histórico inteiro. Um link encaminhado é um estranho lendo a correspondência
-- sigilosa entre a banca e os clientes dela.
--
-- O DESENHO: o link autoriza um PAPEL; a aprovação verifica a IDENTIDADE.
--
--   Clicar CONSOME o link e cria uma solicitação pendente. Ninguém vira
--   membro clicando. Se o link ficasse vivo com pedido pendente, uma segunda
--   pessoa também pediria, e o uso único deixaria de significar algo.
--
--   Quem decide vê QUEM É: nome, e-mail e se o CPF está confirmado. É isso
--   que faz o gestor reconhecer ou estranhar; sem esses dados a aprovação
--   vira carimbo.
--
--   A corrida se resolve aqui, não na tela: FOR UPDATE na solicitação, o
--   primeiro decide, o segundo ouve quem decidiu.
--
--   RECUSA NÃO TEM CAMPO DE MOTIVO, de propósito: justificativa escrita no
--   calor do momento vira mensagem que a gente entrega, sem moderação
--   nenhuma. Recusar é fechar a porta, não explicar por quê.
--
--   Prazo de 7 dias, igual ao do link, senão pedido de março fica pendurado.

-- ---------------------------------------------------------------------------
-- 1. A solicitação
-- ---------------------------------------------------------------------------
create table if not exists public.law_firm_join_requests (
  id uuid primary key default gen_random_uuid(),
  law_firm_id uuid not null references public.law_firms (id) on delete cascade,
  invite_link_id uuid not null references public.law_firm_invite_links (id) on delete cascade,
  requester_id uuid not null references public.profiles (id) on delete cascade,
  member_role text not null check (member_role in ('secretary', 'intern')),
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  decided_by uuid references public.profiles (id) on delete set null,
  decided_at timestamptz
);

-- Um pedido PENDENTE por pessoa por banca. Sem isto, quem recebe dois links
-- (ou insiste) empilha pedidos e a tela de Equipe vira lista de duplicatas.
create unique index if not exists law_firm_join_requests_um_pendente
  on public.law_firm_join_requests (law_firm_id, requester_id)
  where status = 'pending';

create index if not exists law_firm_join_requests_firm_idx
  on public.law_firm_join_requests (law_firm_id, created_at desc);
create index if not exists law_firm_join_requests_requester_idx
  on public.law_firm_join_requests (requester_id, created_at desc);

-- As duas FKs restantes ganham indice porque DELETE no pai varreria a filha
-- inteira sem eles, e o caminho de exclusao de conta (LGPD) cascateia por
-- quase todas as tabelas. A barreira perf_invariants pegou as duas.
create index if not exists law_firm_join_requests_link_idx
  on public.law_firm_join_requests (invite_link_id);
create index if not exists law_firm_join_requests_decided_by_idx
  on public.law_firm_join_requests (decided_by);

alter table public.law_firm_join_requests enable row level security;
revoke all on public.law_firm_join_requests from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Clicar o link: consome e vira pedido
-- ---------------------------------------------------------------------------
create or replace function public.solicitar_entrada_por_link(token_value text)
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
  pedido_id uuid;
  quem text;
begin
  if caller is null then
    raise exception 'User must be authenticated';
  end if;

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

  -- Já-membro antes do congelamento: quem está dentro não está pedindo para
  -- crescer, e "assinatura parada" seria o erro errado apontando o caminho
  -- errado.
  if found and membro.status = 'active' then
    raise exception 'Already a member of this firm';
  end if;

  teto := public.teto_de_advogados(link.law_firm_id);
  if teto = 0 then
    raise exception 'Subscription is not active';
  end if;

  -- O LINK MORRE AQUI. Pedido pendente com link vivo deixaria uma segunda
  -- pessoa pedir pelo mesmo convite.
  update public.law_firm_invite_links l
  set used_by = caller, used_at = now()
  where l.id = link.id;

  insert into public.law_firm_join_requests
    (law_firm_id, invite_link_id, requester_id, member_role, expires_at)
  values
    (link.law_firm_id, link.id, caller, link.member_role,
     now() + interval '7 days')
  returning law_firm_join_requests.id into pedido_id;

  select coalesce(p.full_name, 'Uma pessoa') into quem
  from public.profiles p where p.id = caller;

  -- Avisa QUEM DECIDE. Escopo 'firm' (seção 6): aviso de gestão cai no sino
  -- do escritório, nunca no do cliente.
  insert into public.notifications
    (recipient_profile_id, actor_profile_id, law_firm_id, type, title, body, metadata)
  select m.profile_id, caller, link.law_firm_id, 'firm_join_requested',
         'Pedido para entrar na equipe',
         quem || ' quer entrar como ' ||
         case link.member_role when 'secretary' then 'secretária'
                               else 'estagiário' end ||
         '. Aprove ou recuse em Equipe.',
         jsonb_build_object('join_request_id', pedido_id)
  from public.law_firm_members m
  where m.law_firm_id = link.law_firm_id
    and m.status = 'active'
    and m.profile_id <> caller
    and (m.roles && array['owner', 'admin']::text[]);

  return pedido_id;
end;
$$;

revoke all on function public.solicitar_entrada_por_link(text) from public, anon;
grant execute on function public.solicitar_entrada_por_link(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Decidir
-- ---------------------------------------------------------------------------
create or replace function public.decidir_entrada_no_escritorio(
  request_id_value uuid,
  aprovar boolean
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  pedido public.law_firm_join_requests%rowtype;
  membro public.law_firm_members%rowtype;
  teto int;
  quem_decidiu text;
  quem_pediu text;
  banca text;
begin
  if caller is null then
    raise exception 'User must be authenticated';
  end if;

  -- A CORRIDA MORRE AQUI: dois gestores clicando ao mesmo tempo, o segundo
  -- espera o primeiro commitar e então lê o status já decidido.
  select * into pedido
  from public.law_firm_join_requests r
  where r.id = request_id_value
  for update;

  if not found then
    raise exception 'Join request not found';
  end if;

  if not public.is_active_law_firm_manager(pedido.law_firm_id) then
    raise exception 'Only active office owners and admins can decide';
  end if;

  if pedido.status <> 'pending' then
    select coalesce(p.full_name, 'Outra pessoa') into quem_decidiu
    from public.profiles p where p.id = pedido.decided_by;
    raise exception 'Join request already decided by %', quem_decidiu;
  end if;

  if pedido.expires_at <= now() then
    raise exception 'Join request expired';
  end if;

  select coalesce(p.full_name, 'Uma pessoa') into quem_pediu
  from public.profiles p where p.id = pedido.requester_id;
  select f.name into banca
  from public.law_firms f where f.id = pedido.law_firm_id;

  if not aprovar then
    update public.law_firm_join_requests r
    set status = 'rejected', decided_by = caller, decided_at = now()
    where r.id = pedido.id;

    -- QUEM PEDIU PRECISA SABER. Sem este aviso a pessoa fica olhando uma
    -- tela morta sem entender se deu certo. Sem motivo: recusar é fechar a
    -- porta, não explicar por quê.
    insert into public.notifications
      (recipient_profile_id, law_firm_id, type, title, body)
    values (pedido.requester_id, pedido.law_firm_id, 'firm_join_decided',
            'Pedido não aprovado',
            'O escritório ' || coalesce(banca, '') ||
            ' não aprovou seu pedido de entrada na equipe.');

    perform public.avisa_gestores_da_decisao(
      pedido.law_firm_id, caller, quem_pediu, false);
    return 'rejected';
  end if;

  -- O congelamento vale NA DECISÃO também: o pedido pode ter nascido antes
  -- de a assinatura parar, e a janela entre pedir e decidir não contorna a
  -- regra de "não cresce".
  teto := public.teto_de_advogados(pedido.law_firm_id);
  if teto = 0 then
    raise exception 'Subscription is not active';
  end if;

  select * into membro
  from public.law_firm_members m
  where m.law_firm_id = pedido.law_firm_id
    and m.profile_id = pedido.requester_id
  limit 1;

  if found and membro.status = 'active' then
    raise exception 'Already a member of this firm';
  end if;

  if found then
    update public.law_firm_members m
    set roles = array[pedido.member_role],
        member_role = pedido.member_role::public.law_firm_member_role,
        role = pedido.member_role,
        status = 'active'
    where m.id = membro.id;
  else
    insert into public.law_firm_members
      (law_firm_id, profile_id, roles, member_role, role, status)
    values
      (pedido.law_firm_id, pedido.requester_id, array[pedido.member_role],
       pedido.member_role::public.law_firm_member_role, pedido.member_role,
       'active');
  end if;

  update public.law_firm_join_requests r
  set status = 'approved', decided_by = caller, decided_at = now()
  where r.id = pedido.id;

  insert into public.notifications
    (recipient_profile_id, law_firm_id, type, title, body)
  values (pedido.requester_id, pedido.law_firm_id, 'firm_join_decided',
          'Você entrou na equipe',
          'O escritório ' || coalesce(banca, '') ||
          ' aprovou sua entrada como ' ||
          case pedido.member_role when 'secretary' then 'secretária'
                                  else 'estagiário' end || '.');

  perform public.avisa_gestores_da_decisao(
    pedido.law_firm_id, caller, quem_pediu, true);
  return 'approved';
end;
$$;

revoke all on function public.decidir_entrada_no_escritorio(uuid, boolean)
  from public, anon;
grant execute on function public.decidir_entrada_no_escritorio(uuid, boolean)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 4. O aviso aos OUTROS gestores
-- ---------------------------------------------------------------------------
--
-- Existe para dois admins não decidirem em paralelo e para haver registro de
-- quem decidiu. Não vai para quem decidiu (ela sabe) nem para quem pediu (ela
-- recebe a própria, com a linguagem dela).
create or replace function public.avisa_gestores_da_decisao(
  law_firm_id_value uuid,
  decisor_id uuid,
  quem_pediu text,
  aprovado boolean
)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.notifications
    (recipient_profile_id, actor_profile_id, law_firm_id, type, title, body)
  select m.profile_id, decisor_id, law_firm_id_value, 'firm_join_decided_admin',
         case when aprovado then 'Entrada aprovada' else 'Entrada recusada' end,
         coalesce(
           (select p.full_name from public.profiles p where p.id = decisor_id),
           'Um gestor'
         ) || (case when aprovado then ' aprovou ' else ' recusou ' end) ||
         'o pedido de ' || quem_pediu || '.'
  from public.law_firm_members m
  where m.law_firm_id = law_firm_id_value
    and m.status = 'active'
    and m.profile_id <> decisor_id
    and (m.roles && array['owner', 'admin']::text[]);
$$;

revoke all on function public.avisa_gestores_da_decisao(uuid, uuid, text, boolean)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. Listar: para quem decide, e para quem pediu
-- ---------------------------------------------------------------------------
create or replace function public.listar_pedidos_de_entrada(law_firm_id_value uuid)
returns table (
  id uuid,
  requester_name text,
  requester_email text,
  cpf_confirmado boolean,
  member_role text,
  created_at timestamptz,
  expires_at timestamptz
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
    raise exception 'Only active office owners and admins can list requests';
  end if;

  return query
  select r.id,
         coalesce(p.full_name, 'Sem nome'),
         coalesce(p.email, ''),
         -- O QUE FAZ A APROVAÇÃO VALER ALGO: quem decide precisa reconhecer
         -- a pessoa. CPF confirmado é o sinal mais forte que temos, e vai
         -- como BOOLEANO: o número em si não é da conta do gestor.
         (p.cpf is not null and length(regexp_replace(p.cpf, '\D', '', 'g')) = 11),
         r.member_role, r.created_at, r.expires_at
  from public.law_firm_join_requests r
  join public.profiles p on p.id = r.requester_id
  where r.law_firm_id = law_firm_id_value
    and r.status = 'pending'
    and r.expires_at > now()
  order by r.created_at asc;
end;
$$;

revoke all on function public.listar_pedidos_de_entrada(uuid) from public, anon;
grant execute on function public.listar_pedidos_de_entrada(uuid) to authenticated;

-- O meu pedido, para a tela de espera de quem clicou saber o que dizer.
create or replace function public.meu_pedido_de_entrada(law_firm_id_value uuid)
returns table (situacao text, firm_name text, member_role text)
language sql
stable
security definer
set search_path = public
as $$
  select case
           when r.expires_at <= now() and r.status = 'pending' then 'expirado'
           else r.status
         end,
         f.name, r.member_role
  from public.law_firm_join_requests r
  join public.law_firms f on f.id = r.law_firm_id
  where r.requester_id = (select auth.uid())
    and r.law_firm_id = law_firm_id_value
  order by r.created_at desc
  limit 1;
$$;

revoke all on function public.meu_pedido_de_entrada(uuid) from public, anon;
grant execute on function public.meu_pedido_de_entrada(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. O escopo dos tipos novos
-- ---------------------------------------------------------------------------
--
-- Corpo verbatim do vigente, com os três tipos novos. A armadilha de sempre:
-- o sino filtra por escopo e o escopo deriva do tipo.
--
--   firm_join_requested / firm_join_decided_admin -> 'firm' (gestão)
--   firm_join_decided -> escopo de QUEM PEDIU, que ainda não é da banca:
--     ela lê pelo sino de cliente, o único que ela tem antes de entrar.
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
      'firm_member_joined',
      'firm_join_requested',
      'firm_join_decided_admin'
    ) then 'firm'::public.notification_scope
    when type_value in (
      'case_request',
      'message',
      'case_update',
      'case_closed',
      'lawyer_recommendation',
      'firm_join_decided'
    ) then 'client'::public.notification_scope
    else coalesce(current_scope, 'client'::public.notification_scope)
  end;
$$;

-- ---------------------------------------------------------------------------
-- 7. A espiada reconhece o dono do pedido
-- ---------------------------------------------------------------------------
--
-- Corpo verbatim da 20260912120000, com UMA adição: quem já clicou e voltou
-- ao link não pode ler "já foi usado". Foi ELA quem usou, e a resposta certa
-- é o estado do pedido dela. Sem isto, a pessoa que aguarda aprovação reabre
-- o link e conclui que perdeu a vaga.
--
-- Só para quem consumiu o link (used_by = auth.uid()); para todo o resto a
-- resposta continua a de antes, e anon segue enxergando só banca e papel.
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
  meu public.law_firm_join_requests%rowtype;
begin
  select * into link
  from public.law_firm_invite_links l
  where l.token_hash = encode(extensions.digest(coalesce(token_value, ''), 'sha256'), 'hex');

  if not found then
    return query select 'inexistente'::text, null::text, null::text, null::text;
    return;
  end if;

  select * into banca from public.law_firms f where f.id = link.law_firm_id;

  if link.used_by is not null and link.used_by = (select auth.uid()) then
    select * into meu
    from public.law_firm_join_requests r
    where r.invite_link_id = link.id
      and r.requester_id = (select auth.uid())
    order by r.created_at desc
    limit 1;

    if found then
      return query select
        case
          when meu.status = 'approved' then 'meu_pedido_aprovado'
          when meu.status = 'rejected' then 'meu_pedido_recusado'
          when meu.expires_at <= now() then 'meu_pedido_expirado'
          else 'meu_pedido_pendente'
        end::text,
        banca.name, banca.initials, link.member_role;
      return;
    end if;
  end if;

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

notify pgrst, 'reload schema';
