-- Confirmacao de visualizacao no chat: enviado, entregue e visto.
--
-- A coluna messages.read_at existia desde o baseline e NUNCA era escrita: o
-- balao mostrava um tique cinza para sempre, em toda mensagem, e o contador de
-- nao lidas da lista de conversas era literalmente `unreadCount: 0` no app.
-- Esta migration liga os tres estados de verdade.
--
-- O QUE CADA ESTADO SIGNIFICA (e por que nao mentimos em nenhum):
--   enviado   read_at e delivered_at nulos. O servidor tem a mensagem.
--   entregue  delivered_at preenchido. O aparelho de quem recebe carregou a
--             lista de conversas — ou seja, o app do outro lado esteve aberto
--             depois da mensagem existir.
--   visto     read_at preenchido. A conversa foi ABERTA por quem recebe.
--
-- CONVERSA DE ESCRITORIO e canal de equipe tem varios destinatarios. Aqui
-- "visto" quer dizer ALGUEM do outro lado abriu, nao "todos abriram" — um
-- balcao de escritorio e caixa compartilhada, e o que o cliente precisa saber
-- e se a mensagem dele chegou a olhos humanos.

alter table public.messages
  add column if not exists delivered_at timestamptz;

-- Historico: tudo que existe hoje e tratado como resolvido.
--
-- A alternativa seria deixar nulo, e ai todo cliente abriria o app depois da
-- atualizacao com um badge somando meses de conversa como "nao lida" — um
-- alarme falso de tamanho proporcional ao tempo de uso. Como nunca houve
-- registro de leitura, qualquer valor aqui e suposicao; a menos ruim e a que
-- nao inventa trabalho para ninguem. Vale UMA vez, so para as linhas que ja
-- existiam quando esta migration rodou.
update public.messages
set read_at = coalesce(read_at, created_at),
    delivered_at = coalesce(delivered_at, created_at)
where read_at is null
   or delivered_at is null;

-- Os dois filtros que as consultas novas fazem o tempo todo. Parciais porque
-- a parte interessante e sempre a minoria: mensagem lida nunca mais volta a
-- ser nao lida.
create index if not exists messages_unread_idx
  on public.messages(conversation_id)
  where read_at is null;

create index if not exists messages_undelivered_idx
  on public.messages(conversation_id)
  where delivered_at is null;

-- ---------------------------------------------------------------------------
-- 1. Marcar como VISTO: a conversa foi aberta
-- ---------------------------------------------------------------------------
create or replace function public.mark_conversation_read(
  conversation_id_value uuid
)
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  marked integer;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  -- Mesma mensagem de block_conversation: quem nao participa nao descobre se
  -- a conversa existe.
  if not public.can_access_conversation(conversation_id_value) then
    raise exception 'Conversation not found';
  end if;

  -- `sender_id is distinct from auth.uid()` é o que impede alguem de marcar a
  -- PROPRIA mensagem como vista e forjar o tique azul no aparelho do outro.
  update public.messages
  set read_at = now(),
      delivered_at = coalesce(delivered_at, now())
  where conversation_id = conversation_id_value
    and sender_id is distinct from auth.uid()
    and read_at is null;

  get diagnostics marked = row_count;
  return marked;
end;
$$;

