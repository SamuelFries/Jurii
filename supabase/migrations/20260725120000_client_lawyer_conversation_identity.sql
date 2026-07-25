-- Conversa direta com advogado mostra o ADVOGADO, nao o escritorio dele
--
-- Bug reportado: cliente toca "Enviar mensagem" no perfil de um advogado
-- recomendado e o chat abre "do escritorio". A conversa criada estava CERTA
-- (lawyer_id do advogado), mas a conversa cliente<->advogado tambem carrega o
-- law_firm_id do vinculo (de proposito: e o que faz a conversa aparecer no
-- painel do escritorio) — e os CASEs de titulo/iniciais/avatar das RPCs de
-- conversa testavam law_firm_id ANTES de lawyer_id para o cliente. Resultado:
-- nome, iniciais e logo do ESCRITORIO no cabecalho de uma conversa que e com
-- o advogado.
--
-- Fix: para o cliente, lawyer_id tem precedencia — conversa com advogado
-- mostra o advogado; escritorio so quando NAO ha advogado na conversa. Nada
-- muda para os escopos lawyer/firmClient (que mostram o cliente) nem para o
-- painel do escritorio (a conversa continua listada la).
--
-- Corpos extraidos VERBATIM das definicoes vigentes (20260718200000); apenas
-- a ordem dos WHENs do cliente foi invertida nos tres CASEs de cada funcao.

create or replace function public.fetch_conversation_for_current_user(
  conversation_id_value uuid
)
returns table (
  id uuid,
  type text,
  title text,
  initials text,
  avatar_url text,
  specialty text,
  last_message text,
  last_message_at timestamptz,
  law_firm_id uuid,
  client_id uuid,
  lawyer_id uuid
)
language sql
stable
security definer
set search_path = public
as $$
  select
    conversation.id,
    conversation.type::text,
    case
      when conversation.client_id = auth.uid()
           and conversation.lawyer_id is not null then
        public.profile_display_name(
          lawyer_profile.full_name,
          lawyer_profile.deleted_display_name,
          lawyer_profile.deleted_at
        )
      when conversation.client_id = auth.uid()
           and conversation.law_firm_id is not null then
        coalesce(firm.name, conversation.title)
      when conversation.client_id = auth.uid() then conversation.title
      else public.profile_display_name(
        client_profile.full_name,
        client_profile.deleted_display_name,
        client_profile.deleted_at
      )
    end as title,
    case
      when conversation.client_id = auth.uid()
           and conversation.lawyer_id is not null then
        coalesce(lawyer_profile.initials, 'AJ')
      when conversation.client_id = auth.uid()
           and conversation.law_firm_id is not null then
        coalesce(firm.initials, 'JE')
      when conversation.client_id = auth.uid() then
        upper(left(trim(conversation.title), 2))
      else coalesce(client_profile.initials, 'CL')
    end as initials,
    case
      when conversation.client_id = auth.uid()
           and conversation.lawyer_id is not null then
        public.safe_profile_avatar_url(
          lawyer_profile.id,
          lawyer_profile.avatar_url
        )
      when conversation.client_id = auth.uid()
           and conversation.law_firm_id is not null then firm.avatar_url
      when conversation.client_id = auth.uid() then null::text
      else public.safe_profile_avatar_url(
        client_profile.id,
        client_profile.avatar_url
      )
    end as avatar_url,
    coalesce(conversation.specialty, 'Atendimento jurídico') as specialty,
    coalesce(conversation.last_message, 'Nova conversa') as last_message,
    conversation.last_message_at,
    conversation.law_firm_id,
    conversation.client_id,
    conversation.lawyer_id
  from public.conversations conversation
  left join public.profiles client_profile
    on client_profile.id = conversation.client_id
  left join public.law_firms firm
    on firm.id = conversation.law_firm_id
  left join public.profiles lawyer_profile
    on lawyer_profile.id = conversation.lawyer_id
  where conversation.id = conversation_id_value
    and (
      conversation.client_id = auth.uid()
      or conversation.lawyer_id = auth.uid()
      or exists (
        select 1
        from public.law_firm_members member
        where member.law_firm_id = conversation.law_firm_id
          and member.profile_id = auth.uid()
          and member.status = 'active'
      )
      or (
        conversation.case_id is not null
        and public.can_access_case(conversation.case_id)
      )
    )
  limit 1;
$$;

create or replace function public.fetch_conversations_for_current_user(
  scope_value text,
  law_firm_id_value uuid default null
)
returns table (
  id uuid,
  type text,
  title text,
  initials text,
  avatar_url text,
  specialty text,
  last_message text,
  last_message_at timestamptz,
  law_firm_id uuid,
  client_id uuid,
  lawyer_id uuid
)
language sql
stable
security definer
set search_path = public
as $$
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
    coalesce(conversation.specialty, 'Atendimento jurídico') as specialty,
    coalesce(conversation.last_message, 'Nova conversa') as last_message,
    conversation.last_message_at,
    conversation.law_firm_id,
    conversation.client_id,
    conversation.lawyer_id
  from scoped_conversations conversation
  left join public.profiles client_profile
    on client_profile.id = conversation.client_id
  left join public.law_firms firm
    on firm.id = conversation.law_firm_id
  left join public.profiles lawyer_profile
    on lawyer_profile.id = conversation.lawyer_id
  order by conversation.last_message_at desc nulls last,
    conversation.updated_at desc;
$$;

notify pgrst, 'reload schema';
