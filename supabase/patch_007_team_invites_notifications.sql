-- Adds office team invitations by OAB and app notifications.
--
-- Run after patch_004, patch_005 and patch_006.

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_profile_id uuid not null references public.profiles(id) on delete cascade,
  actor_profile_id uuid references public.profiles(id) on delete set null,
  law_firm_id uuid references public.law_firms(id) on delete cascade,
  type text not null default 'system',
  title text not null,
  body text not null,
  metadata jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists notifications_recipient_created_idx
on public.notifications(recipient_profile_id, created_at desc);

create index if not exists notifications_recipient_unread_idx
on public.notifications(recipient_profile_id)
where read_at is null;

alter table public.notifications enable row level security;

drop policy if exists "notifications_select_own" on public.notifications;
create policy "notifications_select_own"
on public.notifications for select
to authenticated
using (recipient_profile_id = auth.uid());

drop policy if exists "notifications_update_own" on public.notifications;
create policy "notifications_update_own"
on public.notifications for update
to authenticated
using (recipient_profile_id = auth.uid())
with check (recipient_profile_id = auth.uid());

grant select, update on public.notifications to authenticated;

update public.law_firm_members lfm
set lawyer_id = lfm.profile_id
where lfm.lawyer_id is null
  and lfm.profile_id is not null
  and lfm.member_role in ('owner', 'admin')
  and exists (
    select 1
    from public.lawyer_profiles lp
    where lp.id = lfm.profile_id
  );

create or replace function public.can_select_profile(profile_id_value uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    profile_id_value = auth.uid()
    or exists (
      select 1
      from public.legal_cases lc
      where (
        lc.client_id = auth.uid()
        and lc.assigned_lawyer_id = profile_id_value
      )
      or (
        lc.assigned_lawyer_id = auth.uid()
        and lc.client_id = profile_id_value
      )
    )
    or exists (
      select 1
      from public.case_participants cp
      where cp.profile_id = profile_id_value
        and public.can_access_case(cp.case_id)
    )
    or exists (
      select 1
      from public.conversations c
      where (
        c.client_id = auth.uid()
        and c.lawyer_id = profile_id_value
      )
      or (
        c.lawyer_id = auth.uid()
        and c.client_id = profile_id_value
      )
    )
    or exists (
      select 1
      from public.law_firm_members viewer
      join public.law_firm_members target
        on target.law_firm_id = viewer.law_firm_id
      where viewer.profile_id = auth.uid()
        and viewer.status in ('active', 'invited')
        and target.profile_id = profile_id_value
        and target.status in ('active', 'invited')
    );
$$;

create or replace function public.is_active_law_firm_manager(
  law_firm_id_value uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.law_firm_members lfm
    where lfm.law_firm_id = law_firm_id_value
      and lfm.profile_id = auth.uid()
      and lfm.status = 'active'
      and lfm.member_role in ('owner', 'admin')
  );
$$;

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
  firm_name_value text;
  normalized_oab_state text;
  normalized_oab_number text;
  membership_id_value uuid;
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

  select id
  into membership_id_value
  from public.law_firm_members
  where law_firm_id = law_firm_id_value
    and (
      profile_id = target_verification.user_id
      or lawyer_id = target_verification.user_id
    )
  limit 1;

  if membership_id_value is null then
    insert into public.law_firm_members (
      law_firm_id,
      lawyer_id,
      profile_id,
      role,
      member_role,
      status
    )
    values (
      law_firm_id_value,
      target_verification.user_id,
      target_verification.user_id,
      'lawyer',
      'lawyer',
      'invited'
    )
    returning id into membership_id_value;
  else
    update public.law_firm_members
    set
      lawyer_id = target_verification.user_id,
      profile_id = target_verification.user_id,
      role = case
        when member_role in ('owner', 'admin') then role
        else 'lawyer'
      end,
      member_role = case
        when member_role in ('owner', 'admin') then member_role
        else 'lawyer'::public.law_firm_member_role
      end,
      status = case
        when status = 'active' then 'active'::public.law_firm_member_status
        else 'invited'::public.law_firm_member_status
      end
    where id = membership_id_value;
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
    jsonb_build_object('membership_id', membership_id_value)
  );

  return membership_id_value;
end;
$$;

revoke all on function public.invite_verified_lawyer_to_law_firm(uuid, text, text)
from public, anon;

grant execute on function public.invite_verified_lawyer_to_law_firm(uuid, text, text)
to authenticated;

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
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  select *
  into membership_row
  from public.law_firm_members
  where id = membership_id_value;

  if not found then
    raise exception 'Invite not found';
  end if;

  if membership_row.profile_id <> auth.uid() then
    raise exception 'Only the invited lawyer can respond to this invite';
  end if;

  if membership_row.status <> 'invited' then
    raise exception 'Invite is no longer pending';
  end if;

  next_status := case
    when accepted_value then 'active'::public.law_firm_member_status
    else 'disabled'::public.law_firm_member_status
  end;

  update public.law_firm_members
  set status = next_status
  where id = membership_id_value;

  update public.notifications
  set
    read_at = coalesce(read_at, now()),
    metadata = metadata ||
      jsonb_build_object(
        'membership_id', membership_id_value,
        'invite_status', case when accepted_value then 'accepted' else 'declined' end
      )
  where recipient_profile_id = auth.uid()
    and type = 'team_invite'
    and metadata ->> 'membership_id' = membership_id_value::text;

  return next_status;
end;
$$;

revoke all on function public.respond_to_law_firm_invite(uuid, boolean)
from public, anon;

grant execute on function public.respond_to_law_firm_invite(uuid, boolean)
to authenticated;
