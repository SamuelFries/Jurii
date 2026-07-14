-- Sugestão de advogado pelo escritório (substitui a proposta de caso do escritório)
--
-- Mudança de fluxo:
--   ANTES: o escritório podia propor um caso ao cliente pelo chat (o cliente
--          aceitava e o caso nascia com law_firm_id, sem advogado definido).
--   AGORA: o escritório sugere um advogado da organização. O cliente fala com
--          esse advogado e é ELE quem propõe o caso — o caso já nasce com
--          advogado responsável (e mantém o law_firm_id do escritório dele,
--          derivado do vínculo, então painel e avaliações do escritório seguem
--          funcionando).
--
-- Conteúdo:
--   1. create_case_request: só o advogado da conversa propõe (escritório barrado
--      no banco, não só na UI).
--   2. can_recommend_law_firm_lawyer: quem fala pelo escritório (owner, admin,
--      advogado ou secretaria — estagiário não).
--   3. fetch_law_firm_lawyers: advogados ativos e aprovados do escritório, para
--      a folha de escolha.
--   4. recommend_lawyer_to_client: grava a sugestão como mensagem de sistema na
--      conversa (metadata com o snapshot do advogado) e notifica o cliente.
--
-- Aditiva: nenhuma tabela nova, nenhuma coluna nova. A sugestão vive na
-- metadata da mensagem — ela não tem máquina de estados como case_requests
-- (não há aceite/recusa), o card é só um atalho para conversar.

-- ---------------------------------------------------------------------------
-- 1. create_case_request: escritório não propõe mais caso
-- ---------------------------------------------------------------------------

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
$$;

revoke all on function public.create_case_request(uuid, text, text, text)
from public, anon;

grant execute on function public.create_case_request(uuid, text, text, text)
to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Quem pode sugerir advogado pelo escritório
--
-- Mesmo conjunto do gate da UI (canRecommendFirmLawyers): dono, admin,
-- advogado e secretaria. Estagiário não fala pelo escritório com o cliente.
-- ---------------------------------------------------------------------------

create or replace function public.can_recommend_law_firm_lawyer(
  law_firm_id_value uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.law_firm_members lfm
    where lfm.law_firm_id = law_firm_id_value
      and lfm.profile_id = auth.uid()
      and lfm.status = 'active'
      and lfm.roles && array['owner', 'admin', 'lawyer', 'secretary']::text[]
  )
  or exists (
    select 1
    from public.law_firm_verifications lfv
    where lfv.law_firm_id = law_firm_id_value
      and lfv.owner_profile_id = auth.uid()
      and lfv.status = 'approved'
  );
$$;

-- ---------------------------------------------------------------------------
-- 3. Advogados do escritório disponíveis para sugestão
--
-- Só entram advogados que o cliente consegue de fato acionar:
-- vínculo ativo, convite aceito e cadastro aprovado — as mesmas condições que
-- start_or_get_lawyer_conversation exige. Sugerir alguém que não passa nesse
-- filtro geraria um card com botão quebrado.
-- ---------------------------------------------------------------------------

create or replace function public.fetch_law_firm_lawyers(
  law_firm_id_value uuid
)
returns table (
  id uuid,
  full_name text,
  initials text,
  oab_number text,
  oab_state text,
  primary_area text,
  practice_areas text[],
  avatar_url text,
  is_available boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    lp.id,
    coalesce(p.full_name, 'Advogado') as full_name,
    coalesce(p.initials, 'AJ') as initials,
    lp.oab_number,
    lp.oab_state::text as oab_state,
    lp.primary_area,
    lp.practice_areas,
    p.avatar_url,
    lp.is_available
  from public.law_firm_members lfm
  join public.lawyer_profiles lp
    on lp.id = coalesce(lfm.lawyer_id, lfm.profile_id)
  join public.profiles p
    on p.id = lp.id
  where lfm.law_firm_id = law_firm_id_value
    and lfm.status = 'active'
    and 'lawyer' = any(lfm.roles)
    and coalesce(
      lfm.lawyer_invite_status,
      'active'::public.law_firm_member_status
    ) = 'active'
    and p.lawyer_status = 'approved'
    and p.deleted_at is null
    and public.can_recommend_law_firm_lawyer(law_firm_id_value)
  order by lp.is_available desc, coalesce(p.full_name, '');
$$;

-- ---------------------------------------------------------------------------
-- 4. Sugerir advogado ao cliente
--
-- A sugestão é uma mensagem de sistema na conversa cliente↔escritório. O nome,
-- a OAB e a foto vão num snapshot dentro da metadata (lidos aqui no servidor,
-- nunca vindos do cliente) — o card do chat renderiza direto, sem consulta
-- extra por mensagem. O lawyer_id é o que vale para abrir a conversa, e
-- start_or_get_lawyer_conversation revalida o advogado no clique.
-- ---------------------------------------------------------------------------

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

  return message_id_value;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Grants
-- ---------------------------------------------------------------------------

revoke all on function public.can_recommend_law_firm_lawyer(uuid)
from public, anon;

revoke all on function public.fetch_law_firm_lawyers(uuid)
from public, anon;

revoke all on function public.recommend_lawyer_to_client(uuid, uuid, text)
from public, anon;

grant execute on function public.can_recommend_law_firm_lawyer(uuid)
to authenticated;

grant execute on function public.fetch_law_firm_lawyers(uuid)
to authenticated;

grant execute on function public.recommend_lawyer_to_client(uuid, uuid, text)
to authenticated;

notify pgrst, 'reload schema';
