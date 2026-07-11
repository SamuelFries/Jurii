-- Keeps profile chat drafts out of inboxes until a real message exists.
--
-- Run after patch_018. Opening a professional or office profile can create a
-- technical conversation draft so the chat screen has an id, but inboxes should
-- only show conversations after at least one message has been sent.

create or replace function public.start_or_get_law_firm_conversation(
  law_firm_id_value uuid,
  initial_message_value text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  firm_row public.law_firms%rowtype;
  conversation_id_value uuid;
  clean_message text;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  select *
  into firm_row
  from public.law_firms
  where id = law_firm_id_value
    and is_active = true;

  if not found then
    raise exception 'Law firm not found';
  end if;

  select id
  into conversation_id_value
  from public.conversations
  where client_id = auth.uid()
    and law_firm_id = law_firm_id_value
    and lawyer_id is null
    and case_id is null
    and type = 'client_firm'
  order by updated_at desc
  limit 1;

  if conversation_id_value is null then
    insert into public.conversations (
      type,
      client_id,
      law_firm_id,
      title,
      specialty
    )
    values (
      'client_firm',
      auth.uid(),
      law_firm_id_value,
      firm_row.name,
      firm_row.specialty
    )
    returning id into conversation_id_value;
  end if;

  clean_message := nullif(trim(coalesce(initial_message_value, '')), '');

  if clean_message is not null then
    insert into public.messages (
      conversation_id,
      sender_id,
      sender_type,
      body
    )
    values (
      conversation_id_value,
      auth.uid(),
      'client',
      clean_message
    );
  end if;

  return conversation_id_value;
end;
$$;

create or replace function public.start_or_get_lawyer_conversation(
  lawyer_profile_id_value uuid,
  initial_message_value text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  lawyer_row public.lawyer_profiles%rowtype;
  profile_row public.profiles%rowtype;
  conversation_id_value uuid;
  clean_message text;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  select *
  into lawyer_row
  from public.lawyer_profiles
  where id = lawyer_profile_id_value;

  if not found then
    raise exception 'Lawyer profile not found';
  end if;

  select *
  into profile_row
  from public.profiles
  where id = lawyer_profile_id_value
    and lawyer_status = 'approved';

  if not found then
    raise exception 'Lawyer profile is not approved';
  end if;

  select id
  into conversation_id_value
  from public.conversations
  where client_id = auth.uid()
    and lawyer_id = lawyer_profile_id_value
    and case_id is null
    and type = 'client_firm'
  order by updated_at desc
  limit 1;

  if conversation_id_value is null then
    insert into public.conversations (
      type,
      client_id,
      lawyer_id,
      title,
      specialty
    )
    values (
      'client_firm',
      auth.uid(),
      lawyer_profile_id_value,
      profile_row.full_name,
      lawyer_row.primary_area
    )
    returning id into conversation_id_value;
  end if;

  clean_message := nullif(trim(coalesce(initial_message_value, '')), '');

  if clean_message is not null then
    insert into public.messages (
      conversation_id,
      sender_id,
      sender_type,
      body
    )
    values (
      conversation_id_value,
      auth.uid(),
      'client',
      clean_message
    );
  end if;

  return conversation_id_value;
end;
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
          and c.lawyer_id = auth.uid()
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
        coalesce(client_profile.full_name, 'Cliente')
      when scope_value = 'client' and c.law_firm_id is not null then
        coalesce(lf.name, c.title)
      when scope_value = 'client' and c.lawyer_id is not null then
        coalesce(lawyer_profile.full_name, c.title)
      else c.title
    end as title,
    case
      when scope_value in ('lawyer', 'firmClient') then
        coalesce(client_profile.initials, 'CL')
      when scope_value = 'client' and c.law_firm_id is not null then
        coalesce(lf.initials, 'JE')
      when scope_value = 'client' and c.lawyer_id is not null then
        coalesce(lawyer_profile.initials, 'AJ')
      else upper(left(trim(c.title), 2))
    end as initials,
    coalesce(c.specialty, 'Atendimento jurídico') as specialty,
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

revoke all on function public.start_or_get_law_firm_conversation(uuid, text)
from public, anon;

revoke all on function public.start_or_get_lawyer_conversation(uuid, text)
from public, anon;

revoke all on function public.fetch_conversations_for_current_user(text, uuid)
from public, anon, authenticated;

grant execute on function public.start_or_get_law_firm_conversation(uuid, text)
to authenticated;

grant execute on function public.start_or_get_lawyer_conversation(uuid, text)
to authenticated;

grant execute on function public.fetch_conversations_for_current_user(text, uuid)
to authenticated;
