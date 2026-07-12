-- Fixes profile RLS recursion during lawyer verification submission.
--
-- Run after patch_016. The main issue is a recursive policy chain:
-- profiles -> lawyer_profiles -> profiles. This patch makes lawyer_profiles
-- readable without checking profiles and moves verification submission into a
-- SECURITY DEFINER RPC.

drop policy if exists "lawyer_profiles_public_read_approved"
on public.lawyer_profiles;

create policy "lawyer_profiles_public_read_approved"
on public.lawyer_profiles for select
to authenticated
using (
  id = auth.uid()
  or approved_at is not null
);

create or replace function public.submit_lawyer_verification(
  oab_number_value text,
  oab_state_value text,
  practice_area_value text
)
returns table (
  id uuid,
  user_id uuid,
  oab_number text,
  oab_state char(2),
  practice_area text,
  status public.verification_status,
  submitted_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  user_id_value uuid;
  email_value text;
  full_name_value text;
  verification_id_value uuid;
  submitted_at_value timestamptz;
  normalized_oab_number text;
  normalized_oab_state char(2);
  normalized_practice_area text;
  status_value public.verification_status := 'pending';
begin
  user_id_value := auth.uid();

  if user_id_value is null then
    raise exception 'User must be authenticated';
  end if;

  normalized_oab_number := nullif(trim(coalesce(oab_number_value, '')), '');
  normalized_oab_state := upper(trim(coalesce(oab_state_value, '')))::char(2);
  normalized_practice_area := nullif(trim(coalesce(practice_area_value, '')), '');

  if normalized_oab_number is null then
    raise exception 'OAB number is required';
  end if;

  if nullif(trim(coalesce(oab_state_value, '')), '') is null then
    raise exception 'OAB state is required';
  end if;

  if normalized_practice_area is null then
    raise exception 'Practice area is required';
  end if;

  email_value := coalesce(auth.jwt() ->> 'email', '');
  full_name_value := coalesce(
    nullif(auth.jwt() -> 'user_metadata' ->> 'full_name', ''),
    nullif(auth.jwt() -> 'user_metadata' ->> 'name', ''),
    nullif(split_part(email_value, '@', 1), ''),
    'Usuário Jurii'
  );

  insert into public.profiles (
    id,
    full_name,
    email,
    initials,
    lawyer_status
  )
  values (
    user_id_value,
    full_name_value,
    email_value,
    upper(left(full_name_value, 1)),
    'pending'
  )
  on conflict on constraint profiles_pkey do update
  set
    full_name = coalesce(nullif(public.profiles.full_name, ''), excluded.full_name),
    email = coalesce(nullif(public.profiles.email, ''), excluded.email),
    initials = coalesce(nullif(public.profiles.initials, ''), excluded.initials),
    lawyer_status = case
      when public.profiles.lawyer_status = 'approved' then 'approved'::public.lawyer_status
      else 'pending'::public.lawyer_status
    end,
    updated_at = now();

  insert into public.lawyer_verifications (
    user_id,
    oab_number,
    oab_state,
    practice_area,
    status
  )
  values (
    user_id_value,
    normalized_oab_number,
    normalized_oab_state,
    normalized_practice_area,
    status_value
  )
  returning
    public.lawyer_verifications.id,
    public.lawyer_verifications.submitted_at
  into verification_id_value, submitted_at_value;

  return query
  select
    verification_id_value,
    user_id_value,
    normalized_oab_number,
    normalized_oab_state,
    normalized_practice_area,
    status_value,
    submitted_at_value;
end;
$$;

revoke all on function public.submit_lawyer_verification(text, text, text)
from public, anon, authenticated;

grant execute on function public.submit_lawyer_verification(text, text, text)
to authenticated;
