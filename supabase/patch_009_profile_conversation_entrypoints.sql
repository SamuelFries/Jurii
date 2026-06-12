-- Profile entry points for starting conversations from client-facing profiles.
--
-- Run after patch_008.

drop policy if exists "profiles_select_approved_lawyers_public"
on public.profiles;

create policy "profiles_select_approved_lawyers_public"
on public.profiles for select
to authenticated
using (
  lawyer_status = 'approved'
  and exists (
    select 1
    from public.lawyer_profiles lp
    where lp.id = profiles.id
  )
);

create or replace function public.approve_lawyer_verification(
  verification_id_value uuid,
  reviewer_id_value uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  verification_row public.lawyer_verifications%rowtype;
begin
  select *
  into verification_row
  from public.lawyer_verifications
  where id = verification_id_value;

  if not found then
    raise exception 'Lawyer verification not found: %', verification_id_value;
  end if;

  update public.lawyer_verifications
  set
    status = 'approved',
    reviewed_at = now(),
    reviewer_id = reviewer_id_value,
    rejection_reason = null
  where id = verification_id_value;

  update public.profiles
  set lawyer_status = 'approved'
  where id = verification_row.user_id;

  insert into public.lawyer_profiles (
    id,
    oab_number,
    oab_state,
    primary_area,
    approved_at
  )
  values (
    verification_row.user_id,
    verification_row.oab_number,
    verification_row.oab_state,
    verification_row.practice_area,
    now()
  )
  on conflict (id) do update
  set
    oab_number = excluded.oab_number,
    oab_state = excluded.oab_state,
    primary_area = excluded.primary_area,
    approved_at = coalesce(public.lawyer_profiles.approved_at, excluded.approved_at);

  return verification_row.user_id;
end;
$$;

revoke all on function public.approve_lawyer_verification(uuid, uuid)
from public, anon, authenticated;

grant execute on function public.approve_lawyer_verification(uuid, uuid)
to service_role;

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
      specialty,
      last_message,
      last_message_at
    )
    values (
      'client_firm',
      auth.uid(),
      law_firm_id_value,
      firm_row.name,
      firm_row.specialty,
      'Conversa iniciada.',
      now()
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
      specialty,
      last_message,
      last_message_at
    )
    values (
      'client_firm',
      auth.uid(),
      lawyer_profile_id_value,
      profile_row.full_name,
      lawyer_row.primary_area,
      'Conversa iniciada.',
      now()
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

revoke all on function public.start_or_get_law_firm_conversation(uuid, text)
from public, anon;

revoke all on function public.start_or_get_lawyer_conversation(uuid, text)
from public, anon;

grant execute on function public.start_or_get_law_firm_conversation(uuid, text)
to authenticated;

grant execute on function public.start_or_get_lawyer_conversation(uuid, text)
to authenticated;
