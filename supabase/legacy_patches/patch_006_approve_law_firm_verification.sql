-- Administrative helper for approving office verification requests.
--
-- Run patch_004 and patch_005 first. Then approve a request from the SQL
-- Editor with:
--
-- select public.approve_law_firm_verification('VERIFICATION_ID_HERE');
--
-- This creates/updates the public law firm, links it back to the verification,
-- and creates the owner membership used by the app's office area.

create or replace function public.approve_law_firm_verification(
  verification_id_value uuid,
  reviewer_id_value uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  verification_row public.law_firm_verifications%rowtype;
  firm_id_value uuid;
  initials_value text;
  existing_member_id uuid;
begin
  select *
  into verification_row
  from public.law_firm_verifications
  where id = verification_id_value;

  if not found then
    raise exception 'Law firm verification not found: %', verification_id_value;
  end if;

  initials_value := upper(left(trim(verification_row.firm_name), 1));
  if initials_value is null or initials_value = '' then
    initials_value := 'E';
  end if;

  if verification_row.law_firm_id is null then
    insert into public.law_firms (
      name,
      initials,
      specialty,
      rating,
      reviews_count,
      distance_label,
      avatar_type,
      phone,
      email,
      address,
      is_active
    )
    values (
      verification_row.firm_name,
      initials_value,
      'Escritório jurídico',
      0,
      0,
      '',
      'purple',
      nullif(verification_row.phone, ''),
      nullif(verification_row.email, ''),
      nullif(verification_row.address, ''),
      true
    )
    returning id into firm_id_value;
  else
    firm_id_value := verification_row.law_firm_id;

    update public.law_firms
    set
      name = verification_row.firm_name,
      initials = initials_value,
      phone = nullif(verification_row.phone, ''),
      email = nullif(verification_row.email, ''),
      address = nullif(verification_row.address, ''),
      avatar_type = 'purple',
      is_active = true,
      updated_at = now()
    where id = firm_id_value;
  end if;

  update public.law_firm_verifications
  set
    status = 'approved',
    law_firm_id = firm_id_value,
    reviewed_at = now(),
    reviewer_id = reviewer_id_value,
    rejection_reason = null
  where id = verification_id_value;

  select id
  into existing_member_id
  from public.law_firm_members
  where law_firm_id = firm_id_value
    and profile_id = verification_row.owner_profile_id
  limit 1;

  if existing_member_id is null then
    insert into public.law_firm_members (
      law_firm_id,
      profile_id,
      role,
      member_role,
      status
    )
    values (
      firm_id_value,
      verification_row.owner_profile_id,
      'owner',
      'owner',
      'active'
    );
  else
    update public.law_firm_members
    set
      role = 'owner',
      member_role = 'owner',
      status = 'active'
    where id = existing_member_id;
  end if;

  return firm_id_value;
end;
$$;

revoke all on function public.approve_law_firm_verification(uuid, uuid)
from public, anon, authenticated;

grant execute on function public.approve_law_firm_verification(uuid, uuid)
to service_role;
