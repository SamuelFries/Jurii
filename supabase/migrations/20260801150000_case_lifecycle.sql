-- Ciclo de vida do caso: encerrar, reabrir, prazo gravável e convite de
-- avaliação — a máquina de estados que existia inteira no banco e nunca era
-- usada (nenhum caminho escrevia status <> 'open' nem deadline_at).
--
-- Decisões:
-- - Encerra/reabre quem responde pelo caso: o advogado responsável
--   (can_manage_case_updates) ou gestor ativo do escritório do caso — o
--   mesmo portão do fetch_case_for_current_user (20260730180000).
-- - Encerrar convida o cliente a avaliar (tipo novo 'case_closed', escopo
--   client declarado em infer_notification_scope — o sino filtra por escopo
--   derivado do tipo, reusar tipo de outro escopo esconderia o aviso).
-- - Prazo (deadline_at) é ferramenta do profissional: gravável pelo mesmo
--   portão, sem notificação. Preenchê-lo acorda o needs_cnj_number (o
--   empurrão "Sem nº do processo" do andamento processual) e o indicador de
--   urgência do painel do escritório, que agora deriva do PRAZO REAL
--   (<= 7 dias), não do status 'deadline' que nada escrevia.
-- - Os corpos das fetch_* abaixo são VERBATIM das definições vigentes
--   (pg_get_functiondef no banco local que espelha as migrations), com
--   apenas as colunas novas — o retorno muda, então é drop + create.

-- ---------------------------------------------------------------------------
-- 1. Encerrar / reabrir
-- ---------------------------------------------------------------------------

