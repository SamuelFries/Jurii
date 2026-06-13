-- Makes case requests actionable from notifications and chat.
--
-- Run after patch_015. The original case request flow stays the same, but
-- each request now owns one chat system message and one client notification.

alter table public.messages
add column if not exists metadata jsonb not null default '{}'::jsonb;

alter table public.case_requests
add column if not exists message_id uuid references public.messages(id) on delete set null;

alter table public.case_requests
add column if not exists notification_id uuid references public.notifications(id) on delete set null;

create index if not exists case_requests_message_idx
on public.case_requests(message_id);

create index if not exists case_requests_notification_idx
on public.case_requests(notification_id);

create or replace function public.sync_case_request_action_surfaces(
  request_id_value uuid,
  status_value public.case_request_status,
  legal_case_id_value uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  request_row public.case_requests%rowtype;
  metadata_value jsonb;
  status_label text;
  message_body text;
  notification_title text;
  notification_body text;
begin
  select *
  into request_row
  from public.case_requests
  where id = request_id_value;

  if not found then
    return;
  end if;

  status_label := case status_value
    when 'accepted' then 'accepted'
    when 'declined' then 'declined'
    when 'cancelled' then 'cancelled'
    else 'pending'
  end;

  metadata_value := jsonb_strip_nulls(jsonb_build_object(
    'type', 'case_request',
    'case_request_id', request_row.id,
    'request_status', status_label,
    'conversation_id', request_row.conversation_id,
    'legal_case_id', coalesce(legal_case_id_value, request_row.legal_case_id),
    'title', request_row.title,
    'area', request_row.area
  ));

  message_body := case status_value
    when 'accepted' then 'Caso aceito: ' || request_row.title
    when 'declined' then 'Caso recusado: ' || request_row.title
    when 'cancelled' then 'Solicitação cancelada: ' || request_row.title
    else 'Solicitação de aceite do caso: ' || request_row.title
  end;

  notification_title := case status_value
    when 'accepted' then 'Caso aceito'
    when 'declined' then 'Caso recusado'
    when 'cancelled' then 'Solicitação cancelada'
    else 'Solicitação de caso'
  end;

  notification_body := case status_value
    when 'accepted' then 'Você aceitou o caso "' || request_row.title || '".'
    when 'declined' then 'Você recusou o caso "' || request_row.title || '".'
    when 'cancelled' then 'A solicitação do caso "' || request_row.title || '" foi cancelada.'
    else 'Revise e responda a solicitação do caso "' || request_row.title || '".'
  end;

  if request_row.message_id is not null then
    update public.messages
    set body = message_body,
        metadata = metadata_value
    where id = request_row.message_id;
  end if;

  if request_row.notification_id is not null then
    update public.notifications
    set title = notification_title,
        body = notification_body,
        metadata = metadata_value,
        read_at = case
          when status_value = 'pending' then null
          else coalesce(read_at, now())
        end
    where id = request_row.notification_id;
  end if;
end;
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
  message_id_value uuid;
  notification_id_value uuid;
  effective_law_firm_id uuid;
  clean_title text;
  clean_area text;
  requester_name text;
  metadata_value jsonb;
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
    order by case lfm.member_role
      when 'owner' then 1
      when 'admin' then 2
      when 'lawyer' then 3
      else 4
    end,
    lfm.created_at
    limit 1;
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

    request_row.message_id := null;
    request_row.notification_id := null;
  end if;

  select case
    when effective_law_firm_id is not null then
      coalesce(lf.name, requester.full_name, 'Jurii')
    else
      coalesce(requester.full_name, 'Advogado Jurii')
    end
  into requester_name
  from public.profiles requester
  left join public.law_firms lf
    on lf.id = effective_law_firm_id
  where requester.id = auth.uid();

  metadata_value := jsonb_build_object(
    'type', 'case_request',
    'case_request_id', request_id_value,
    'request_status', 'pending',
    'conversation_id', conversation_row.id,
    'title', clean_title,
    'area', clean_area
  );

  if request_row.message_id is not null then
    update public.messages
    set body = 'Solicitação de aceite do caso: ' || clean_title,
        metadata = metadata_value
    where id = request_row.message_id
    returning id into message_id_value;
  end if;

  if message_id_value is null then
    insert into public.messages (
      conversation_id,
      sender_id,
      sender_type,
      body,
      metadata
    )
    values (
      conversation_row.id,
      auth.uid(),
      'system',
      'Solicitação de aceite do caso: ' || clean_title,
      metadata_value
    )
    returning id into message_id_value;
  end if;

  if request_row.notification_id is not null then
    update public.notifications
    set
      title = 'Solicitação de caso',
      body = coalesce(requester_name, 'Jurii') || ' pediu seu aceite para o caso "' || clean_title || '".',
      type = 'case_request',
      actor_profile_id = auth.uid(),
      law_firm_id = effective_law_firm_id,
      metadata = metadata_value,
      read_at = null
    where id = request_row.notification_id
    returning id into notification_id_value;
  end if;

  if notification_id_value is null then
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
      conversation_row.client_id,
      auth.uid(),
      effective_law_firm_id,
      'case_request',
      'Solicitação de caso',
      coalesce(requester_name, 'Jurii') || ' pediu seu aceite para o caso "' || clean_title || '".',
      metadata_value
    )
    returning id into notification_id_value;
  end if;

  update public.case_requests
  set message_id = message_id_value,
      notification_id = notification_id_value
  where id = request_id_value;

  return request_id_value;
