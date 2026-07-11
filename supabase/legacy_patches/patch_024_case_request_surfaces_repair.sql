-- Repairs and hardens client-facing case request surfaces.
--
-- Run after patch_023 if a lawyer can create a case request but the client
-- does not see a notification or an actionable card in chat.

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

create or replace function public.ensure_case_request_client_surfaces(
  request_id_value uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  request_row public.case_requests%rowtype;
  actor_name text;
  actor_initials text;
  firm_name text;
  firm_initials text;
  sender_id_value uuid;
  message_id_value uuid;
  notification_id_value uuid;
  status_value text;
  message_body text;
  notification_title text;
  notification_body text;
  metadata_value jsonb;
begin
  select *
  into request_row
  from public.case_requests
  where id = request_id_value;

  if not found then
    return;
  end if;

  select full_name, initials
  into actor_name, actor_initials
  from public.profiles
  where id = coalesce(request_row.requested_by_profile_id, request_row.lawyer_id);

  select name, initials
  into firm_name, firm_initials
  from public.law_firms
  where id = request_row.law_firm_id;

  sender_id_value := coalesce(
    request_row.requested_by_profile_id,
    request_row.lawyer_id,
    request_row.client_id
  );

  status_value := request_row.status::text;

  metadata_value := jsonb_strip_nulls(jsonb_build_object(
    'type', 'case_request',
    'case_request_id', request_row.id,
    'request_status', status_value,
    'conversation_id', request_row.conversation_id,
    'legal_case_id', request_row.legal_case_id,
    'title', request_row.title,
    'area', request_row.area
  ));

  message_body := case request_row.status
    when 'accepted' then 'Caso aceito: ' || request_row.title
    when 'declined' then 'Caso recusado: ' || request_row.title
    when 'cancelled' then 'Solicitação cancelada: ' || request_row.title
    else 'Solicitação de aceite do caso: ' || request_row.title
  end;

  notification_title := case request_row.status
    when 'accepted' then 'Caso aceito'
    when 'declined' then 'Caso recusado'
    when 'cancelled' then 'Solicitação cancelada'
    else 'Solicitação de caso'
  end;

  notification_body := case request_row.status
    when 'accepted' then 'Você aceitou o caso "' || request_row.title || '".'
    when 'declined' then 'Você recusou o caso "' || request_row.title || '".'
    when 'cancelled' then 'A solicitação do caso "' || request_row.title || '" foi cancelada.'
    else coalesce(firm_name, actor_name, 'Jurii') || ' pediu seu aceite para o caso "' || request_row.title || '".'
  end;

  if request_row.message_id is null then
    insert into public.messages (
      conversation_id,
      sender_id,
      sender_type,
      body,
      metadata
    )
    values (
      request_row.conversation_id,
      sender_id_value,
      'system',
      message_body,
      metadata_value
    )
    returning id into message_id_value;
  else
    update public.messages
    set body = message_body,
        metadata = metadata_value
    where id = request_row.message_id
    returning id into message_id_value;
  end if;

  if request_row.notification_id is null and request_row.status = 'pending' then
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
      request_row.client_id,
      sender_id_value,
      request_row.law_firm_id,
      'case_request',
      notification_title,
      notification_body,
      metadata_value
    )
    returning id into notification_id_value;
  elsif request_row.notification_id is not null then
    update public.notifications
    set title = notification_title,
        body = notification_body,
        metadata = metadata_value,
        read_at = case
          when request_row.status = 'pending' then null
          else coalesce(read_at, now())
        end
    where id = request_row.notification_id
    returning id into notification_id_value;
  end if;

  if message_id_value is not null
      and message_id_value is distinct from request_row.message_id then
    update public.case_requests
    set message_id = message_id_value
    where id = request_row.id;
  end if;

  if notification_id_value is not null
      and notification_id_value is distinct from request_row.notification_id then
    update public.case_requests
    set notification_id = notification_id_value
    where id = request_row.id;
  end if;
end;
$$;

create or replace function public.case_requests_ensure_client_surfaces()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if pg_trigger_depth() > 1 then
    return new;
  end if;

  perform public.ensure_case_request_client_surfaces(new.id);
  return new;
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
    order by case lfm.member_role
      when 'owner' then 1
      when 'admin' then 2
      when 'lawyer' then 3
      else 4
    end,
    coalesce(lfm.created_at, lfm.joined_at)
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
  end if;

  perform public.ensure_case_request_client_surfaces(request_id_value);

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
    coalesce(lfm.created_at, lfm.joined_at)
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

    perform public.ensure_case_request_client_surfaces(request_id_value);

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

  perform public.ensure_case_request_client_surfaces(request_id_value);

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

drop trigger if exists case_requests_ensure_client_surfaces on public.case_requests;
create trigger case_requests_ensure_client_surfaces
after insert or update of title, area, status, legal_case_id, message_id, notification_id
on public.case_requests
for each row execute function public.case_requests_ensure_client_surfaces();

do $$
declare
  request_record record;
begin
  for request_record in
    select id
    from public.case_requests
    where status = 'pending'
       or message_id is null
       or notification_id is null
  loop
    perform public.ensure_case_request_client_surfaces(request_record.id);
  end loop;
end $$;

revoke all on function public.ensure_case_request_client_surfaces(uuid)
from public, anon, authenticated;

revoke all on function public.case_requests_ensure_client_surfaces()
from public, anon, authenticated;

revoke all on function public.create_case_request(uuid, text, text, text)
from public, anon, authenticated;

revoke all on function public.respond_to_case_request(uuid, boolean)
from public, anon, authenticated;

grant execute on function public.create_case_request(uuid, text, text, text)
to authenticated;

grant execute on function public.respond_to_case_request(uuid, boolean)
to authenticated;

notify pgrst, 'reload schema';
