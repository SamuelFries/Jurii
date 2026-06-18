-- Soft account deletion while preserving shared legal history.
--
-- Run after patch_034. This intentionally does not physically delete
-- public.profiles because several shared resources still reference it:
-- conversations, cases, appointments and documents. The deleted account is
-- blocked by the app, professional access is removed, and related users keep
-- seeing the historical name with "(delleted account)" in conversation lists.

alter table public.profiles
add column if not exists deleted_at timestamptz;

alter table public.profiles
add column if not exists deleted_display_name text;

alter table public.profiles
add column if not exists deleted_email text;

create index if not exists profiles_deleted_at_idx
on public.profiles(deleted_at);

create or replace function public.profile_display_name(
  full_name_value text,
  deleted_display_name_value text,
  deleted_at_value timestamptz
)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when deleted_at_value is not null then
      coalesce(
        nullif(trim(deleted_display_name_value), ''),
        nullif(trim(full_name_value), ''),
        'Usuário'
      ) || ' (delleted account)'
    else
      coalesce(nullif(trim(full_name_value), ''), 'Usuário Jurii')
  end;
$$;

create or replace function public.law_firm_member_role_rank(
  roles_value text[]
)
returns int
language sql
immutable
set search_path = public
as $$
  select case
    when 'owner' = any(coalesce(roles_value, '{}'::text[])) then 1
    when 'admin' = any(coalesce(roles_value, '{}'::text[])) then 2
    when 'lawyer' = any(coalesce(roles_value, '{}'::text[])) then 3
    when 'secretary' = any(coalesce(roles_value, '{}'::text[])) then 4
    when 'intern' = any(coalesce(roles_value, '{}'::text[])) then 5
    else 99
  end;
$$;

create or replace function public.can_select_profile(profile_id_value uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles target_profile
    where target_profile.id = profile_id_value
      and target_profile.deleted_at is null
  )
  and (
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
  );
$$;

