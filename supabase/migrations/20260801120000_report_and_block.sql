-- Denúncia e bloqueio no chat (diretriz 1.2 da App Store: conteúdo gerado
-- por usuário exige mecanismo de denúncia e de bloqueio de usuários).
--
-- O bloqueio é POR CONVERSA e congela os DOIS lados: na Jurii todo contato
-- entre um par acontece numa única conversa (start_or_get_* devolve sempre a
-- mesma), então congelar a conversa bloqueia o par — e cobre também o balcão
-- do escritório, em que vários operadores falam pela mesma conversa e não
-- existe "a" contraparte para bloquear. Quem bloqueou pode desbloquear.
--
-- A trava fica num trigger de INSERT em messages (e não na policy): cobre
-- também os caminhos server-side que inserem mensagem (anexo via RPC,
-- sugestão de advogado) sem reescrever a policy endurecida do patch_041.
--
-- Denúncias ficam em user_reports, lidas só pelo back-office (padrão das
-- verificações). Nada aqui depende de e-mail externo.

-- ---------------------------------------------------------------------------
-- 1. Tabelas
-- ---------------------------------------------------------------------------

create table if not exists public.conversation_blocks (
  conversation_id uuid not null
    references public.conversations (id) on delete cascade,
  blocker_profile_id uuid not null
    references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (conversation_id, blocker_profile_id)
);

create index if not exists conversation_blocks_blocker_idx
  on public.conversation_blocks (blocker_profile_id);

create table if not exists public.user_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_profile_id uuid not null
    references public.profiles (id) on delete cascade,
  reported_profile_id uuid
    references public.profiles (id) on delete set null,
  law_firm_id uuid
    references public.law_firms (id) on delete set null,
  conversation_id uuid
    references public.conversations (id) on delete set null,
  message_id uuid
    references public.messages (id) on delete set null,
  reason text not null check (reason in (
    'conteudo_abusivo', 'golpe_ou_fraude', 'falsa_identidade', 'spam', 'outro'
  )),
  details text check (char_length(details) <= 1000),
  status text not null default 'open'
    check (status in ('open', 'reviewed', 'dismissed')),
  created_at timestamptz not null default now()
);

-- Toda FK com índice (invariante de perf_invariants_test).
create index if not exists user_reports_reporter_idx
  on public.user_reports (reporter_profile_id, created_at desc);
create index if not exists user_reports_reported_idx
  on public.user_reports (reported_profile_id);
create index if not exists user_reports_law_firm_idx
  on public.user_reports (law_firm_id);
create index if not exists user_reports_conversation_idx
  on public.user_reports (conversation_id);
create index if not exists user_reports_message_idx
  on public.user_reports (message_id);
create index if not exists user_reports_status_idx
  on public.user_reports (status, created_at desc);

-- Duas camadas, como featured_placements: RLS sem policy + revoke de tabela.
-- Toda escrita/leitura passa pelas RPCs SECURITY DEFINER abaixo; o
-- back-office lê pelo painel (service_role).
alter table public.conversation_blocks enable row level security;
alter table public.user_reports enable row level security;
revoke all on public.conversation_blocks from authenticated, anon;
revoke all on public.user_reports from authenticated, anon;

-- ---------------------------------------------------------------------------
-- 2. Trava de envio: conversa bloqueada não recebe mensagem de ninguém
-- ---------------------------------------------------------------------------

create or replace function public.enforce_conversation_not_blocked()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.conversation_blocks cb
    where cb.conversation_id = new.conversation_id
  ) then
    -- Marcador constante (sem eco de entrada): o app traduz para o usuário.
    raise exception 'conversation_blocked';
  end if;
  return new;
end;
$$;

drop trigger if exists messages_block_guard on public.messages;
create trigger messages_block_guard
  before insert on public.messages
  for each row
  execute function public.enforce_conversation_not_blocked();

-- Sem este segundo guard, anexar arquivo NOVO a uma mensagem ANTIGA própria
-- (INSERT direto em message_attachments, permitido pela policy) seria um
-- canal de conteúdo furando o bloqueio.
drop trigger if exists message_attachments_block_guard
  on public.message_attachments;
create trigger message_attachments_block_guard
  before insert on public.message_attachments
  for each row
  execute function public.enforce_conversation_not_blocked();

-- ---------------------------------------------------------------------------
-- 3. RPCs de bloqueio
-- ---------------------------------------------------------------------------

