-- Repairs office owners after patch_030 and hardens role sync.
--
-- Run after patch_030 if an office creator cannot invite/manage members.
-- This is safe to run even if the bug did not happen.

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
    when new.member_role::text = 'lawyer' then new.member_role::text
    when new.role = 'lawyer' then new.role
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

update public.law_firm_members lfm
set
  roles = public.normalize_law_firm_member_roles(
    array[
      case
        when lfm.member_role::text in ('owner', 'admin', 'secretary', 'intern') then lfm.member_role::text
        when lfm.role in ('owner', 'admin', 'secretary', 'intern') then lfm.role
        else 'lawyer'
      end
    ]::text[]
  )
where lfm.roles = array['lawyer']::text[]
  and (
    lfm.member_role::text in ('owner', 'admin', 'secretary', 'intern')
    or lfm.role in ('owner', 'admin', 'secretary', 'intern')
  );

insert into public.law_firm_members (
  law_firm_id,
  profile_id,
  role,
  member_role,
  roles,
  status
)
select
  lfv.law_firm_id,
  lfv.owner_profile_id,
  'owner',
  'owner'::public.law_firm_member_role,
  array['owner']::text[],
  'active'::public.law_firm_member_status
from public.law_firm_verifications lfv
where lfv.status = 'approved'
  and lfv.law_firm_id is not null
  and not exists (
    select 1
    from public.law_firm_members lfm
    where lfm.law_firm_id = lfv.law_firm_id
      and lfm.profile_id = lfv.owner_profile_id
  );

update public.law_firm_members lfm
set
  roles = public.normalize_law_firm_member_roles(array['owner']::text[]),
  role = 'owner',
  member_role = 'owner'::public.law_firm_member_role,
  status = 'active'::public.law_firm_member_status
from public.law_firm_verifications lfv
where lfv.law_firm_id = lfm.law_firm_id
  and lfv.owner_profile_id = lfm.profile_id
  and lfv.status = 'approved'
  and not ('owner' = any(lfm.roles));

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
  )
  or exists (
    select 1
    from public.law_firm_verifications lfv
    where lfv.law_firm_id = law_firm_id_value
      and lfv.owner_profile_id = auth.uid()
      and lfv.status = 'approved'
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
  )
  or exists (
    select 1
    from public.law_firm_verifications lfv
    where lfv.law_firm_id = law_firm_id_value
      and lfv.owner_profile_id = auth.uid()
      and lfv.status = 'approved'
  );
$$;

notify pgrst, 'reload schema';
