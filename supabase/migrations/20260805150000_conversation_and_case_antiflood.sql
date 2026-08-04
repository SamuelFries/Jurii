-- Antiflood nas portas de entrada do fluxo cliente<->profissional.
--
-- So report_conversation e invite_verified_lawyer_to_law_firm tinham limite.
-- Abrir conversa e propor caso — as duas portas que a fraude de avaliacao
-- percorre, e as duas que um script usaria para spam — nao tinham teto.
--
-- Limites folgados de proposito: 20 conversas novas por dia por cliente e 30
-- propostas de caso por dia por advogado estao muito acima do uso legitimo
-- (o mais ativo hoje tem 17 conversas no total) e ainda assim tiram o abuso
-- em escala do terreno do "de graca".
--
-- O advisory lock serializa por usuario: sem ele, chamadas concorrentes
-- passam todas pelo count antes de qualquer insert aparecer. Mesmo padrao
-- ja usado em report_conversation.
--
-- Corpos extraidos VERBATIM do banco (pg_get_functiondef) com substituicao
-- por script e assert de ocorrencia unica.

CREATE OR REPLACE FUNCTION public.start_or_get_lawyer_conversation(lawyer_profile_id_value uuid, initial_message_value text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  lawyer_row public.lawyer_profiles%rowtype;
  profile_row public.profiles%rowtype;
  conversation_id_value uuid;
  clean_message text;
  firm_id_value uuid;
  firm_joined_at_value timestamptz;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  -- Antiflood: serializa por usuário (sem o lock, chamadas concorrentes
  -- passam todas pelo count antes de qualquer insert aparecer) e limita a
  -- 20 por 1 day. Mesmo padrão de report_conversation.
  perform pg_advisory_xact_lock(
    hashtext('conversations_started:' || auth.uid()::text)
  );

  if (
    select count(*)
    from public.conversations t
    where t.client_id = auth.uid()
      and t.created_at > now() - interval '1 day'
  ) >= 20 then
    raise exception 'Too many conversations started';
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

  select
    lfm.law_firm_id,
    coalesce(lfm.joined_at, lfm.created_at, now())
  into firm_id_value, firm_joined_at_value
  from public.law_firm_members lfm
  where coalesce(lfm.lawyer_id, lfm.profile_id) = lawyer_profile_id_value
    and lfm.status = 'active'
    and 'lawyer' = any(lfm.roles)
    and coalesce(
      lfm.lawyer_invite_status,
      'active'::public.law_firm_member_status
    ) = 'active'
  order by
    case
      when 'owner' = any(lfm.roles) then 1
      when 'admin' = any(lfm.roles) then 2
      else 3
    end,
    coalesce(lfm.joined_at, lfm.created_at, now()) desc
  limit 1;

  select id
  into conversation_id_value
  from public.conversations
  where client_id = auth.uid()
    and lawyer_id = lawyer_profile_id_value
    and type = 'client_firm'
    and (
      (
        firm_id_value is not null
        and law_firm_id = firm_id_value
      )
      or (
        firm_id_value is not null
        and law_firm_id is null
        and created_at >= firm_joined_at_value
      )
      or (
        firm_id_value is null
        and law_firm_id is null
      )
    )
  order by
    case when law_firm_id = firm_id_value then 0 else 1 end,
    updated_at desc
  limit 1;

  if conversation_id_value is null then
    insert into public.conversations (
      type,
      client_id,
      lawyer_id,
      law_firm_id,
      title,
      specialty,
      last_message,
      last_message_at
    )
    values (
      'client_firm',
      auth.uid(),
      lawyer_profile_id_value,
      firm_id_value,
      profile_row.full_name,
      lawyer_row.primary_area,
      'Conversa iniciada.',
      now()
    )
    returning id into conversation_id_value;
  elsif firm_id_value is not null then
    update public.conversations
    set
      law_firm_id = firm_id_value,
      updated_at = now()
    where id = conversation_id_value
      and law_firm_id is null;
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
$function$;


CREATE OR REPLACE FUNCTION public.start_or_get_law_firm_conversation(law_firm_id_value uuid, initial_message_value text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  firm_row public.law_firms%rowtype;
  conversation_id_value uuid;
  clean_message text;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  -- Antiflood: serializa por usuário (sem o lock, chamadas concorrentes
  -- passam todas pelo count antes de qualquer insert aparecer) e limita a
  -- 20 por 1 day. Mesmo padrão de report_conversation.
  perform pg_advisory_xact_lock(
    hashtext('conversations_started:' || auth.uid()::text)
  );

  if (
    select count(*)
    from public.conversations t
    where t.client_id = auth.uid()
      and t.created_at > now() - interval '1 day'
  ) >= 20 then
    raise exception 'Too many conversations started';
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
$function$;


CREATE OR REPLACE FUNCTION public.create_case_request(conversation_id_value uuid, title_value text, area_value text, summary_value text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  -- Antiflood: serializa por usuário (sem o lock, chamadas concorrentes
  -- passam todas pelo count antes de qualquer insert aparecer) e limita a
  -- 30 por 1 day. Mesmo padrão de report_conversation.
  perform pg_advisory_xact_lock(
    hashtext('case_requests_created:' || auth.uid()::text)
  );

  if (
    select count(*)
    from public.case_requests t
    where t.lawyer_id = auth.uid()
      and t.created_at > now() - interval '1 day'
  ) >= 30 then
    raise exception 'Too many case proposals';
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

  -- Só o advogado responsável pela conversa propõe caso. O escritório perdeu
  -- essa capacidade: agora ele sugere um advogado da organização
  -- (recommend_lawyer_to_client) e o caso nasce na conversa com esse advogado.
  if conversation_row.lawyer_id is null
    or conversation_row.lawyer_id <> auth.uid() then
    raise exception 'Only the responsible lawyer can request case acceptance';
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
$function$;

notify pgrst, 'reload schema';
