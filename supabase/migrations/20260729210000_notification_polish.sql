-- Polimento do sistema de notificacoes
--
-- Quatro frentes, todas de higiene do que ja existe:
--
--   1. BUG do fan-out do escritorio: a notificacao 'firm_case_started'
--      escolhia os destinatarios por `member_role` (papel PRIMARIO singular,
--      derivado por precedencia owner>admin>lawyer>secretary>intern), enquanto
--      todo o resto do sistema decide permissao pelo ARRAY `roles`
--      (is_active_law_firm_case_manager usa `roles && array[...]`). Efeito:
--      um membro ['lawyer','secretary'] tem member_role='lawyer' e NAO era
--      avisado de caso novo, embora possa gerenciar casos. Corpo VERBATIM da
--      definicao vigente (baseline 20260711190000:5204), extraido
--      programaticamente; muda so o predicado do fan-out.
--
--   2. Token de push morto: a Edge Function send-push agora detecta
--      UNREGISTERED/INVALID_ARGUMENT do FCM e apaga o token. Sem uma RPC
--      service_role isso era impossivel (unregister_push_token exige
--      auth.uid()), entao o app acumulava tokens mortos para sempre — cada
--      notificacao futura tentava entregar em todos eles.
--
--   3. Teto defensivo em fetch_push_tokens_for_recipient: sem limite, um
--      usuario com muitas reinstalacoes acumulava fan-out ilimitado de HTTP
--      por notificacao. Mantem os mais recentes.
--
--   4. Retencao: a tabela notifications crescia para sempre (nenhum delete
--      alem do swipe do usuario). Job diario apaga so o que ja foi LIDO ha
--      mais de 90 dias; nao-lida nunca e apagada.

-- ---------------------------------------------------------------------------
-- 1. Fan-out do escritorio pelo array de papeis
-- ---------------------------------------------------------------------------

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
      and lfm.roles && array['owner', 'admin', 'secretary']::text[];
  end if;

  return case_id_value;
end;
$$;

revoke all on function public.respond_to_case_request(uuid, boolean)
  from public, anon;
grant execute on function public.respond_to_case_request(uuid, boolean)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Remocao de token de push morto (so o servidor de push chama)
-- ---------------------------------------------------------------------------

create or replace function public.delete_push_token_by_value(token_value text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  removed integer;
begin
  delete from public.push_tokens
  where token = token_value;

  get diagnostics removed = row_count;
  return removed;
end;
$$;

revoke all on function public.delete_push_token_by_value(text)
  from public, anon, authenticated;
grant execute on function public.delete_push_token_by_value(text)
  to service_role;

-- ---------------------------------------------------------------------------
-- 3. Teto defensivo na leitura de tokens (mais recentes primeiro)
--    Corpo verbatim da 20260718120000:102, so com order by + limit.
-- ---------------------------------------------------------------------------

create or replace function public.fetch_push_tokens_for_recipient(
  recipient_id uuid
)
returns table (
  token text,
  platform text
)
language sql
stable
security definer
set search_path = public
as $$
  select pt.token, pt.platform
  from public.push_tokens pt
  where pt.profile_id = recipient_id
  order by pt.updated_at desc
  limit 20;
$$;

revoke all on function public.fetch_push_tokens_for_recipient(uuid)
  from public, anon, authenticated;
grant execute on function public.fetch_push_tokens_for_recipient(uuid)
  to service_role;

-- ---------------------------------------------------------------------------
-- 4. Retencao: so notificacao LIDA e antiga; nao-lida nunca e apagada
-- ---------------------------------------------------------------------------

create index if not exists notifications_read_at_idx
  on public.notifications(read_at)
  where read_at is not null;

create or replace function public.purge_old_notifications(
  older_than interval default interval '90 days'
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  removed integer;
begin
  delete from public.notifications
  where read_at is not null
    and read_at < now() - older_than;

  get diagnostics removed = row_count;
  return removed;
end;
$$;

revoke all on function public.purge_old_notifications(interval)
  from public, anon, authenticated;

-- cron.schedule faz upsert por nome: reaplicar a migration nao duplica o job.
create extension if not exists pg_cron;

select cron.schedule(
  'purge-old-notifications',
  '23 4 * * *',
  $cron$select public.purge_old_notifications();$cron$
);

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Verificacao pos-push (SQL Editor):
--   select prosrc like '%roles && array%' from pg_proc
--   where proname = 'respond_to_case_request';                    -- true
--   select jobname from cron.job where jobname='purge-old-notifications';
--   select public.purge_old_notifications(interval '999 years');  -- 0 esperado
-- ---------------------------------------------------------------------------
