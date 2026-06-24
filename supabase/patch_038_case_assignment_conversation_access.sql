-- Makes office case assignment surface the existing office chat to the lawyer.
--
-- Run after patch_037. When an office assigns a case that came from an office
-- conversation, the assigned lawyer should see that same chat in the lawyer
-- message flow, and the chat should show a system assignment event.

create or replace function public.assign_law_firm_case(
  law_firm_id_value uuid,
  case_id_value uuid,
  lawyer_profile_id_value uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  case_row public.legal_cases%rowtype;
  old_lawyer_id uuid;
  target_lawyer_id uuid;
  target_lawyer_name text;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  if not public.is_active_law_firm_case_manager(law_firm_id_value) then
    raise exception 'Only office case managers can assign cases';
  end if;

  select *
  into case_row
  from public.legal_cases
  where id = case_id_value
  for update;

  if not found then
    raise exception 'Case not found';
  end if;

  if not (
    case_row.law_firm_id = law_firm_id_value
    or exists (
      select 1
      from public.law_firm_members lfm
      where lfm.law_firm_id = law_firm_id_value
        and lfm.profile_id = case_row.assigned_lawyer_id
        and lfm.status = 'active'
    )
    or exists (
      select 1
      from public.case_participants cp
      join public.law_firm_members lfm
        on lfm.profile_id = cp.profile_id
      where cp.case_id = case_row.id
        and cp.role in ('lawyer', 'firm_member')
        and lfm.law_firm_id = law_firm_id_value
        and lfm.status = 'active'
    )
  ) then
    raise exception 'Case does not belong to this office';
  end if;

  select
    coalesce(lfm.lawyer_id, lfm.profile_id),
    coalesce(p.full_name, 'Advogado')
  into target_lawyer_id, target_lawyer_name
  from public.law_firm_members lfm
  join public.lawyer_profiles lp
    on lp.id = coalesce(lfm.lawyer_id, lfm.profile_id)
  left join public.profiles p
    on p.id = coalesce(lfm.lawyer_id, lfm.profile_id)
  where lfm.law_firm_id = law_firm_id_value
    and lfm.profile_id = lawyer_profile_id_value
    and lfm.status = 'active'
    and 'lawyer' = any(lfm.roles)
    and coalesce(lfm.lawyer_invite_status, 'active'::public.law_firm_member_status)
      = 'active'
  limit 1;

  if target_lawyer_id is null then
    raise exception 'Target member must be an active lawyer';
  end if;

  old_lawyer_id := case_row.assigned_lawyer_id;

  update public.legal_cases
  set
    law_firm_id = coalesce(law_firm_id, law_firm_id_value),
    assigned_lawyer_id = target_lawyer_id,
    last_update_label = 'Caso atribuído',
    updated_at = now()
  where id = case_id_value;

  if old_lawyer_id is not null and old_lawyer_id <> target_lawyer_id then
    delete from public.case_participants
    where case_id = case_id_value
      and profile_id = old_lawyer_id
      and role = 'lawyer';
  end if;

  insert into public.case_participants (case_id, profile_id, role)
  values (case_id_value, target_lawyer_id, 'lawyer')
  on conflict (case_id, profile_id) do update
  set role = 'lawyer';

  update public.conversations
  set
    law_firm_id = coalesce(law_firm_id, law_firm_id_value),
    lawyer_id = target_lawyer_id,
    updated_at = now()
  where case_id = case_id_value
    and type <> 'firm_internal';

  if old_lawyer_id is distinct from target_lawyer_id then
    insert into public.messages (
      conversation_id,
      sender_id,
      sender_type,
      body,
      metadata
    )
    select
      c.id,
      auth.uid(),
      'system',
      'Caso atribuído a ' || target_lawyer_name || '.',
      jsonb_build_object(
        'type', 'case_assignment',
        'case_id', case_id_value,
        'lawyer_id', target_lawyer_id,
        'law_firm_id', law_firm_id_value
      )
    from public.conversations c
    where c.case_id = case_id_value
      and c.type <> 'firm_internal';
  end if;

  return target_lawyer_id;
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
      when scope_value = 'client' and c.law_firm_id is not null then
        coalesce(lf.name, c.title)
      when scope_value = 'client' and c.lawyer_id is not null then
        public.profile_display_name(
          lawyer_profile.full_name,
          lawyer_profile.deleted_display_name,
          lawyer_profile.deleted_at
        )
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

revoke all on function public.assign_law_firm_case(uuid, uuid, uuid)
from public, anon, authenticated;

revoke all on function public.fetch_conversations_for_current_user(text, uuid)
from public, anon, authenticated;

grant execute on function public.assign_law_firm_case(uuid, uuid, uuid)
to authenticated;

grant execute on function public.fetch_conversations_for_current_user(text, uuid)
to authenticated;

select pg_notify('pgrst', 'reload schema');
