-- Adds multi-role office memberships and role-based office permissions.
--
-- Run after patch_029. This keeps the legacy role/member_role columns synced,
-- but makes roles text[] the source of truth for app permissions.

do $$
begin
  if exists (select 1 from pg_type where typname = 'law_firm_member_role') then
    execute 'alter type public.law_firm_member_role add value if not exists ''intern''';
  end if;
end $$;

alter table public.law_firm_members
add column if not exists roles text[] not null default array['lawyer']::text[];

create or replace function public.normalize_practice_areas(
  practice_areas_value text[]
)
returns text[]
language sql
immutable
set search_path = public
as $$
  select coalesce(array_agg(area order by first_ordinal), '{}'::text[])
  from (
    select area, min(ordinality) as first_ordinal
    from (
      select nullif(trim(area_value), '') as area, ordinality
      from unnest(coalesce(practice_areas_value, '{}'::text[]))
        with ordinality as areas(area_value, ordinality)
    ) cleaned_areas
    where area is not null
    group by area
  ) distinct_areas;
$$;

create or replace function public.normalize_law_firm_member_roles(
  roles_value text[]
)
returns text[]
language plpgsql
immutable
set search_path = public
as $$
declare
  normalized_roles text[];
  invalid_roles text[];
begin
  with raw_roles as (
    select lower(trim(role_value)) as role_value
    from unnest(coalesce(roles_value, '{}'::text[])) as role_value
    where nullif(trim(role_value), '') is not null
  ),
  distinct_roles as (
    select distinct role_value
    from raw_roles
  )
  select coalesce(
    array_agg(
      role_value
      order by case role_value
        when 'owner' then 1
        when 'admin' then 2
        when 'lawyer' then 3
        when 'secretary' then 4
        when 'intern' then 5
        else 99
      end
    ),
    '{}'::text[]
  )
  into normalized_roles
  from distinct_roles
  where role_value in ('owner', 'admin', 'lawyer', 'secretary', 'intern');

  with raw_roles as (
    select lower(trim(role_value)) as role_value
    from unnest(coalesce(roles_value, '{}'::text[])) as role_value
    where nullif(trim(role_value), '') is not null
  ),
  invalid as (
    select distinct role_value
    from raw_roles
    where role_value not in ('owner', 'admin', 'lawyer', 'secretary', 'intern')
  )
  select coalesce(array_agg(role_value), '{}'::text[])
  into invalid_roles
  from invalid;

  if coalesce(array_length(invalid_roles, 1), 0) > 0 then
    raise exception 'Invalid firm roles: %', array_to_string(invalid_roles, ', ');
  end if;

  if coalesce(array_length(normalized_roles, 1), 0) = 0 then
    return array['lawyer']::text[];
  end if;

  return normalized_roles;
end;
$$;

create or replace function public.primary_law_firm_member_role(
  roles_value text[]
)
returns text
language sql
immutable
set search_path = public
as $$
  select (public.normalize_law_firm_member_roles(roles_value))[1];
$$;

update public.law_firm_members
set roles = public.normalize_law_firm_member_roles(
  case
    when roles is not null
         and coalesce(array_length(roles, 1), 0) > 0
         and not (
           roles = array['lawyer']::text[]
           and coalesce(member_role::text, role) in ('owner', 'admin', 'secretary', 'intern')
         ) then roles
    else array[
      coalesce(
        nullif(member_role::text, ''),
        nullif(role, ''),
        'lawyer'
      )
    ]::text[]
  end
);

alter table public.law_firm_members
alter column roles set default array['lawyer']::text[];

alter table public.law_firm_members
alter column roles set not null;

alter table public.law_firm_members
drop constraint if exists law_firm_members_roles_allowed;

alter table public.law_firm_members
add constraint law_firm_members_roles_allowed
check (
  coalesce(array_length(roles, 1), 0) > 0
  and roles <@ array['owner', 'admin', 'lawyer', 'secretary', 'intern']::text[]
);

create index if not exists law_firm_members_roles_gin_idx
on public.law_firm_members using gin (roles);

create or replace function public.sync_law_firm_member_roles_legacy()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_roles text[];
  primary_role text;
  legacy_role text;
