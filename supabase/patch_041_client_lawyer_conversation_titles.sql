-- Shows the lawyer name to clients when a conversation has a responsible lawyer.
--
-- Run after patch_040. This keeps the existing conversation rows and only
-- changes the display title/initials returned by the conversation RPCs.

create or replace function public.fetch_conversation_for_current_user(
  conversation_id_value uuid
)
returns table (
  id uuid,
  type text,
  title text,
  initials text,
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
    c.id,
    c.type::text,
    case
      when c.client_id = auth.uid() and c.lawyer_id is not null then
        public.profile_display_name(
          lawyer_profile.full_name,
          lawyer_profile.deleted_display_name,
          lawyer_profile.deleted_at
        )
      when c.client_id = auth.uid() and c.law_firm_id is not null then
        coalesce(lf.name, c.title)
      when c.client_id = auth.uid() then
        c.title
      else
        public.profile_display_name(
          client_profile.full_name,
          client_profile.deleted_display_name,
          client_profile.deleted_at
        )
    end as title,
    case
      when c.client_id = auth.uid() and c.lawyer_id is not null then
        coalesce(lawyer_profile.initials, 'AJ')
      when c.client_id = auth.uid() and c.law_firm_id is not null then
        coalesce(lf.initials, 'JE')
      when c.client_id = auth.uid() then
        upper(left(trim(c.title), 2))
      else
        coalesce(client_profile.initials, 'CL')
    end as initials,
    coalesce(c.specialty, 'Atendimento juridico') as specialty,
    coalesce(c.last_message, 'Nova conversa') as last_message,
    c.last_message_at,
    c.law_firm_id,
    c.client_id,
    c.lawyer_id
  from public.conversations c
  left join public.profiles client_profile
    on client_profile.id = c.client_id
  left join public.law_firms lf
    on lf.id = c.law_firm_id
  left join public.profiles lawyer_profile
    on lawyer_profile.id = c.lawyer_id
  where c.id = conversation_id_value
    and (
      c.client_id = auth.uid()
      or c.lawyer_id = auth.uid()
      or exists (
        select 1
        from public.law_firm_members lfm
        where lfm.law_firm_id = c.law_firm_id
          and lfm.profile_id = auth.uid()
          and lfm.status = 'active'
      )
      or (
        c.case_id is not null
        and public.can_access_case(c.case_id)
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
    select c.*
    from public.conversations c
    where auth.uid() is not null
      and exists (
        select 1
        from public.messages m
        where m.conversation_id = c.id
      )
      and (
        (
          scope_value = 'client'
          and c.client_id = auth.uid()
        )
        or (
          scope_value = 'lawyer'
          and c.type <> 'firm_internal'
          and (
            c.lawyer_id = auth.uid()
            or (
              c.case_id is not null
              and public.can_access_case(c.case_id)
            )
          )
        )
        or (
          scope_value = 'firmClient'
          and law_firm_id_value is not null
          and c.law_firm_id = law_firm_id_value
          and c.type <> 'firm_internal'
          and exists (
            select 1
            from public.law_firm_members lfm
            where lfm.law_firm_id = law_firm_id_value
              and lfm.profile_id = auth.uid()
              and lfm.status = 'active'
          )
        )
        or (
          scope_value = 'firmTeam'
          and law_firm_id_value is not null
          and c.law_firm_id = law_firm_id_value
          and c.type = 'firm_internal'
          and exists (
            select 1
            from public.law_firm_members lfm
            where lfm.law_firm_id = law_firm_id_value
              and lfm.profile_id = auth.uid()
              and lfm.status = 'active'
          )
        )
      )
  )
  select
    c.id,
    c.type::text,
    case
      when scope_value in ('lawyer', 'firmClient') then
        public.profile_display_name(
          client_profile.full_name,
          client_profile.deleted_display_name,
          client_profile.deleted_at
        )
      when scope_value = 'client' and c.lawyer_id is not null then
        public.profile_display_name(
          lawyer_profile.full_name,
          lawyer_profile.deleted_display_name,
          lawyer_profile.deleted_at
        )
      when scope_value = 'client' and c.law_firm_id is not null then
        coalesce(lf.name, c.title)
      else c.title
    end as title,
    case
      when scope_value in ('lawyer', 'firmClient') then
        coalesce(client_profile.initials, 'CL')
      when scope_value = 'client' and c.lawyer_id is not null then
        coalesce(lawyer_profile.initials, 'AJ')
      when scope_value = 'client' and c.law_firm_id is not null then
        coalesce(lf.initials, 'JE')
      else upper(left(trim(c.title), 2))
    end as initials,
    coalesce(c.specialty, 'Atendimento juridico') as specialty,
    coalesce(c.last_message, 'Nova conversa') as last_message,
    c.last_message_at,
    c.law_firm_id,
    c.client_id,
    c.lawyer_id
  from scoped_conversations c
  left join public.profiles client_profile
    on client_profile.id = c.client_id
  left join public.law_firms lf
    on lf.id = c.law_firm_id
  left join public.profiles lawyer_profile
    on lawyer_profile.id = c.lawyer_id
  order by c.last_message_at desc nulls last, c.updated_at desc;
$$;

revoke all on function public.fetch_conversation_for_current_user(uuid)
from public, anon, authenticated;

revoke all on function public.fetch_conversations_for_current_user(text, uuid)
from public, anon, authenticated;

grant execute on function public.fetch_conversation_for_current_user(uuid)
to authenticated;

grant execute on function public.fetch_conversations_for_current_user(text, uuid)
to authenticated;

select pg_notify('pgrst', 'reload schema');