create or replace function public.block_conversation(
  conversation_id_value uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;
  if not public.can_access_conversation(conversation_id_value) then
    raise exception 'Conversation not found';
  end if;

  -- O canal interno da equipe não é UGC entre estranhos: um membro poderia
  -- congelar o escritório inteiro. Governança interna é do escritório.
  if exists (
    select 1
    from public.conversations c
    where c.id = conversation_id_value
      and c.type = 'firm_internal'
  ) then
    raise exception 'Internal conversation';
  end if;

  insert into public.conversation_blocks (conversation_id, blocker_profile_id)
  values (conversation_id_value, auth.uid())
  on conflict do nothing;
end;
$$;

create or replace function public.unblock_conversation(
  conversation_id_value uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  -- Só a própria trava — com uma exceção: dono/admin do escritório destrava
  -- bloqueios deixados por OPERADORES do próprio escritório (nunca o do
  -- cliente). Sem isso, um membro que bloqueou o balcão e saiu da equipe
  -- congelaria a conversa para sempre.
  delete from public.conversation_blocks cb
  where cb.conversation_id = conversation_id_value
    and (
      cb.blocker_profile_id = auth.uid()
      or exists (
        select 1
        from public.conversations c
        join public.law_firm_members admin_member
          on admin_member.law_firm_id = c.law_firm_id
        where c.id = cb.conversation_id
          and c.law_firm_id is not null
          and cb.blocker_profile_id is distinct from c.client_id
          and admin_member.profile_id = auth.uid()
          and admin_member.status = 'active'
          and admin_member.roles && array['owner', 'admin']
      )
    );
end;
$$;

create or replace function public.fetch_conversation_block_state(
  conversation_id_value uuid
)
returns table (is_blocked boolean, blocked_by_me boolean)
language sql
stable
security definer
set search_path = public
as $$
  select
    -- Quem não participa da conversa não aprende nada sobre ela.
    public.can_access_conversation(conversation_id_value)
      and exists (
        select 1
        from public.conversation_blocks cb
        where cb.conversation_id = conversation_id_value
      ),
    exists (
      select 1
      from public.conversation_blocks cb
      where cb.conversation_id = conversation_id_value
        and cb.blocker_profile_id = auth.uid()
    );
$$;

-- ---------------------------------------------------------------------------
-- 4. RPC de denúncia
-- ---------------------------------------------------------------------------

create or replace function public.report_conversation(
  conversation_id_value uuid,
  reason_value text,
  details_value text default null,
  message_id_value uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  conversation_row public.conversations%rowtype;
  reported_profile uuid;
  reported_firm uuid;
  clean_details text;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if reason_value is null or reason_value not in (
    'conteudo_abusivo', 'golpe_ou_fraude', 'falsa_identidade', 'spam', 'outro'
  ) then
    raise exception 'Invalid report reason';
  end if;

  if not public.can_access_conversation(conversation_id_value) then
    raise exception 'Conversation not found';
  end if;

  select * into conversation_row
  from public.conversations
  where id = conversation_id_value;

  -- O canal interno da equipe não tem "contraparte": a denúncia apontaria o
  -- membro errado. Conflito interno se resolve na governança do escritório.
  if conversation_row.type = 'firm_internal' then
    raise exception 'Internal conversation';
  end if;

  -- Contraparte denunciada: para o cliente, o advogado da conversa (ou o
  -- escritório, no balcão); para o profissional, o cliente.
  if conversation_row.client_id = auth.uid() then
    reported_profile := conversation_row.lawyer_id;
    reported_firm := case
      when conversation_row.lawyer_id is null then conversation_row.law_firm_id
    end;
  else
    reported_profile := conversation_row.client_id;
    reported_firm := null;
  end if;

  -- Mensagem denunciada precisa pertencer à própria conversa.
  if message_id_value is not null and not exists (
    select 1
    from public.messages m
    where m.id = message_id_value
      and m.conversation_id = conversation_id_value
  ) then
    raise exception 'Message not in conversation';
  end if;

  -- Serializa o antiflood por usuário: sem o lock, denúncias concorrentes
  -- passariam todas pelo count antes de qualquer insert aparecer.
  perform pg_advisory_xact_lock(
    hashtext('user_reports:' || auth.uid()::text)
  );

  -- Antiflood: 10 denúncias por usuário por dia.
  if (
    select count(*)
    from public.user_reports r
    where r.reporter_profile_id = auth.uid()
      and r.created_at > now() - interval '1 day'
  ) >= 10 then
    raise exception 'Report limit reached';
  end if;

  -- Texto livre: sem caracteres de controle e com teto — mesma blindagem
  -- da migration 20260730150000 (log injection).
  clean_details := nullif(btrim(left(
    regexp_replace(coalesce(details_value, ''), '[[:cntrl:]]+', ' ', 'g'),
    1000
  )), '');

  insert into public.user_reports (
    reporter_profile_id,
    reported_profile_id,
    law_firm_id,
    conversation_id,
    message_id,
    reason,
    details
  ) values (
    auth.uid(),
    reported_profile,
    reported_firm,
    conversation_id_value,
    message_id_value,
    reason_value,
    clean_details
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Grants
-- ---------------------------------------------------------------------------

revoke all on function public.enforce_conversation_not_blocked()
  from public, anon, authenticated;

revoke all on function public.block_conversation(uuid) from public, anon;
grant execute on function public.block_conversation(uuid) to authenticated;

revoke all on function public.unblock_conversation(uuid) from public, anon;
grant execute on function public.unblock_conversation(uuid) to authenticated;

revoke all on function public.fetch_conversation_block_state(uuid)
  from public, anon;
grant execute on function public.fetch_conversation_block_state(uuid)
  to authenticated;

revoke all on function public.report_conversation(uuid, text, text, uuid)
  from public, anon;
grant execute on function public.report_conversation(uuid, text, text, uuid)
  to authenticated;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Verificacao pos-push (SQL Editor):
--   select tgname from pg_trigger
--    where tgrelid = 'public.messages'::regclass and tgname = 'messages_block_guard';
--   select * from public.fetch_conversation_block_state('<id de conversa sua>');
-- ---------------------------------------------------------------------------