create or replace function public.transfer_owned_law_firms_for_deleted_profile(
  profile_id_value uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  firm_record record;
  replacement_record record;
  replacement_roles text[];
  replacement_primary_role text;
begin
  for firm_record in
    select distinct lfv.law_firm_id
    from public.law_firm_verifications lfv
    where lfv.owner_profile_id = profile_id_value
      and lfv.law_firm_id is not null
      and lfv.status = 'approved'
  loop
    select
      lfm.id,
      lfm.profile_id,
      coalesce(lfm.roles, array[lfm.member_role::text]::text[]) as roles
    into replacement_record
    from public.law_firm_members lfm
    join public.profiles p
      on p.id = lfm.profile_id
    where lfm.law_firm_id = firm_record.law_firm_id
      and lfm.profile_id is not null
      and lfm.profile_id <> profile_id_value
      and lfm.status = 'active'
      and p.deleted_at is null
    order by
      public.law_firm_member_role_rank(
        coalesce(lfm.roles, array[lfm.member_role::text]::text[])
      ),
      lower(coalesce(nullif(trim(p.full_name), ''), p.email, p.id::text)),
      lfm.profile_id
    limit 1;

    if replacement_record.profile_id is not null then
      replacement_roles := public.normalize_law_firm_member_roles(
        case
          when 'owner' = any(replacement_record.roles) then replacement_record.roles
          else replacement_record.roles || array['owner']::text[]
        end
      );
      replacement_primary_role := public.primary_law_firm_member_role(
        replacement_roles
      );

      update public.law_firm_members
      set
        roles = replacement_roles,
        role = replacement_primary_role,
        member_role = replacement_primary_role::public.law_firm_member_role,
        status = 'active'
      where id = replacement_record.id;

      update public.law_firm_verifications
      set
        owner_profile_id = replacement_record.profile_id,
        updated_at = now()
      where law_firm_id = firm_record.law_firm_id
        and owner_profile_id = profile_id_value
        and status = 'approved';
    end if;
  end loop;
end;
$$;

create or replace function public.delete_current_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  profile_id_value uuid;
  profile_row public.profiles%rowtype;
  deleted_name_value text;
  deleted_email_value text;
begin
  profile_id_value := auth.uid();

  if profile_id_value is null then
    raise exception 'User must be authenticated';
  end if;

  select *
  into profile_row
  from public.profiles
  where id = profile_id_value
  for update;

  if not found then
    return;
  end if;

  if profile_row.deleted_at is not null then
    return;
  end if;

  deleted_name_value := coalesce(
    nullif(trim(profile_row.deleted_display_name), ''),
    nullif(trim(profile_row.full_name), ''),
    'Usuário'
  );
  deleted_email_value := nullif(trim(profile_row.email), '');

  perform public.transfer_owned_law_firms_for_deleted_profile(profile_id_value);

  update public.conversations
  set
    title = deleted_name_value || ' (delleted account)',
    updated_at = now()
  where lawyer_id = profile_id_value
    and law_firm_id is null;

  update public.law_firm_members
  set
    status = 'disabled',
    lawyer_id = null,
    pending_lawyer_id = null,
    lawyer_invite_status = 'disabled'
  where profile_id = profile_id_value
     or lawyer_id = profile_id_value
     or pending_lawyer_id = profile_id_value;

  delete from public.verification_documents
  where user_id = profile_id_value;

  delete from public.lawyer_verifications
  where user_id = profile_id_value;

  delete from public.lawyer_profiles
  where id = profile_id_value;

  delete from public.law_firm_verification_documents lfvd
  where lfvd.owner_profile_id = profile_id_value
    and exists (
      select 1
      from public.law_firm_verifications lfv
      where lfv.id = lfvd.verification_id
        and lfv.owner_profile_id = profile_id_value
        and lfv.status <> 'approved'
    );

  update public.law_firm_verifications
  set
    status = case
      when law_firm_id is null then 'rejected'::public.verification_status
      else status
    end,
    rejection_reason = case
      when law_firm_id is null then 'Conta solicitante excluída.'
      else rejection_reason
    end,
    updated_at = now()
  where owner_profile_id = profile_id_value;

  update public.profiles
  set
    deleted_at = now(),
    deleted_display_name = deleted_name_value,
    deleted_email = deleted_email_value,
    full_name = deleted_name_value,
    email = 'deleted+' || profile_id_value::text || '@deleted.jurii.local',
    cpf = null,
    phone = null,
    avatar_url = null,
    lawyer_status = 'client'
  where id = profile_id_value;
end;
$$;

create or replace function public.fetch_chat_profile(
  profile_id_value uuid
)
returns table (
  id uuid,
  full_name text,
  email text,
  initials text,
  member_since date,
  lawyer_status text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    p.full_name,
    p.email,
    p.initials,
    p.member_since,
    p.lawyer_status::text
  from public.profiles p
  where p.id = profile_id_value
    and p.deleted_at is null
    and public.can_select_profile(p.id)
  limit 1;
$$;

drop function if exists public.fetch_lawyer_public_profile(uuid);

create or replace function public.fetch_lawyer_public_profile(
  lawyer_profile_id_value uuid
)
returns table (
  id uuid,
  full_name text,
  initials text,
  oab_number text,
  oab_state text,
  primary_area text,
  practice_areas text[],
  bio text,
  rating numeric,
  reviews_count int,
  avatar_type text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    lp.id,
    coalesce(p.full_name, 'Advogado Jurii') as full_name,
    coalesce(p.initials, 'AJ') as initials,
    lp.oab_number,
    lp.oab_state::text as oab_state,
    lp.primary_area,
    case
      when cardinality(lp.practice_areas) > 0 then lp.practice_areas
      else array[lp.primary_area]
    end as practice_areas,
    coalesce(lp.bio, 'Perfil profissional verificado pela Jurii.') as bio,
    4.8::numeric as rating,
    0::int as reviews_count,
    'navy'::text as avatar_type
  from public.lawyer_profiles lp
  join public.profiles p on p.id = lp.id
  where lp.id = lawyer_profile_id_value
    and lp.is_available = true
    and p.deleted_at is null
  limit 1;
$$;

create or replace function public.fetch_conversation_for_current_user(
  conversation_id_value uuid
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
  select
    c.id,
    c.type::text,
    case
      when c.client_id = auth.uid() and c.law_firm_id is not null then
        coalesce(lf.name, c.title)
      when c.client_id = auth.uid() and c.lawyer_id is not null then
        public.profile_display_name(
          lawyer_profile.full_name,
          lawyer_profile.deleted_display_name,
          lawyer_profile.deleted_at
        )
      when c.client_id = auth.uid() then
        c.title
      else
        public.profile_display_name(
          client_profile.full_name,
          client_profile.deleted_display_name,
          client_profile.deleted_at
        )
    end as title,
    case
      when c.client_id = auth.uid() and c.law_firm_id is not null then
        coalesce(lf.initials, 'JE')
      when c.client_id = auth.uid() and c.lawyer_id is not null then
        coalesce(lawyer_profile.initials, 'AJ')
      when c.client_id = auth.uid() then
        upper(left(trim(c.title), 2))
      else
        coalesce(client_profile.initials, 'CL')
    end as initials,
    coalesce(c.specialty, 'Atendimento jurídico') as specialty,
    coalesce(c.last_message, 'Nova conversa') as last_message,
    c.last_message_at,
    c.law_firm_id,
    c.client_id,
    c.lawyer_id
  from public.conversations c
  left join public.profiles client_profile
    on client_profile.id = c.client_id
  left join public.law_firms lf
    on lf.id = c.law_firm_id
  left join public.profiles lawyer_profile
    on lawyer_profile.id = c.lawyer_id
  where c.id = conversation_id_value
    and (
      c.client_id = auth.uid()
      or c.lawyer_id = auth.uid()
      or exists (
        select 1
        from public.law_firm_members lfm
        where lfm.law_firm_id = c.law_firm_id
          and lfm.profile_id = auth.uid()
          and lfm.status = 'active'
      )
      or (
        c.case_id is not null
        and public.can_access_case(c.case_id)
      )
    )
  limit 1;
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

create or replace function public.fetch_lawyer_cases()
returns table (
  id uuid,
  title text,
  client_name text,
  client_initials text,
  area text,
  last_update_label text,
  status text,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select distinct
    lc.id,
    lc.title,
    public.profile_display_name(
      client_profile.full_name,
      client_profile.deleted_display_name,
      client_profile.deleted_at
    ) as client_name,
    coalesce(client_profile.initials, 'CL') as client_initials,
    lc.area,
    coalesce(lc.last_update_label, 'Atualizado hoje') as last_update_label,
    lc.status::text as status,
    lc.updated_at
  from public.legal_cases lc
  left join public.profiles client_profile
    on client_profile.id = lc.client_id
  where lc.assigned_lawyer_id = auth.uid()
     or exists (
      select 1
      from public.case_participants cp
      where cp.case_id = lc.id
        and cp.profile_id = auth.uid()
        and cp.role in ('lawyer', 'firm_member')
     )
  order by lc.updated_at desc;
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
    public.profile_display_name(
      client_profile.full_name,
      client_profile.deleted_display_name,
      client_profile.deleted_at
    ) as client_name,
    coalesce(client_profile.initials, 'CL') as client_initials,
    sc.assigned_lawyer_id,
    case
      when lawyer_profile.id is null then 'Sem advogado definido'
      else public.profile_display_name(
        lawyer_profile.full_name,
        lawyer_profile.deleted_display_name,
        lawyer_profile.deleted_at
      )
    end as assigned_lawyer,
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

revoke all on function public.profile_display_name(text, text, timestamptz)
from public, anon, authenticated;

revoke all on function public.law_firm_member_role_rank(text[])
from public, anon, authenticated;

revoke all on function public.can_select_profile(uuid)
from public, anon, authenticated;

revoke all on function public.transfer_owned_law_firms_for_deleted_profile(uuid)
from public, anon, authenticated;

revoke all on function public.delete_current_account()
from public, anon, authenticated;

revoke all on function public.fetch_chat_profile(uuid)
from public, anon, authenticated;

revoke all on function public.fetch_lawyer_public_profile(uuid)
from public, anon, authenticated;

revoke all on function public.fetch_conversation_for_current_user(uuid)
from public, anon, authenticated;

revoke all on function public.fetch_conversations_for_current_user(text, uuid)
from public, anon, authenticated;

revoke all on function public.fetch_lawyer_cases()
from public, anon, authenticated;

revoke all on function public.fetch_law_firm_cases(uuid)
from public, anon, authenticated;

grant execute on function public.delete_current_account()
to authenticated;

grant execute on function public.can_select_profile(uuid)
to authenticated;

grant execute on function public.fetch_chat_profile(uuid)
to authenticated;

grant execute on function public.fetch_lawyer_public_profile(uuid)
to authenticated;

grant execute on function public.fetch_conversation_for_current_user(uuid)
to authenticated;

grant execute on function public.fetch_conversations_for_current_user(text, uuid)
to authenticated;

grant execute on function public.fetch_lawyer_cases()
to authenticated;

grant execute on function public.fetch_law_firm_cases(uuid)
to authenticated;

notify pgrst, 'reload schema';
