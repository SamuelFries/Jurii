-- Apagar mensagem no chat: "para mim" e "para todos".
--
-- Os dois sao coisas diferentes de proposito, como no WhatsApp:
--
--   PARA MIM     some da minha tela e de mais lugar nenhum. E uma linha em
--                message_deletions; a mensagem continua intacta para o outro.
--
--   PARA TODOS   apaga o CONTEUDO para todo mundo e deixa a lapide no lugar.
--                So o autor pode, e so dentro da janela de tempo.
--
-- JANELA DE 60 HORAS (2 dias e meio), a mesma referencia do WhatsApp. Existe
-- porque "apagar para todos" reescreve o que a outra pessoa ja leu: sem prazo,
-- daria para apagar uma promessa de um mes atras depois que ela virou
-- problema. Num aplicativo onde a conversa e prova de relacao entre cliente e
-- advogado, isso importa mais do que no WhatsApp, nao menos.
--
-- O QUE "PARA TODOS" REALMENTE FAZ: zera body e metadata e apaga a linha de
-- message_attachments. Nao basta esconder na interface — a policy de leitura
-- devolve a linha inteira para quem participa da conversa, entao deixar o
-- texto ali significaria que um cliente com a API na mao continuaria lendo o
-- que foi "apagado". Sem a linha de message_attachments, a policy do Storage
-- tambem deixa de liberar o arquivo: a foto fica ilegivel para todos. O objeto
-- em si vira orfao no bucket (a limpeza de orfaos continua pendente).

-- ---------------------------------------------------------------------------
-- 1. "Apagar para mim": uma linha por pessoa
-- ---------------------------------------------------------------------------

create table if not exists public.message_deletions (
  message_id uuid not null references public.messages(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (message_id, profile_id)
);

-- A chave primaria ja serve a busca por (message_id, profile_id); este indice
-- e para o caminho inverso, quando o dono da conta e apagado em cascata.
create index if not exists message_deletions_profile_idx
  on public.message_deletions(profile_id);

alter table public.message_deletions enable row level security;

drop policy if exists message_deletions_select_own on public.message_deletions;

create policy message_deletions_select_own
on public.message_deletions for select
to authenticated
using (profile_id = (select auth.uid()));

revoke all on table public.message_deletions from public, anon, authenticated;

-- SELECT precisa existir, e a razao nao e obvia: a policy de messages (secao
-- 3) consulta esta tabela, e expressao de RLS roda com os privilegios de QUEM
-- CONSULTA. Sem este grant, ler qualquer mensagem estoura "permission denied
-- for table message_deletions" — a conversa inteira para de carregar. A policy
-- acima limita o que se ve as proprias linhas, que e informacao de quem ja e
-- dono dela. Escrita continua fechada: so as RPCs gravam.
grant select on table public.message_deletions to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Lapide de "apagar para todos"
-- ---------------------------------------------------------------------------

alter table public.messages
  add column if not exists deleted_for_all_at timestamptz;

-- ---------------------------------------------------------------------------
-- 3. A mensagem apagada "para mim" para de existir para mim
--
--    Fica na RLS, e nao numa consulta do app, porque assim vale para TODO
--    caminho de leitura de uma vez: o fetch da conversa, o tempo real (o
--    Supabase checa a policy antes de entregar o evento) e qualquer consulta
--    futura. Filtrar no app deixaria a mensagem reaparecendo pelo realtime.
-- ---------------------------------------------------------------------------

alter policy "messages_select_related" on public.messages
  using (
    can_access_conversation(conversation_id)
    and not exists (
      select 1
      from public.message_deletions hidden
      where hidden.message_id = messages.id
        and hidden.profile_id = (select auth.uid())
    )
  );

-- ---------------------------------------------------------------------------
-- 4. RPCs
-- ---------------------------------------------------------------------------

create or replace function public.delete_messages_for_me(
  message_ids_value uuid[]
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

  select array_agg(distinct message_id)
  into clean_ids
  from unnest(coalesce(message_ids_value, array[]::uuid[]))
    as ids(message_id)
  where message_id is not null;

  clean_ids := coalesce(clean_ids, array[]::uuid[]);

  if cardinality(clean_ids) = 0 then
    return 0;
  end if;

  -- Teto igual ao da selecao na tela. Sem ele, uma chamada direta na API
  -- viraria varredura da tabela de mensagens.
  if cardinality(clean_ids) > 100 then
    raise exception 'Too many messages';
  end if;

  insert into public.message_deletions (message_id, profile_id)
  select message.id, auth.uid()
  from public.messages message
  where message.id = any(clean_ids)
    -- Sem esta checagem daria para esconder mensagem de conversa alheia. Nao
    -- vaza conteudo, mas suja a tabela de quem nao tem nada com aquilo.
    and public.can_access_conversation(message.conversation_id)
  on conflict (message_id, profile_id) do nothing;

  get diagnostics marked = row_count;
  return marked;
end;
$$;

revoke all on function public.delete_messages_for_me(uuid[]) from public, anon;
grant execute on function public.delete_messages_for_me(uuid[]) to authenticated;

create or replace function public.delete_messages_for_everyone(
  message_ids_value uuid[]
)
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  clean_ids uuid[];
  deletable uuid[];
  marked integer;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select array_agg(distinct message_id)
  into clean_ids
  from unnest(coalesce(message_ids_value, array[]::uuid[]))
    as ids(message_id)
  where message_id is not null;

  clean_ids := coalesce(clean_ids, array[]::uuid[]);

  if cardinality(clean_ids) = 0 then
    return 0;
  end if;

  if cardinality(clean_ids) > 100 then
    raise exception 'Too many messages';
  end if;

  -- As quatro condicoes que definem quem pode apagar o que.
  select array_agg(message.id)
  into deletable
  from public.messages message
  where message.id = any(clean_ids)
    -- 1. So o AUTOR apaga para todos.
    and message.sender_id = auth.uid()
    -- 2. Dentro da janela.
    and message.created_at >= now() - interval '60 hours'
    -- 3. Mensagem de sistema (aceite de caso, sugestao de advogado) e registro
    --    do fluxo, nao conversa: apagar deixaria cartao vazio na tela.
    and message.sender_type in ('client', 'lawyer')
    -- 4. Nao repete o que ja foi apagado.
    and message.deleted_for_all_at is null;

  if deletable is null then
    return 0;
  end if;

  -- Sem a linha de message_attachments a policy do Storage para de liberar o
  -- arquivo: e o que torna a foto apagada de fato inacessivel, e nao apenas
  -- escondida.
  delete from public.message_attachments
  where message_id = any(deletable);

  update public.messages
  set body = '',
      metadata = '{}'::jsonb,
      deleted_for_all_at = now()
  where id = any(deletable);

  get diagnostics marked = row_count;
  return marked;
end;
$$;

revoke all on function public.delete_messages_for_everyone(uuid[])
from public, anon;
grant execute on function public.delete_messages_for_everyone(uuid[])
to authenticated;

-- ---------------------------------------------------------------------------
-- 5. O contador de nao lidas ignora o que ja nao aparece.
--    Corpo VERBATIM do que esta no banco; muda so o filtro do subselect.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fetch_conversations_for_current_user(scope_value text, law_firm_id_value uuid DEFAULT NULL::uuid)
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
        and unread.deleted_for_all_at is null
        and not exists (
          select 1
          from public.message_deletions hidden
          where hidden.message_id = unread.id
            and hidden.profile_id = auth.uid()
        )
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