revoke all on function public.mark_conversation_read(uuid) from public, anon;
grant execute on function public.mark_conversation_read(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Marcar como ENTREGUE: o app de quem recebe carregou a lista
-- ---------------------------------------------------------------------------
create or replace function public.mark_messages_delivered(
  conversation_ids_value uuid[]
)
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  clean_ids uuid[];
  marked integer;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select array_agg(distinct conversation_id)
  into clean_ids
  from unnest(coalesce(conversation_ids_value, array[]::uuid[]))
    as ids(conversation_id)
  where conversation_id is not null;

  clean_ids := coalesce(clean_ids, array[]::uuid[]);

  if cardinality(clean_ids) = 0 then
    return 0;
  end if;

  -- A lista vem da tela de conversas, que carrega dezenas. O teto existe para
  -- a chamada nao virar varredura da tabela inteira se alguem mandar um array
  -- gigante direto na API.
  if cardinality(clean_ids) > 200 then
    raise exception 'Too many conversations';
  end if;

  -- can_access_conversation e chamada UMA vez por conversa (no CTE), nao uma
  -- vez por mensagem: a diferenca aparece em conversa longa.
  with allowed as (
    select c.id
    from public.conversations c
    where c.id = any(clean_ids)
      and public.can_access_conversation(c.id)
  )
  update public.messages message
  set delivered_at = now()
  from allowed
  where message.conversation_id = allowed.id
    and message.sender_id is distinct from auth.uid()
    and message.delivered_at is null;

  get diagnostics marked = row_count;
  return marked;
end;
$$;

revoke all on function public.mark_messages_delivered(uuid[]) from public, anon;
grant execute on function public.mark_messages_delivered(uuid[])
to authenticated;

-- ---------------------------------------------------------------------------
-- 3. A lista de conversas passa a devolver o contador de nao lidas.
--    Corpo VERBATIM do que esta em producao; muda so a assinatura e a coluna
--    nova. Mudar RETURNS TABLE exige drop + create (e refazer o grant, que o
--    drop devolve para PUBLIC).
-- ---------------------------------------------------------------------------
drop function public.fetch_conversations_for_current_user(text, uuid);

create function public.fetch_conversations_for_current_user(scope_value text, law_firm_id_value uuid DEFAULT NULL::uuid)
 RETURNS TABLE(id uuid, type text, title text, initials text, avatar_url text, specialty text, last_message text, last_message_at timestamp with time zone, law_firm_id uuid, client_id uuid, lawyer_id uuid, unread_count integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with scoped_conversations as (
    select conversation.*
    from public.conversations conversation
    where auth.uid() is not null
      and exists (
        select 1
        from public.messages message
        where message.conversation_id = conversation.id
      )
      and (
        (
          scope_value = 'client'
          and conversation.client_id = auth.uid()
        )
        or (
          scope_value = 'lawyer'
          and conversation.type <> 'firm_internal'
          and (
            conversation.lawyer_id = auth.uid()
            or (
              conversation.case_id is not null
              and public.can_access_case(conversation.case_id)
            )
          )
        )
        or (
          scope_value = 'firmClient'
          and law_firm_id_value is not null
          and conversation.law_firm_id = law_firm_id_value
          and conversation.type <> 'firm_internal'
          and exists (
            select 1
            from public.law_firm_members member
            where member.law_firm_id = law_firm_id_value
              and member.profile_id = auth.uid()
              and member.status = 'active'
          )
        )
        or (
          scope_value = 'firmTeam'
          and law_firm_id_value is not null
          and conversation.law_firm_id = law_firm_id_value
          and conversation.type = 'firm_internal'
          and exists (
            select 1
            from public.law_firm_members member
            where member.law_firm_id = law_firm_id_value
              and member.profile_id = auth.uid()
              and member.status = 'active'
          )
        )
      )
  )
  select
    conversation.id,
    conversation.type::text,
    case
      when scope_value in ('lawyer', 'firmClient') then
        public.profile_display_name(
          client_profile.full_name,
          client_profile.deleted_display_name,
          client_profile.deleted_at
        )
      when scope_value = 'client'
           and conversation.lawyer_id is not null then
        public.profile_display_name(
          lawyer_profile.full_name,
          lawyer_profile.deleted_display_name,
          lawyer_profile.deleted_at
        )
      when scope_value = 'client'
           and conversation.law_firm_id is not null then
        coalesce(firm.name, conversation.title)
      else conversation.title
    end as title,
    case
      when scope_value in ('lawyer', 'firmClient') then
        coalesce(client_profile.initials, 'CL')
      when scope_value = 'client'
           and conversation.lawyer_id is not null then
        coalesce(lawyer_profile.initials, 'AJ')
      when scope_value = 'client'
           and conversation.law_firm_id is not null then
        coalesce(firm.initials, 'JE')
      else upper(left(trim(conversation.title), 2))
    end as initials,
    case
      when scope_value in ('lawyer', 'firmClient') then
        public.safe_profile_avatar_url(
          client_profile.id,
          client_profile.avatar_url
        )
      when scope_value = 'client'
           and conversation.lawyer_id is not null then
        public.safe_profile_avatar_url(
          lawyer_profile.id,
          lawyer_profile.avatar_url
        )
      when scope_value = 'client'
           and conversation.law_firm_id is not null then firm.avatar_url
      else null::text
    end as avatar_url,
    case
      when scope_value = 'firmClient'
           and conversation.lawyer_id is not null then
        public.profile_display_name(
          lawyer_profile.full_name,
          lawyer_profile.deleted_display_name,
          lawyer_profile.deleted_at
        ) || ' · ' || coalesce(conversation.specialty, 'Atendimento jurídico')
      else coalesce(conversation.specialty, 'Atendimento jurídico')
    end as specialty,
    coalesce(conversation.last_message, 'Nova conversa') as last_message,
    conversation.last_message_at,
    conversation.law_firm_id,
    conversation.client_id,
    conversation.lawyer_id,
    -- Nao lidas = o que chegou de OUTRA pessoa e ainda nao foi aberto. A
    -- propria mensagem nunca conta, senao a lista marcaria badge para quem
    -- acabou de escrever. Indice parcial messages_unread_idx serve este filtro.
    (
      select count(*)::integer
      from public.messages unread
      where unread.conversation_id = conversation.id
        and unread.sender_id is distinct from auth.uid()
        and unread.read_at is null
    ) as unread_count
  from scoped_conversations conversation
  left join public.profiles client_profile
    on client_profile.id = conversation.client_id
  left join public.law_firms firm
    on firm.id = conversation.law_firm_id
  left join public.profiles lawyer_profile
    on lawyer_profile.id = conversation.lawyer_id
  order by conversation.last_message_at desc nulls last,
    conversation.updated_at desc;
$function$;

revoke all on function public.fetch_conversations_for_current_user(text, uuid)
from public, anon;

grant execute on function public.fetch_conversations_for_current_user(text, uuid)
to authenticated;

notify pgrst, 'reload schema';