begin
  legacy_role := case
    when new.member_role::text in ('owner', 'admin', 'secretary', 'intern') then new.member_role::text
    when new.role in ('owner', 'admin', 'secretary', 'intern') then new.role
    when new.member_role::text in ('lawyer') then new.member_role::text
    when new.role in ('lawyer') then new.role
    else 'lawyer'
  end;

  normalized_roles := public.normalize_law_firm_member_roles(
    case
      when new.roles is not null
           and coalesce(array_length(new.roles, 1), 0) > 0
           and not (
             new.roles = array['lawyer']::text[]
             and legacy_role in ('owner', 'admin', 'secretary', 'intern')
           ) then new.roles
      else array[legacy_role]::text[]
    end
  );
  primary_role := public.primary_law_firm_member_role(normalized_roles);

  new.roles := normalized_roles;
  new.role := primary_role;
  new.member_role := primary_role::public.law_firm_member_role;

  return new;
end;
$$;

drop trigger if exists law_firm_members_sync_roles_legacy
on public.law_firm_members;

create trigger law_firm_members_sync_roles_legacy
before insert or update of roles, role, member_role
on public.law_firm_members
for each row execute function public.sync_law_firm_member_roles_legacy();

create or replace function public.current_law_firm_member_roles(
  law_firm_id_value uuid,
  profile_id_value uuid default auth.uid()
)
returns text[]
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select lfm.roles
    from public.law_firm_members lfm
    where lfm.law_firm_id = law_firm_id_value
      and lfm.profile_id = profile_id_value
      and lfm.status = 'active'
    limit 1
  ), '{}'::text[]);
$$;