create or replace function public.close_legal_case(case_id_value uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  case_row public.legal_cases%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  -- for update: sem o lock, duas chamadas concorrentes (retry de rede,
  -- dois gestores) passam ambas no guard e duplicam timeline e convite.
  select * into case_row
  from public.legal_cases
  where id = case_id_value
  for update;
  if not found then
    raise exception 'Case not found';
  end if;

  if not (
    public.can_manage_case_updates(case_id_value)
    or (
      case_row.law_firm_id is not null
      and public.is_active_law_firm_case_manager(case_row.law_firm_id)
    )
  ) then
    raise exception 'Only the responsible lawyer or firm managers can close a case';
  end if;

  -- Idempotente: encerrar o já encerrado não duplica timeline nem aviso.
  if case_row.status = 'closed' then
    return;
  end if;

  update public.legal_cases
  set status = 'closed',
      last_update_label = 'Encerrado',
      updated_at = now()
  where id = case_id_value;

  insert into public.case_updates (case_id, author_profile_id, title, body)
  values (case_id_value, auth.uid(), 'Caso encerrado',
          'O responsável encerrou este caso.');

  -- Convite de avaliação. Texto neutro, sem ecoar título (entrada de
  -- usuário não viaja em push).
  insert into public.notifications
    (recipient_profile_id, actor_profile_id, type, title, body, metadata, scope)
  values (
    case_row.client_id,
    auth.uid(),
    'case_closed',
    'Caso encerrado',
    'Seu caso foi encerrado. Como foi sua experiência? '
      || 'Toque para ver o caso e avaliar o atendimento.',
    jsonb_build_object('case_id', case_id_value),
    public.infer_notification_scope('case_closed', 'client')
  );
end;
$$;

create or replace function public.reopen_legal_case(case_id_value uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  case_row public.legal_cases%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  -- for update: sem o lock, duas chamadas concorrentes (retry de rede,
  -- dois gestores) passam ambas no guard e duplicam timeline e convite.
  select * into case_row
  from public.legal_cases
  where id = case_id_value
  for update;
  if not found then
    raise exception 'Case not found';
  end if;

  if not (
    public.can_manage_case_updates(case_id_value)
    or (
      case_row.law_firm_id is not null
      and public.is_active_law_firm_case_manager(case_row.law_firm_id)
    )
  ) then
    raise exception 'Only the responsible lawyer or firm managers can reopen a case';
  end if;

  if case_row.status <> 'closed' then
    return;
  end if;

  update public.legal_cases
  set status = 'open',
      last_update_label = 'Caso reaberto',
      updated_at = now()
  where id = case_id_value;

  insert into public.case_updates (case_id, author_profile_id, title, body)
  values (case_id_value, auth.uid(), 'Caso reaberto',
          'O responsável reabriu este caso.');

  insert into public.notifications
    (recipient_profile_id, actor_profile_id, type, title, body, metadata, scope)
  values (
    case_row.client_id,
    auth.uid(),
    'case_update',
    'Caso reaberto',
    'Seu caso voltou a ficar em andamento.',
    jsonb_build_object('case_id', case_id_value),
    public.infer_notification_scope('case_update', 'client')
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Prazo gravável
-- ---------------------------------------------------------------------------

create or replace function public.set_case_deadline(
  case_id_value uuid,
  deadline_value timestamptz
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  case_row public.legal_cases%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  -- for update: sem o lock, duas chamadas concorrentes (retry de rede,
  -- dois gestores) passam ambas no guard e duplicam timeline e convite.
  select * into case_row
  from public.legal_cases
  where id = case_id_value
  for update;
  if not found then
    raise exception 'Case not found';
  end if;

  if not (
    public.can_manage_case_updates(case_id_value)
    or (
      case_row.law_firm_id is not null
      and public.is_active_law_firm_case_manager(case_row.law_firm_id)
    )
  ) then
    raise exception 'Only the responsible lawyer or firm managers can set the deadline';
  end if;

  if case_row.status = 'closed' then
    raise exception 'Case is closed';
  end if;

  update public.legal_cases
  set deadline_at = deadline_value,
      updated_at = now()
  where id = case_id_value;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Escopo do tipo novo (o sino filtra por escopo derivado do tipo)
-- ---------------------------------------------------------------------------

create or replace function public.infer_notification_scope(
  type_value text,
  current_scope notification_scope default null
)
returns notification_scope
language sql
immutable
set search_path = public
as $$
  select case
    when type_value in (
      'team_invite',
      'case_request_response',
      'lawyer_recommended',
      'appointment_reminder'
    ) then 'lawyer'::public.notification_scope
    when type_value in ('firm_case_started') then 'firm'::public.notification_scope
    when type_value in (
      'case_request',
      'message',
      'case_update',
      'case_closed',
      'lawyer_recommendation'
    ) then 'client'::public.notification_scope
    else coalesce(current_scope, 'client'::public.notification_scope)
  end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Leituras: description/status/prazo no detalhe; deadline_at nas listas;
--    urgência do painel derivada do prazo real
-- ---------------------------------------------------------------------------

drop function if exists public.fetch_case_for_current_user(uuid);

create function public.fetch_case_for_current_user(case_id_value uuid)
 RETURNS TABLE(id uuid, title text, area text, status_label text, client_name text, cnj_number text, description text, status text, deadline_at timestamp with time zone, created_at timestamp with time zone, assigned_lawyer_id uuid, law_firm_id uuid, viewer_is_client boolean, can_manage boolean, can_manage_lifecycle boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    lc.id,
    lc.title,
    lc.area,
    public.case_status_label(lc.status) as status_label,
    public.profile_display_name(
      client_profile.full_name,
      client_profile.deleted_at,
      client_profile.deleted_display_name
    ) as client_name,
    lc.cnj_number,
    lc.description,
    lc.status::text as status,
    lc.deadline_at,
    lc.created_at,
    lc.assigned_lawyer_id,
    lc.law_firm_id,
    lc.client_id = auth.uid() as viewer_is_client,
    public.can_manage_case_updates(lc.id) as can_manage,
    -- Espelha o gate de escrita de close/reopen/set_case_deadline: sem
    -- isto o gestor do escritório nunca veria os controles que o
    -- servidor permite a ele usar.
    (
      public.can_manage_case_updates(lc.id)
      or (
        lc.law_firm_id is not null
        and public.is_active_law_firm_case_manager(lc.law_firm_id)
      )
    ) as can_manage_lifecycle
  from public.legal_cases lc
  left join public.profiles client_profile
    on client_profile.id = lc.client_id
  where lc.id = case_id_value
    and (
      public.can_access_case(case_id_value)
      or (
        lc.law_firm_id is not null
        and public.is_active_law_firm_case_manager(lc.law_firm_id)
      )
    );
$function$;

drop function if exists public.fetch_client_cases();

create function public.fetch_client_cases()
 RETURNS TABLE(id uuid, title text, area text, status text, status_label text, last_update_label text, cnj_number text, deadline_at timestamp with time zone, updated_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    lc.id,
    lc.title,
    lc.area,
    lc.status::text as status,
    public.case_status_label(lc.status) as status_label,
    coalesce(lc.last_update_label, 'Atualizado hoje') as last_update_label,
    lc.cnj_number,
    lc.deadline_at,
    lc.updated_at
  from public.legal_cases lc
  where lc.client_id = auth.uid()
  order by lc.updated_at desc;
$function$;

drop function if exists public.fetch_lawyer_cases();

create function public.fetch_lawyer_cases()
 RETURNS TABLE(id uuid, title text, client_name text, client_initials text, area text, last_update_label text, status text, cnj_number text, needs_cnj_number boolean, deadline_at timestamp with time zone, updated_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    lc.cnj_number,
    (lc.deadline_at is not null and lc.cnj_number is null) as needs_cnj_number,
    lc.deadline_at,
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
$function$;

drop function if exists public.fetch_law_firm_cases(uuid);

create function public.fetch_law_firm_cases(law_firm_id_value uuid)
 RETURNS TABLE(id uuid, title text, client_name text, client_initials text, assigned_lawyer_id uuid, assigned_lawyer text, area text, status text, status_label text, next_step text, urgent boolean, cnj_number text, needs_cnj_number boolean, deadline_at timestamp with time zone, updated_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with viewer as (
    select lfm.profile_id, lfm.roles
    from public.law_firm_members lfm
    where lfm.law_firm_id = law_firm_id_value
      and lfm.profile_id = auth.uid()
      and lfm.status = 'active'
    limit 1
  ),
  scoped_cases as (
    select lc.*
    from public.legal_cases lc
    where lc.law_firm_id = law_firm_id_value
      and exists (select 1 from viewer)
      and (
        exists (
          select 1
          from viewer
          where roles && array['owner', 'admin', 'secretary']::text[]
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
      client_profile.deleted_at,
      client_profile.deleted_display_name
    ) as client_name,
    coalesce(client_profile.initials, 'CL') as client_initials,
    sc.assigned_lawyer_id,
    case
      when lawyer_profile.id is null then 'Sem advogado definido'
      else public.profile_display_name(
        lawyer_profile.full_name,
        lawyer_profile.deleted_at,
        lawyer_profile.deleted_display_name
      )
    end as assigned_lawyer,
    sc.area,
    sc.status::text as status,
    public.case_status_label(sc.status) as status_label,
    coalesce(sc.last_update_label, 'Atualizado hoje') as next_step,
    (
      sc.status <> 'closed'
      and sc.deadline_at is not null
      and sc.deadline_at <= now() + interval '7 days'
    ) as urgent,
    sc.cnj_number,
    (sc.deadline_at is not null and sc.cnj_number is null) as needs_cnj_number,
    sc.deadline_at,
    sc.updated_at
  from scoped_cases sc
  left join public.profiles client_profile
    on client_profile.id = sc.client_id
  left join public.profiles lawyer_profile
    on lawyer_profile.id = sc.assigned_lawyer_id
  order by sc.updated_at desc;
$function$;

-- ---------------------------------------------------------------------------
-- 4b. Caso encerrado não recebe atualização manual
--
-- Corpo VERBATIM da definição vigente (baseline); muda só a guarda nova.
-- Sem ela, add_case_update num caso encerrado sobrescrevia o rótulo
-- "Encerrado" por um título de atividade recente e re-subia o caso nas
-- listas — encerrado, mas parecendo vivo.
-- ---------------------------------------------------------------------------

create or replace function public.add_case_update(
  case_id_value uuid,
  title_value text,
  body_value text default null::text
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

  if (
    select status from public.legal_cases where id = case_id_value
  ) = 'closed' then
    raise exception 'Case is closed';
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

-- ---------------------------------------------------------------------------
-- 5. Grants
-- ---------------------------------------------------------------------------

revoke all on function public.close_legal_case(uuid) from public, anon;
grant execute on function public.close_legal_case(uuid) to authenticated;

revoke all on function public.reopen_legal_case(uuid) from public, anon;
grant execute on function public.reopen_legal_case(uuid) to authenticated;

revoke all on function public.set_case_deadline(uuid, timestamptz)
  from public, anon;
grant execute on function public.set_case_deadline(uuid, timestamptz)
  to authenticated;

-- Recriadas com drop + create, as quatro voltam com EXECUTE para PUBLIC
-- (default do Postgres) — revogar de novo faz parte da recriação.
revoke all on function public.fetch_case_for_current_user(uuid)
  from public, anon;
grant execute on function public.fetch_case_for_current_user(uuid)
  to authenticated;

revoke all on function public.fetch_client_cases() from public, anon;
grant execute on function public.fetch_client_cases() to authenticated;

revoke all on function public.fetch_lawyer_cases() from public, anon;
grant execute on function public.fetch_lawyer_cases() to authenticated;

revoke all on function public.fetch_law_firm_cases(uuid) from public, anon;
grant execute on function public.fetch_law_firm_cases(uuid) to authenticated;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Verificacao pos-push (SQL Editor):
--   select public.infer_notification_scope('case_closed', null);  -- client
--   select * from public.fetch_case_for_current_user('<id de caso seu>');
-- ---------------------------------------------------------------------------