end;
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
  effective_law_firm_id uuid;
  client_name_value text;
  lawyer_name_value text;
  response_status public.case_request_status;
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
    return request_row.legal_case_id;
  end if;

  effective_law_firm_id := request_row.law_firm_id;

  if effective_law_firm_id is null and request_row.lawyer_id is not null then
    select lfm.law_firm_id
    into effective_law_firm_id
    from public.law_firm_members lfm
    where lfm.profile_id = request_row.lawyer_id
      and lfm.status = 'active'
    order by case lfm.member_role
      when 'owner' then 1
      when 'admin' then 2
      when 'lawyer' then 3
      else 4
    end,
    lfm.created_at
    limit 1;

    if effective_law_firm_id is not null then
      update public.case_requests
      set law_firm_id = effective_law_firm_id
      where id = request_id_value;
    end if;
  end if;

  select coalesce(full_name, 'Cliente')
  into client_name_value
  from public.profiles
  where id = request_row.client_id;

  select coalesce(full_name, 'Advogado')
  into lawyer_name_value
  from public.profiles
  where id = request_row.lawyer_id;

  if not accepted_value then
    response_status := 'declined';

    update public.case_requests
    set status = response_status,
        responded_at = now()
    where id = request_id_value;

    perform public.sync_case_request_action_surfaces(
      request_id_value,
      response_status,
      null
    );

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

    insert into public.notifications (
      recipient_profile_id,
      actor_profile_id,
      law_firm_id,
      type,
      title,
      body,
      metadata
    )
    select distinct recipient_id,
      auth.uid(),
      effective_law_firm_id,
      'case_request_response',
      'Solicitação recusada',
      coalesce(client_name_value, 'Cliente') || ' recusou o caso "' || request_row.title || '".',
      jsonb_build_object(
        'case_request_id', request_row.id,
        'request_status', 'declined',
        'conversation_id', request_row.conversation_id,
        'title', request_row.title,
        'area', request_row.area
      )
    from (
      values (request_row.lawyer_id), (request_row.requested_by_profile_id)
    ) as recipients(recipient_id)
    where recipient_id is not null
      and recipient_id <> auth.uid();

    return null;
  end if;

  response_status := 'accepted';

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
    effective_law_firm_id,
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
  set status = response_status,
      legal_case_id = case_id_value,
      responded_at = now()
  where id = request_id_value;

  perform public.sync_case_request_action_surfaces(
    request_id_value,
    response_status,
    case_id_value
  );

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

  insert into public.notifications (
    recipient_profile_id,
    actor_profile_id,
    law_firm_id,
    type,
    title,
    body,
    metadata
  )
  select distinct recipient_id,
    auth.uid(),
    effective_law_firm_id,
    'case_request_response',
    'Caso aceito',
    coalesce(client_name_value, 'Cliente') || ' aceitou o caso "' || request_row.title || '".',
    jsonb_build_object(
      'case_request_id', request_row.id,
      'request_status', 'accepted',
      'conversation_id', request_row.conversation_id,
      'legal_case_id', case_id_value,
      'title', request_row.title,
      'area', request_row.area
    )
  from (
    values (request_row.lawyer_id), (request_row.requested_by_profile_id)
  ) as recipients(recipient_id)
  where recipient_id is not null
    and recipient_id <> auth.uid();

  if effective_law_firm_id is not null then
    insert into public.notifications (
      recipient_profile_id,
      actor_profile_id,
      law_firm_id,
      type,
      title,
      body,
      metadata
    )
    select distinct
      lfm.profile_id,
      request_row.client_id,
      effective_law_firm_id,
      'firm_case_started',
      'Novo caso no escritório',
      coalesce(lawyer_name_value, 'Advogado') || ' iniciou um novo caso com ' || coalesce(client_name_value, 'Cliente') || '.',
      jsonb_build_object(
        'case_id', case_id_value,
        'case_request_id', request_row.id,
        'request_status', 'accepted',
        'conversation_id', request_row.conversation_id,
        'law_firm_id', effective_law_firm_id,
        'title', request_row.title,
        'area', request_row.area
      )
    from public.law_firm_members lfm
    where lfm.law_firm_id = effective_law_firm_id
      and lfm.profile_id is not null
      and lfm.status = 'active'
      and lfm.member_role in ('owner', 'admin', 'secretary');
  end if;

  return case_id_value;
end;
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
  select
    lc.id,
    lc.title,
    coalesce(client_profile.full_name, 'Cliente') as client_name,
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

revoke all on function public.sync_case_request_action_surfaces(
  uuid,
  public.case_request_status,
  uuid
) from public, anon, authenticated;

revoke all on function public.create_case_request(uuid, text, text, text)
from public, anon, authenticated;

revoke all on function public.respond_to_case_request(uuid, boolean)
from public, anon, authenticated;

revoke all on function public.fetch_lawyer_cases()
from public, anon, authenticated;

grant execute on function public.create_case_request(uuid, text, text, text)
to authenticated;

grant execute on function public.respond_to_case_request(uuid, boolean)
to authenticated;

grant execute on function public.fetch_lawyer_cases()
to authenticated;
