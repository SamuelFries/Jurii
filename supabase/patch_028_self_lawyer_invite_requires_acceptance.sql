-- Requires explicit lawyer acceptance even when an office owner/admin invites
-- their own verified lawyer profile by OAB.
--
-- Run after patch_027. This keeps the office leadership membership active,
-- but tracks the lawyer association as a separate pending invite until the
-- lawyer accepts it from the notification bell.

alter table public.law_firm_members
add column if not exists lawyer_invite_status public.law_firm_member_status;

alter table public.law_firm_members
add column if not exists pending_lawyer_id uuid references public.lawyer_profiles(id) on delete set null;

create index if not exists law_firm_members_pending_lawyer_idx
on public.law_firm_members(pending_lawyer_id)
where pending_lawyer_id is not null;

update public.law_firm_members
set lawyer_invite_status = case
  when status = 'invited' then 'invited'::public.law_firm_member_status
  when status = 'disabled' then 'disabled'::public.law_firm_member_status
  when lawyer_id is not null then 'active'::public.law_firm_member_status
  else lawyer_invite_status
end
where lawyer_invite_status is null;

create or replace function public.invite_verified_lawyer_to_law_firm(
  law_firm_id_value uuid,
  oab_state_value text,
  oab_number_value text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  target_verification public.lawyer_verifications%rowtype;
  target_profile public.profiles%rowtype;
  existing_member public.law_firm_members%rowtype;
  firm_name_value text;
  normalized_oab_state text;
  normalized_oab_number text;
  membership_id_value uuid;
  existing_is_manager boolean;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  if not public.is_active_law_firm_manager(law_firm_id_value) then
    raise exception 'Only active office owners and admins can invite lawyers';
  end if;

  normalized_oab_state := upper(trim(coalesce(oab_state_value, '')));
  normalized_oab_number := regexp_replace(
    upper(coalesce(oab_number_value, '')),
    '[^A-Z0-9]',
    '',
    'g'
  );

  if length(normalized_oab_state) <> 2 or normalized_oab_number = '' then
    raise exception 'Invalid OAB';
  end if;

  select *
  into target_verification
  from public.lawyer_verifications lv
  where lv.status = 'approved'
    and upper(trim(lv.oab_state)) = normalized_oab_state
    and regexp_replace(upper(coalesce(lv.oab_number, '')), '[^A-Z0-9]', '', 'g')
      = normalized_oab_number
  order by lv.reviewed_at desc nulls last, lv.submitted_at desc
  limit 1;

  if not found then
    raise exception 'Lawyer not found or not approved for this OAB';
  end if;

  select *
  into target_profile
  from public.profiles
  where id = target_verification.user_id;

  if not found then
    raise exception 'Lawyer profile not found';
  end if;

  update public.profiles
  set lawyer_status = 'approved'
  where id = target_verification.user_id;

  insert into public.lawyer_profiles (
    id,
    oab_number,
    oab_state,
    primary_area,
    approved_at
  )
  values (
    target_verification.user_id,
    target_verification.oab_number,
    target_verification.oab_state,
    target_verification.practice_area,
    coalesce(target_verification.reviewed_at, now())
  )
  on conflict (id) do update
  set
    oab_number = excluded.oab_number,
    oab_state = excluded.oab_state,
    primary_area = excluded.primary_area,
    approved_at = coalesce(public.lawyer_profiles.approved_at, excluded.approved_at);

  select *
  into existing_member
  from public.law_firm_members
  where law_firm_id = law_firm_id_value
    and (
      profile_id = target_verification.user_id
      or lawyer_id = target_verification.user_id
      or pending_lawyer_id = target_verification.user_id
    )
  limit 1;

  if found
      and existing_member.lawyer_id = target_verification.user_id
      and existing_member.lawyer_invite_status = 'active' then
    raise exception 'Lawyer already active in this office';
  end if;

  if found
      and existing_member.pending_lawyer_id = target_verification.user_id
      and existing_member.lawyer_invite_status = 'invited' then
    raise exception 'Lawyer invite already pending';
  end if;

  if not found then
    insert into public.law_firm_members (
      law_firm_id,
      lawyer_id,
      profile_id,
      role,
      member_role,
      status,
      lawyer_invite_status,
      pending_lawyer_id
    )
    values (
      law_firm_id_value,
      target_verification.user_id,
      target_verification.user_id,
      'lawyer',
      'lawyer',
      'invited',
      'invited',
      null
    )
    returning id into membership_id_value;
  else
    existing_is_manager :=
      existing_member.status = 'active'
      and existing_member.member_role in ('owner', 'admin', 'secretary');

    update public.law_firm_members
    set
      profile_id = target_verification.user_id,
      lawyer_id = case
        when existing_is_manager then lawyer_id
        else target_verification.user_id
      end,
      pending_lawyer_id = case
        when existing_is_manager then target_verification.user_id
        else null
      end,
      lawyer_invite_status = 'invited',
      role = case
        when existing_is_manager then role
        else 'lawyer'
      end,
      member_role = case
        when existing_is_manager then member_role
        else 'lawyer'::public.law_firm_member_role
      end,
      status = case
        when existing_is_manager then status
        else 'invited'::public.law_firm_member_status
      end
    where id = existing_member.id
    returning id into membership_id_value;
  end if;

  select name
  into firm_name_value
  from public.law_firms
  where id = law_firm_id_value;

  insert into public.notifications (
    recipient_profile_id,
    actor_profile_id,
    law_firm_id,
    type,
    title,
    body,
    metadata
  )
  values (
    target_verification.user_id,
    auth.uid(),
    law_firm_id_value,
    'team_invite',
    'Convite para escritório',
    coalesce(firm_name_value, 'Um escritório') ||
      ' convidou você para integrar a equipe.',
    jsonb_build_object(
      'membership_id', membership_id_value,
      'invite_status', null,
      'lawyer_invite_status', 'invited'
    )
  );

  return membership_id_value;
end;
$$;

create or replace function public.respond_to_law_firm_invite(
  membership_id_value uuid,
  accepted_value boolean
)
returns public.law_firm_member_status
language plpgsql
security definer
set search_path = public
as $$
declare
  membership_row public.law_firm_members%rowtype;
  next_status public.law_firm_member_status;
  is_manager_membership boolean;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  select *
  into membership_row
  from public.law_firm_members
  where id = membership_id_value
  for update;

  if not found then
    raise exception 'Invite not found';
  end if;

  if membership_row.profile_id <> auth.uid() then
    raise exception 'Only the invited lawyer can respond to this invite';
  end if;

  if membership_row.status <> 'invited'
      and membership_row.lawyer_invite_status <> 'invited' then
    raise exception 'Invite is no longer pending';
  end if;

  is_manager_membership :=
    membership_row.status = 'active'
    and membership_row.member_role in ('owner', 'admin', 'secretary');

  next_status := case
    when accepted_value then 'active'::public.law_firm_member_status
    else 'disabled'::public.law_firm_member_status
  end;

  if accepted_value then
    update public.law_firm_members
    set
      status = case
        when is_manager_membership then status
        else 'active'::public.law_firm_member_status
      end,
      lawyer_id = coalesce(pending_lawyer_id, lawyer_id, profile_id),
      pending_lawyer_id = null,
      lawyer_invite_status = 'active'
    where id = membership_id_value;
  else
    update public.law_firm_members
    set
      status = case
        when is_manager_membership then status
        else 'disabled'::public.law_firm_member_status
      end,
      lawyer_id = case
        when is_manager_membership
             and lawyer_invite_status = 'invited'
             and pending_lawyer_id is not null then null
        else lawyer_id
      end,
      pending_lawyer_id = null,
      lawyer_invite_status = 'disabled'
    where id = membership_id_value;
  end if;

  update public.notifications
  set
    read_at = coalesce(read_at, now()),
    metadata = metadata ||
      jsonb_build_object(
        'membership_id', membership_id_value,
        'invite_status', case when accepted_value then 'accepted' else 'declined' end,
        'lawyer_invite_status', case when accepted_value then 'active' else 'disabled' end
      )
  where recipient_profile_id = auth.uid()
    and type = 'team_invite'
    and metadata ->> 'membership_id' = membership_id_value::text;

  return next_status;
end;
$$;

with frozen_self_invites as (
  select
    n.id as notification_id,
    n.recipient_profile_id,
    (n.metadata ->> 'membership_id')::uuid as membership_id
  from public.notifications n
  join public.law_firm_members lfm
    on lfm.id = (n.metadata ->> 'membership_id')::uuid
  where n.type = 'team_invite'
    and n.read_at is null
    and n.actor_profile_id = n.recipient_profile_id
    and n.metadata ->> 'membership_id' is not null
    and n.metadata ->> 'invite_status' is null
    and lfm.profile_id = n.recipient_profile_id
    and lfm.status = 'active'
    and lfm.member_role in ('owner', 'admin', 'secretary')
)
update public.law_firm_members lfm
set
  pending_lawyer_id = frozen_self_invites.recipient_profile_id,
  lawyer_invite_status = 'invited',
  lawyer_id = case
    when lfm.lawyer_id = frozen_self_invites.recipient_profile_id then null
    else lfm.lawyer_id
  end
from frozen_self_invites
where lfm.id = frozen_self_invites.membership_id;

with frozen_self_invites as (
  select n.id
  from public.notifications n
  join public.law_firm_members lfm
    on lfm.id = (n.metadata ->> 'membership_id')::uuid
  where n.type = 'team_invite'
    and n.read_at is null
    and n.actor_profile_id = n.recipient_profile_id
    and n.metadata ->> 'membership_id' is not null
    and n.metadata ->> 'invite_status' is null
    and lfm.profile_id = n.recipient_profile_id
    and lfm.lawyer_invite_status = 'invited'
)
update public.notifications n
set metadata = n.metadata || jsonb_build_object('lawyer_invite_status', 'invited')
from frozen_self_invites
where n.id = frozen_self_invites.id;

revoke all on function public.invite_verified_lawyer_to_law_firm(uuid, text, text)
from public, anon;

grant execute on function public.invite_verified_lawyer_to_law_firm(uuid, text, text)
to authenticated;

revoke all on function public.respond_to_law_firm_invite(uuid, boolean)
from public, anon;

grant execute on function public.respond_to_law_firm_invite(uuid, boolean)
to authenticated;

notify pgrst, 'reload schema';