create or replace function public.has_law_firm_role(
  law_firm_id_value uuid,
  role_value text,
  profile_id_value uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select lower(trim(role_value)) = any(
    public.current_law_firm_member_roles(law_firm_id_value, profile_id_value)
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
      and lfm.roles && array['owner', 'admin']::text[]
  );
$$;

create or replace function public.is_active_law_firm_case_manager(
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
      and lfm.roles && array['owner', 'admin', 'secretary']::text[]
  );
$$;

create or replace function public.update_law_firm_member_roles(
  law_firm_id_value uuid,
  member_profile_id_value uuid,
  roles_value text[]
)
returns text[]
language plpgsql
security definer
set search_path = public
as $$
declare
  target_member public.law_firm_members%rowtype;
  normalized_roles text[];
  primary_role text;
  actor_is_owner boolean;
  target_has_owner boolean;
  target_will_have_owner boolean;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  if coalesce(array_length(roles_value, 1), 0) = 0 then
    raise exception 'At least one firm role is required';
  end if;

  if not public.is_active_law_firm_manager(law_firm_id_value) then
    raise exception 'Only active office owners and admins can edit member roles';
  end if;

  actor_is_owner := public.has_law_firm_role(law_firm_id_value, 'owner');
  normalized_roles := public.normalize_law_firm_member_roles(roles_value);
  primary_role := public.primary_law_firm_member_role(normalized_roles);

  select *
  into target_member
  from public.law_firm_members
  where law_firm_id = law_firm_id_value
    and profile_id = member_profile_id_value
    and status <> 'disabled'
  for update;

  if not found then
    raise exception 'Firm member not found';
  end if;

  target_has_owner := 'owner' = any(target_member.roles);
  target_will_have_owner := 'owner' = any(normalized_roles);

  if target_has_owner and not actor_is_owner then
    raise exception 'Only owners can grant or remove owner role';
  end if;

  if target_has_owner is distinct from target_will_have_owner
      and not actor_is_owner then
    raise exception 'Only owners can grant or remove owner role';
  end if;

  if target_has_owner and not target_will_have_owner and not exists (
    select 1
    from public.law_firm_members lfm
    where lfm.law_firm_id = law_firm_id_value
      and lfm.profile_id <> member_profile_id_value
      and lfm.status = 'active'
      and 'owner' = any(lfm.roles)
  ) then
    raise exception 'Office must keep at least one owner';
  end if;

  update public.law_firm_members
  set
    roles = normalized_roles,
    role = primary_role,
    member_role = primary_role::public.law_firm_member_role
  where id = target_member.id;

  return normalized_roles;
end;
$$;

drop function if exists public.fetch_law_firm_cases(uuid);

create or replace function public.fetch_law_firm_cases(
  law_firm_id_value uuid
)
returns table (
  id uuid,
  title text,
  client_name text,
  client_initials text,
  assigned_lawyer_id uuid,
  assigned_lawyer text,
  area text,
  status_label text,
  next_step text,
  urgent boolean,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  with active_members as (
    select lfm.profile_id, lfm.roles
    from public.law_firm_members lfm
    where lfm.law_firm_id = law_firm_id_value
      and lfm.profile_id is not null
      and lfm.status = 'active'
  ),
  viewer as (
    select *
    from active_members
    where profile_id = auth.uid()
    limit 1
  ),
  scoped_cases as (
    select distinct lc.*
    from public.legal_cases lc
    where exists (select 1 from viewer)
      and (
        (
          exists (
            select 1
            from viewer
            where roles && array['owner', 'admin', 'secretary']::text[]
          )
          and (
            lc.law_firm_id = law_firm_id_value
            or exists (
              select 1
              from active_members assigned_member
              where assigned_member.profile_id = lc.assigned_lawyer_id
            )
            or exists (
              select 1
              from public.case_participants cp
              join active_members participant_member
                on participant_member.profile_id = cp.profile_id
              where cp.case_id = lc.id
                and cp.role in ('lawyer', 'firm_member')
            )
          )
        )
        or lc.assigned_lawyer_id = auth.uid()
        or exists (
          select 1
          from public.case_participants cp
          where cp.case_id = lc.id
            and cp.profile_id = auth.uid()
        )
      )
  )
  select
    sc.id,
    sc.title,
    coalesce(client_profile.full_name, 'Cliente') as client_name,
    coalesce(client_profile.initials, 'CL') as client_initials,
    sc.assigned_lawyer_id,
    coalesce(lawyer_profile.full_name, 'Sem advogado definido') as assigned_lawyer,
    sc.area,
    public.case_status_label(sc.status) as status_label,
    coalesce(sc.last_update_label, 'Atualizado hoje') as next_step,
    sc.status = 'deadline' as urgent,
    sc.updated_at
  from scoped_cases sc
  left join public.profiles client_profile
    on client_profile.id = sc.client_id
  left join public.profiles lawyer_profile
    on lawyer_profile.id = sc.assigned_lawyer_id
  order by sc.updated_at desc;
$$;

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

  select coalesce(lfm.lawyer_id, lfm.profile_id)
  into target_lawyer_id
  from public.law_firm_members lfm
  join public.lawyer_profiles lp
    on lp.id = coalesce(lfm.lawyer_id, lfm.profile_id)
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
    last_update_label = 'Caso atribuido',
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

  return target_lawyer_id;
end;
$$;

create or replace function public.can_manage_case_updates(case_id_value uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.legal_cases lc
    where lc.id = case_id_value
      and (
        lc.assigned_lawyer_id = auth.uid()
        or exists (
          select 1
          from public.case_participants cp
          where cp.case_id = lc.id
            and cp.profile_id = auth.uid()
            and cp.role = 'lawyer'
        )
      )
  );
$$;

create or replace function public.create_case_request(
  conversation_id_value uuid,
  title_value text,
  area_value text,
  summary_value text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  conversation_row public.conversations%rowtype;
  request_row public.case_requests%rowtype;
  request_id_value uuid;
  effective_law_firm_id uuid;
  clean_title text;
  clean_area text;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  clean_title := nullif(trim(coalesce(title_value, '')), '');
  clean_area := nullif(trim(coalesce(area_value, '')), '');

  if clean_title is null or clean_area is null then
    raise exception 'Title and area are required';
  end if;

  select *
  into conversation_row
  from public.conversations
  where id = conversation_id_value;

  if not found then
    raise exception 'Conversation not found';
  end if;

  effective_law_firm_id := conversation_row.law_firm_id;

  if effective_law_firm_id is null and conversation_row.lawyer_id = auth.uid() then
    select lfm.law_firm_id
    into effective_law_firm_id
    from public.law_firm_members lfm
    where lfm.profile_id = auth.uid()
      and lfm.status = 'active'
      and lfm.roles && array['owner', 'admin', 'lawyer', 'secretary']::text[]
    order by case
      when 'owner' = any(lfm.roles) then 1
      when 'admin' = any(lfm.roles) then 2
      when 'lawyer' = any(lfm.roles) then 3
      when 'secretary' = any(lfm.roles) then 4
      else 5
    end,
    coalesce(lfm.created_at, lfm.joined_at)
    limit 1;
  end if;

  if not (
    conversation_row.lawyer_id = auth.uid()
    or (
      conversation_row.law_firm_id is not null
      and public.is_active_law_firm_case_manager(conversation_row.law_firm_id)
    )
  ) then
    raise exception 'Only the responsible professional can request case acceptance';
  end if;

  select *
  into request_row
  from public.case_requests
  where conversation_id = conversation_id_value
    and status = 'pending'
  order by created_at desc
  limit 1;

  if found then
    request_id_value := request_row.id;

    update public.case_requests
    set
      title = clean_title,
      area = clean_area,
      summary = nullif(trim(coalesce(summary_value, '')), ''),
      law_firm_id = effective_law_firm_id,
      requested_by_profile_id = auth.uid()
    where id = request_id_value;
  else
    insert into public.case_requests (
      conversation_id,
      client_id,
      law_firm_id,
      lawyer_id,
      requested_by_profile_id,
      title,
      area,
      summary
    )
    values (
      conversation_row.id,
      conversation_row.client_id,
      effective_law_firm_id,
      conversation_row.lawyer_id,
      auth.uid(),
      clean_title,
      clean_area,
      nullif(trim(coalesce(summary_value, '')), '')
    )
    returning id into request_id_value;
  end if;

  perform public.ensure_case_request_client_surfaces(request_id_value);

  return request_id_value;
end;
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
    practice_areas,
    approved_at
  )
  values (
    target_verification.user_id,
    target_verification.oab_number,
    target_verification.oab_state,
    target_verification.practice_area,
    public.normalize_practice_areas(target_verification.practice_areas),
    coalesce(target_verification.reviewed_at, now())
  )
  on conflict (id) do update
  set
    oab_number = excluded.oab_number,
    oab_state = excluded.oab_state,
    primary_area = excluded.primary_area,
    practice_areas = excluded.practice_areas,
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
      roles,
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
      array['lawyer']::text[],
      'invited',
      'invited',
      null
    )
    returning id into membership_id_value;
  else
    existing_is_manager :=
      existing_member.status = 'active'
      and existing_member.roles && array['owner', 'admin', 'secretary']::text[];

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
      roles = case
        when existing_is_manager then roles
        else array['lawyer']::text[]
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
    'Convite para escritorio',
    coalesce(firm_name_value, 'Um escritorio') ||
      ' convidou voce para integrar a equipe.',
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
    and membership_row.roles && array['owner', 'admin', 'secretary']::text[];

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
      roles = case
        when is_manager_membership then
          public.normalize_law_firm_member_roles(roles || array['lawyer']::text[])
        else array['lawyer']::text[]
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

revoke all on function public.update_law_firm_member_roles(uuid, uuid, text[])
from public, anon;

grant execute on function public.update_law_firm_member_roles(uuid, uuid, text[])
to authenticated;

revoke all on function public.assign_law_firm_case(uuid, uuid, uuid)
from public, anon;

grant execute on function public.assign_law_firm_case(uuid, uuid, uuid)
to authenticated;

revoke all on function public.fetch_law_firm_cases(uuid)
from public, anon, authenticated;

grant execute on function public.fetch_law_firm_cases(uuid)
to authenticated;

revoke all on function public.create_case_request(uuid, text, text, text)
from public, anon, authenticated;

grant execute on function public.create_case_request(uuid, text, text, text)
to authenticated;

revoke all on function public.invite_verified_lawyer_to_law_firm(uuid, text, text)
from public, anon;

grant execute on function public.invite_verified_lawyer_to_law_firm(uuid, text, text)
to authenticated;

revoke all on function public.respond_to_law_firm_invite(uuid, boolean)
from public, anon;

grant execute on function public.respond_to_law_firm_invite(uuid, boolean)
to authenticated;

notify pgrst, 'reload schema';
