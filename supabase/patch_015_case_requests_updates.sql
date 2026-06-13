-- Case request and case update workflow.
--
-- Run after patch_014. Lawyers and office members can propose a case from a
-- client conversation. Clients accept or decline. Accepted requests become
-- legal_cases, and professionals can add progress updates.

do $$
begin
  if not exists (select 1 from pg_type where typname = 'case_request_status') then
    create type public.case_request_status as enum (
      'pending',
      'accepted',
      'declined',
      'cancelled'
    );
  end if;
end $$;

create table if not exists public.case_requests (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  client_id uuid not null references public.profiles(id) on delete cascade,
  law_firm_id uuid references public.law_firms(id) on delete set null,
  lawyer_id uuid references public.lawyer_profiles(id) on delete set null,
  requested_by_profile_id uuid references public.profiles(id) on delete set null,
  legal_case_id uuid references public.legal_cases(id) on delete set null,
  title text not null,
  area text not null,
  summary text,
  status public.case_request_status not null default 'pending',
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists public.case_updates (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references public.legal_cases(id) on delete cascade,
  author_profile_id uuid references public.profiles(id) on delete set null,
  title text not null,
  body text,
  created_at timestamptz not null default now()
);

create index if not exists case_requests_client_status_idx
on public.case_requests(client_id, status);

create index if not exists case_requests_conversation_status_idx
on public.case_requests(conversation_id, status);

create index if not exists case_updates_case_created_idx
on public.case_updates(case_id, created_at desc);

drop trigger if exists case_requests_set_updated_at on public.case_requests;
create trigger case_requests_set_updated_at
before update on public.case_requests
for each row execute function public.set_updated_at();

alter table public.case_requests enable row level security;
alter table public.case_updates enable row level security;

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
            and cp.role in ('lawyer', 'firm_member')
        )
        or (
          lc.law_firm_id is not null
          and exists (
            select 1
            from public.law_firm_members lfm
            where lfm.law_firm_id = lc.law_firm_id
              and lfm.profile_id = auth.uid()
              and lfm.status = 'active'
          )
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
  request_id_value uuid;
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

  if not (
    conversation_row.lawyer_id = auth.uid()
    or (
      conversation_row.law_firm_id is not null
      and exists (
        select 1
        from public.law_firm_members lfm
        where lfm.law_firm_id = conversation_row.law_firm_id
          and lfm.profile_id = auth.uid()
          and lfm.status = 'active'
      )
    )
  ) then
    raise exception 'Only the responsible professional can request case acceptance';
  end if;

  select id
  into request_id_value
  from public.case_requests
  where conversation_id = conversation_id_value
    and status = 'pending'
  order by created_at desc
  limit 1;

  if request_id_value is not null then
    update public.case_requests
    set
      title = clean_title,
      area = clean_area,
      summary = nullif(trim(coalesce(summary_value, '')), ''),
      requested_by_profile_id = auth.uid()
    where id = request_id_value;

    return request_id_value;
  end if;

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
    conversation_row.law_firm_id,
    conversation_row.lawyer_id,
    auth.uid(),
    clean_title,
    clean_area,
    nullif(trim(coalesce(summary_value, '')), '')
  )
  returning id into request_id_value;

  insert into public.messages (
    conversation_id,
    sender_id,
    sender_type,
    body
  )
  values (
    conversation_row.id,
    auth.uid(),
    'system',
    'Solicitação de caso enviada: ' || clean_title
  );

  return request_id_value;
end;
$$;

