-- Auto-indicação também notifica o advogado
--
-- A versão anterior (20260714180000) pulava o aviso quando quem sugeria era o
-- próprio advogado indicado, para não gerar eco. Na prática isso barra o caso
-- COMUM: escritório de dois sócios, onde o próprio advogado opera o chat e se
-- indica ao cliente. Decisão do Samuel (14/07): notificar sempre.
--
-- O aviso deixa de ser "alguém te indicou" e passa a ser o registro de que o
-- advogado foi colocado na frente de um cliente em potencial — útil mesmo
-- quando ele mesmo fez a indicação.

create or replace function public.recommend_lawyer_to_client(
  conversation_id_value uuid,
  lawyer_profile_id_value uuid,
  note_value text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  conversation_row public.conversations%rowtype;
  lawyer_name text;
  lawyer_initials text;
  lawyer_avatar_url text;
  lawyer_oab_number text;
  lawyer_oab_state text;
  lawyer_primary_area text;
  firm_name text;
  clean_note text;
  message_id_value uuid;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  select *
  into conversation_row
  from public.conversations
  where id = conversation_id_value;

  if not found then
    raise exception 'Conversation not found';
  end if;

  if conversation_row.law_firm_id is null then
    raise exception 'Conversation does not belong to a law firm';
  end if;

  -- Sugestão é para cliente. O chat interno da equipe também tem law_firm_id
  -- (e um client_id qualquer), então sem esta guarda a RPC aceitaria virar
  -- mensagem no chat da equipe.
  if conversation_row.type = 'firm_internal' then
    raise exception 'Cannot recommend a lawyer in an internal conversation';
  end if;

  if not public.can_recommend_law_firm_lawyer(conversation_row.law_firm_id) then
    raise exception 'Only the office team can recommend a lawyer';
  end if;

  select
    coalesce(p.full_name, 'Advogado'),
    coalesce(p.initials, 'AJ'),
    p.avatar_url,
    lp.oab_number,
    lp.oab_state::text,
    lp.primary_area
  into
    lawyer_name,
    lawyer_initials,
    lawyer_avatar_url,
    lawyer_oab_number,
    lawyer_oab_state,
    lawyer_primary_area
  from public.law_firm_members lfm
  join public.lawyer_profiles lp
    on lp.id = coalesce(lfm.lawyer_id, lfm.profile_id)
  join public.profiles p
    on p.id = lp.id
  where lfm.law_firm_id = conversation_row.law_firm_id
    and lp.id = lawyer_profile_id_value
    and lfm.status = 'active'
    and 'lawyer' = any(lfm.roles)
    and coalesce(
      lfm.lawyer_invite_status,
      'active'::public.law_firm_member_status
    ) = 'active'
    and p.lawyer_status = 'approved'
    and p.deleted_at is null
  limit 1;

  if lawyer_name is null then
    raise exception 'Lawyer is not an active member of this office';
  end if;

  select name
  into firm_name
  from public.law_firms
  where id = conversation_row.law_firm_id;

  clean_note := nullif(trim(coalesce(note_value, '')), '');

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
    'Advogado sugerido: ' || lawyer_name,
    jsonb_strip_nulls(jsonb_build_object(
      'type', 'lawyer_recommendation',
      'lawyer_id', lawyer_profile_id_value,
      'lawyer_name', lawyer_name,
      'lawyer_initials', lawyer_initials,
      'avatar_url', lawyer_avatar_url,
      'oab_label', 'OAB/' || lawyer_oab_state || ' ' || lawyer_oab_number,
      'primary_area', lawyer_primary_area,
      'law_firm_id', conversation_row.law_firm_id,
      'note', clean_note
    ))
  )
  returning id into message_id_value;

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
    conversation_row.law_firm_id,
    'lawyer_recommendation',
    'Advogado sugerido',
    coalesce(firm_name, 'O escritório') || ' sugeriu ' || lawyer_name || ' para o seu atendimento.',
    jsonb_build_object(
      'conversation_id', conversation_row.id,
      'lawyer_id', lawyer_profile_id_value,
      'message_id', message_id_value
    )
  );

  -- O advogado indicado sempre é avisado, INCLUSIVE quando ele mesmo se indicou
  -- (escritório de dois sócios se indicando é fluxo normal, não exceção — e o
  -- aviso vira o registro de que ele foi posto na frente de um cliente).
  -- Sem o nome do cliente: ele ainda não é cliente deste advogado, e o contato
  -- pode nunca acontecer.
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
    lawyer_profile_id_value,
    auth.uid(),
    conversation_row.law_firm_id,
    'lawyer_recommended',
    'Você foi recomendado',
    coalesce(firm_name, 'O escritório')
      || ' recomendou você para um cliente em potencial.',
    jsonb_build_object(
      'law_firm_id', conversation_row.law_firm_id,
      'message_id', message_id_value
    )
  );

  return message_id_value;
end;
$$;

notify pgrst, 'reload schema';
