-- Links client conversations started from an office lawyer back to the office.
--
-- Run after patch_035. Without this, conversations opened from a lawyer profile
-- can stay only on lawyer_id, so the office inbox and office metrics do not see
-- them.

create index if not exists conversations_law_firm_idx
on public.conversations(law_firm_id);

create or replace function public.can_access_conversation(
  conversation_id_value uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.conversations c
    where c.id = conversation_id_value
      and (
        c.client_id = auth.uid()
        or c.lawyer_id = auth.uid()
        or (
          c.law_firm_id is not null
          and exists (
            select 1
            from public.law_firm_members lfm
            where lfm.law_firm_id = c.law_firm_id
              and lfm.profile_id = auth.uid()
              and lfm.status = 'active'
          )
        )
        or (
          c.law_firm_id is null
          and c.lawyer_id is not null
          and exists (
            select 1
            from public.law_firm_members lfm
            where lfm.profile_id = auth.uid()
              and lfm.status = 'active'
              and 'lawyer' = any(lfm.roles)
              and coalesce(lfm.lawyer_id, lfm.profile_id) = c.lawyer_id
              and coalesce(
                lfm.lawyer_invite_status,
                'active'::public.law_firm_member_status
              ) = 'active'
              and c.created_at >= coalesce(lfm.joined_at, lfm.created_at, c.created_at)
          )
        )
        or (
          c.case_id is not null
          and public.can_access_case(c.case_id)
        )
      )
  );
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
  firm_id_value uuid;
  firm_joined_at_value timestamptz;
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

  select
    lfm.law_firm_id,
    coalesce(lfm.joined_at, lfm.created_at, now())
  into firm_id_value, firm_joined_at_value
  from public.law_firm_members lfm
  where coalesce(lfm.lawyer_id, lfm.profile_id) = lawyer_profile_id_value
    and lfm.status = 'active'
    and 'lawyer' = any(lfm.roles)
    and coalesce(
      lfm.lawyer_invite_status,
      'active'::public.law_firm_member_status
    ) = 'active'
  order by
    case
      when 'owner' = any(lfm.roles) then 1
      when 'admin' = any(lfm.roles) then 2
      else 3
    end,
    coalesce(lfm.joined_at, lfm.created_at, now()) desc
  limit 1;

  select id
  into conversation_id_value
  from public.conversations
  where client_id = auth.uid()
    and lawyer_id = lawyer_profile_id_value
    and case_id is null
    and type = 'client_firm'
    and (
      (
        firm_id_value is not null
        and law_firm_id = firm_id_value
      )
      or (
        firm_id_value is not null
        and law_firm_id is null
        and created_at >= firm_joined_at_value
      )
      or (
        firm_id_value is null
        and law_firm_id is null
      )
    )
  order by
    case when law_firm_id = firm_id_value then 0 else 1 end,
    updated_at desc
  limit 1;

  if conversation_id_value is null then
    insert into public.conversations (
      type,
      client_id,
      lawyer_id,
      law_firm_id,
      title,
      specialty,
      last_message,
      last_message_at
    )
    values (
      'client_firm',
      auth.uid(),
      lawyer_profile_id_value,
      firm_id_value,
      profile_row.full_name,
      lawyer_row.primary_area,
      'Conversa iniciada.',
      now()
    )
    returning id into conversation_id_value;
  elsif firm_id_value is not null then
    update public.conversations
    set
      law_firm_id = firm_id_value,
      updated_at = now()
    where id = conversation_id_value
      and law_firm_id is null;
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

with active_lawyer_members as (
  select distinct on (coalesce(lfm.lawyer_id, lfm.profile_id))
    coalesce(lfm.lawyer_id, lfm.profile_id) as lawyer_profile_id,
    lfm.law_firm_id,
    coalesce(lfm.joined_at, lfm.created_at, now()) as member_since
  from public.law_firm_members lfm
  where coalesce(lfm.lawyer_id, lfm.profile_id) is not null
    and lfm.status = 'active'
    and 'lawyer' = any(lfm.roles)
    and coalesce(
      lfm.lawyer_invite_status,
      'active'::public.law_firm_member_status
    ) = 'active'
  order by
    coalesce(lfm.lawyer_id, lfm.profile_id),
    coalesce(lfm.joined_at, lfm.created_at, now()) desc
)
update public.conversations c
set
  law_firm_id = active_lawyer_members.law_firm_id,
  updated_at = now()
from active_lawyer_members
where c.lawyer_id = active_lawyer_members.lawyer_profile_id
  and c.law_firm_id is null
  and c.case_id is null
  and c.type = 'client_firm'
  and c.created_at >= active_lawyer_members.member_since;

revoke all on function public.can_access_conversation(uuid)
from public, anon;

revoke all on function public.start_or_get_lawyer_conversation(uuid, text)
from public, anon;

grant execute on function public.can_access_conversation(uuid)
to authenticated;

grant execute on function public.start_or_get_lawyer_conversation(uuid, text)
to authenticated;

select pg_notify('pgrst', 'reload schema');