create or replace function public.fetch_case_requests_for_client()
returns table (
  id uuid,
  conversation_id uuid,
  title text,
  area text,
  summary text,
  status text,
  requested_by text,
  requester_initials text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    cr.id,
    cr.conversation_id,
    cr.title,
    cr.area,
    cr.summary,
    cr.status::text as status,
    case
      when cr.law_firm_id is not null then coalesce(lf.name, requester.full_name, 'Jurii')
      else coalesce(requester.full_name, lawyer_profile.full_name, 'Advogado Jurii')
    end as requested_by,
    case
      when cr.law_firm_id is not null then coalesce(lf.initials, requester.initials, 'JE')
      else coalesce(requester.initials, lawyer_profile.initials, 'AJ')
    end as requester_initials,
    cr.created_at
  from public.case_requests cr
  left join public.profiles requester
    on requester.id = cr.requested_by_profile_id
  left join public.law_firms lf
    on lf.id = cr.law_firm_id
  left join public.profiles lawyer_profile
    on lawyer_profile.id = cr.lawyer_id
  where cr.client_id = auth.uid()
    and cr.status = 'pending'
  order by cr.created_at desc;
$$;

create or replace function public.respond_to_case_request(
  request_id_value uuid,
  accepted_value boolean
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  request_row public.case_requests%rowtype;
  case_id_value uuid;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  select *
  into request_row
  from public.case_requests
  where id = request_id_value
  for update;

  if not found then
    raise exception 'Case request not found';
  end if;

  if request_row.client_id <> auth.uid() then
    raise exception 'Only the client can respond to this case request';
  end if;

  if request_row.status <> 'pending' then
    raise exception 'This case request has already been answered';
  end if;

  if not accepted_value then
    update public.case_requests
    set status = 'declined',
        responded_at = now()
    where id = request_id_value;

    insert into public.messages (
      conversation_id,
      sender_id,
      sender_type,
      body
    )
    values (
      request_row.conversation_id,
      auth.uid(),
      'system',
      'Solicitação de caso recusada pelo cliente.'
    );

    return null;
  end if;

  insert into public.legal_cases (
    title,
    area,
    status,
    client_id,
    law_firm_id,
    assigned_lawyer_id,
    description,
    last_update_label
  )
  values (
    request_row.title,
    request_row.area,
    'open',
    request_row.client_id,
    request_row.law_firm_id,
    request_row.lawyer_id,
    request_row.summary,
    'Caso aceito pelo cliente'
  )
  returning id into case_id_value;

  insert into public.case_participants (case_id, profile_id, role)
  values (case_id_value, request_row.client_id, 'client')
  on conflict (case_id, profile_id) do nothing;

  if request_row.lawyer_id is not null then
    insert into public.case_participants (case_id, profile_id, role)
    values (case_id_value, request_row.lawyer_id, 'lawyer')
    on conflict (case_id, profile_id) do nothing;
  end if;

  if request_row.requested_by_profile_id is not null then
    insert into public.case_participants (case_id, profile_id, role)
    values (
      case_id_value,
      request_row.requested_by_profile_id,
      case
        when request_row.requested_by_profile_id = request_row.lawyer_id then 'lawyer'
        else 'firm_member'
      end::public.case_participant_role
    )
    on conflict (case_id, profile_id) do nothing;
  end if;

  insert into public.case_updates (
    case_id,
    author_profile_id,
    title,
    body
  )
  values (
    case_id_value,
    auth.uid(),
    'Caso iniciado',
    'O cliente aceitou a solicitação e o caso foi criado na Jurii.'
  );

  update public.conversations
  set case_id = case_id_value,
      updated_at = now()
  where id = request_row.conversation_id;

  update public.case_requests
  set status = 'accepted',
      legal_case_id = case_id_value,
      responded_at = now()
  where id = request_id_value;

  insert into public.messages (
    conversation_id,
    sender_id,
    sender_type,
    body
  )
  values (
    request_row.conversation_id,
    auth.uid(),
    'system',
    'Solicitação de caso aceita pelo cliente.'
  );

  return case_id_value;
end;
$$;

create or replace function public.fetch_case_updates(case_id_value uuid)
returns table (
  id uuid,
  case_id uuid,
  title text,
  body text,
  author_name text,
  author_initials text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    cu.id,
    cu.case_id,
    cu.title,
    cu.body,
    coalesce(author.full_name, 'Jurii') as author_name,
    coalesce(author.initials, 'JR') as author_initials,
    cu.created_at
  from public.case_updates cu
  left join public.profiles author
    on author.id = cu.author_profile_id
  where cu.case_id = case_id_value
    and public.can_access_case(cu.case_id)
  order by cu.created_at desc;
$$;

create or replace function public.add_case_update(
  case_id_value uuid,
  title_value text,
  body_value text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  update_id_value uuid;
  clean_title text;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  if not public.can_manage_case_updates(case_id_value) then
    raise exception 'Only professionals assigned to this case can add updates';
  end if;

  clean_title := nullif(trim(coalesce(title_value, '')), '');
  if clean_title is null then
    raise exception 'Title is required';
  end if;

  insert into public.case_updates (
    case_id,
    author_profile_id,
    title,
    body
  )
  values (
    case_id_value,
    auth.uid(),
    clean_title,
    nullif(trim(coalesce(body_value, '')), '')
  )
  returning id into update_id_value;

  update public.legal_cases
  set last_update_label = clean_title,
      updated_at = now()
  where id = case_id_value;

  return update_id_value;
end;
$$;

drop policy if exists "case_requests_select_related" on public.case_requests;
create policy "case_requests_select_related"
on public.case_requests for select
to authenticated
using (
  client_id = auth.uid()
  or lawyer_id = auth.uid()
  or requested_by_profile_id = auth.uid()
  or (
    law_firm_id is not null
    and exists (
      select 1
      from public.law_firm_members lfm
      where lfm.law_firm_id = case_requests.law_firm_id
        and lfm.profile_id = auth.uid()
        and lfm.status = 'active'
    )
  )
);

drop policy if exists "case_updates_select_related" on public.case_updates;
create policy "case_updates_select_related"
on public.case_updates for select
to authenticated
using (public.can_access_case(case_updates.case_id));

drop policy if exists "case_updates_insert_professional" on public.case_updates;
create policy "case_updates_insert_professional"
on public.case_updates for insert
to authenticated
with check (
  author_profile_id = auth.uid()
  and public.can_manage_case_updates(case_updates.case_id)
);

grant select, insert, update on public.case_requests to authenticated;
grant select, insert on public.case_updates to authenticated;

revoke all on function public.can_manage_case_updates(uuid)
from public, anon, authenticated;

revoke all on function public.create_case_request(uuid, text, text, text)
from public, anon, authenticated;

revoke all on function public.fetch_case_requests_for_client()
from public, anon, authenticated;

revoke all on function public.respond_to_case_request(uuid, boolean)
from public, anon, authenticated;

revoke all on function public.fetch_case_updates(uuid)
from public, anon, authenticated;

revoke all on function public.add_case_update(uuid, text, text)
from public, anon, authenticated;

grant execute on function public.create_case_request(uuid, text, text, text)
to authenticated;

grant execute on function public.fetch_case_requests_for_client()
to authenticated;

grant execute on function public.respond_to_case_request(uuid, boolean)
to authenticated;

grant execute on function public.fetch_case_updates(uuid)
to authenticated;

grant execute on function public.add_case_update(uuid, text, text)
to authenticated;
