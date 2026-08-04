-- Remove o PRAZO MANUAL do caso.
--
-- Por que sai: prazo processual só serve se for confiável, e confiável aqui
-- significa automático. O advogado com dezenas de processos não vai manter um
-- registro paralelo de prazos num app de marketplace — ele já tem software de
-- escritório para isso. E automatizar pelo DataJud não fecha: o índice público
-- tem frescor de 3-4 dias (embargos de declaração são 5 dias úteis), não traz
-- data de intimação (que é o que inicia a contagem) nem diz de qual parte é o
-- prazo. Meio-caminho aqui não é feature incompleta, é risco: perder prazo tem
-- consequência jurídica.
--
-- Contraste com o número CNJ, que FICA: informa-se uma vez e a timeline passa
-- a atualizar sozinha. Esse é o critério — o que o profissional faz uma vez e
-- rende para sempre fica; o que exige manutenção perpétua sai.
--
-- Produção tem 0 casos com deadline_at preenchido: nada a migrar.
--
-- Sai junto:
--   * set_case_deadline (RPC) e a coluna legal_cases.deadline_at;
--   * needs_cnj_number, que dependia do prazo e por isso NUNCA disparou;
--   * urgent do painel do escritório derivado de prazo — substituído por
--     sinal automático (cliente sem resposta há 24h), abaixo.
--
-- As 4 fetch_* são reescritas VERBATIM a partir das definições vigentes em
-- produção (pg_get_functiondef), com as substituições feitas por script com
-- assert de ocorrência única. Drop+create zera EXECUTE: grants refeitos no fim.

drop function if exists public.set_case_deadline(uuid, timestamptz);

drop function if exists public.fetch_client_cases();
drop function if exists public.fetch_lawyer_cases();
drop function if exists public.fetch_law_firm_cases(uuid);
drop function if exists public.fetch_case_for_current_user(uuid);

alter table public.legal_cases drop column if exists deadline_at;

create function public.fetch_client_cases()
 RETURNS TABLE(id uuid, title text, area text, status text, status_label text, last_update_label text, cnj_number text, updated_at timestamp with time zone)
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
    lc.updated_at
  from public.legal_cases lc
  where lc.client_id = auth.uid()
  order by lc.updated_at desc;
$function$
;

create function public.fetch_lawyer_cases()
 RETURNS TABLE(id uuid, title text, client_name text, client_initials text, area text, last_update_label text, status text, cnj_number text, updated_at timestamp with time zone)
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
$function$
;

create function public.fetch_law_firm_cases(law_firm_id_value uuid)
 RETURNS TABLE(id uuid, title text, client_name text, client_initials text, assigned_lawyer_id uuid, assigned_lawyer text, area text, status text, status_label text, next_step text, urgent boolean, cnj_number text, updated_at timestamp with time zone)
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
    -- Urgência AUTOMÁTICA: cliente falou por último e está sem resposta
    -- há mais de 24h. Antes derivava de deadline_at, um campo que alguém
    -- tinha que lembrar de preencher (0 casos em produção o tinham). Este
    -- sinal o app já possui inteiro e nunca fica desatualizado; num
    -- marketplace, o que perde cliente é advogado que não responde.
    (
      sc.status <> 'closed'
      and exists (
        select 1
        from public.conversations conv
        cross join lateral (
          select m.sender_type, m.created_at
          from public.messages m
          where m.conversation_id = conv.id
          order by m.created_at desc
          limit 1
        ) last_message
        where conv.case_id = sc.id
          and last_message.sender_type = 'client'
          and last_message.created_at < now() - interval '24 hours'
      )
    ) as urgent,
    sc.cnj_number,
    sc.updated_at
  from scoped_cases sc
  left join public.profiles client_profile
    on client_profile.id = sc.client_id
  left join public.profiles lawyer_profile
    on lawyer_profile.id = sc.assigned_lawyer_id
  order by sc.updated_at desc;
$function$
;

create function public.fetch_case_for_current_user(case_id_value uuid)
 RETURNS TABLE(id uuid, title text, area text, status_label text, client_name text, cnj_number text, description text, status text, created_at timestamp with time zone, assigned_lawyer_id uuid, law_firm_id uuid, viewer_is_client boolean, can_manage boolean, can_manage_lifecycle boolean)
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
    lc.created_at,
    lc.assigned_lawyer_id,
    lc.law_firm_id,
    lc.client_id = auth.uid() as viewer_is_client,
    public.can_manage_case_updates(lc.id) as can_manage,
    -- Espelha o gate de escrita de close/reopen: sem
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
$function$
;

revoke all on function public.fetch_client_cases() from public, anon;
grant execute on function public.fetch_client_cases() to authenticated;

revoke all on function public.fetch_lawyer_cases() from public, anon;
grant execute on function public.fetch_lawyer_cases() to authenticated;

revoke all on function public.fetch_law_firm_cases(uuid) from public, anon;
grant execute on function public.fetch_law_firm_cases(uuid) to authenticated;

revoke all on function public.fetch_case_for_current_user(uuid) from public, anon;
grant execute on function public.fetch_case_for_current_user(uuid) to authenticated;

notify pgrst, 'reload schema';
