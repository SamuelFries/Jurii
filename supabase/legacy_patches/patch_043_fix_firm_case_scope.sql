-- Patch 043 -- Escopo estrito de casos do escritorio.
--
-- Rode depois do patch_042.
--
-- Problema: as RPCs de escritorio herdadas do patch_030 tratavam como "caso do
-- escritorio" qualquer caso atribuido a um advogado membro ou com participante
-- membro do escritorio. Isso permitia que o escritorio A enxergasse ou
-- reatribuisse um caso pessoal do advogado, ou um caso de outro escritorio, so
-- porque o advogado tambem era membro do escritorio A.
--
-- Correcao: na superficie do escritorio, caso pertence ao escritorio somente
-- quando public.legal_cases.law_firm_id = law_firm_id_value. Membership de
-- advogado continua servindo para permissao/atribuicao dentro desse escritorio,
-- mas nunca para "puxar" caso de fora para dentro.

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

create or replace function public.assign_law_firm_case(
  law_firm_id_value uuid,
  case_id_value uuid,
  lawyer_profile_id_value uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  case_row public.legal_cases%rowtype;
  old_lawyer_id uuid;
  target_lawyer_id uuid;
  target_lawyer_name text;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  if not public.is_active_law_firm_case_manager(law_firm_id_value) then
    raise exception 'Only office case managers can assign cases';
  end if;

  select *
  into case_row
  from public.legal_cases
  where id = case_id_value
  for update;

  if not found then
    raise exception 'Case not found';
  end if;

  if case_row.law_firm_id is distinct from law_firm_id_value then
    raise exception 'Case does not belong to this office';
  end if;

  select
    coalesce(lfm.lawyer_id, lfm.profile_id),
    coalesce(p.full_name, 'Advogado')
  into target_lawyer_id, target_lawyer_name
  from public.law_firm_members lfm
  join public.lawyer_profiles lp
    on lp.id = coalesce(lfm.lawyer_id, lfm.profile_id)
  left join public.profiles p
    on p.id = coalesce(lfm.lawyer_id, lfm.profile_id)
  where lfm.law_firm_id = law_firm_id_value
    and lfm.profile_id = lawyer_profile_id_value
    and lfm.status = 'active'
    and 'lawyer' = any(lfm.roles)
    and coalesce(lfm.lawyer_invite_status, 'active'::public.law_firm_member_status)
      = 'active'
  limit 1;

  if target_lawyer_id is null then
    raise exception 'Target member must be an active lawyer';
  end if;

  old_lawyer_id := case_row.assigned_lawyer_id;

  update public.legal_cases
  set
    law_firm_id = law_firm_id_value,
    assigned_lawyer_id = target_lawyer_id,
    last_update_label = 'Caso atribuído',
    updated_at = now()
  where id = case_id_value;

  if old_lawyer_id is not null and old_lawyer_id <> target_lawyer_id then
    delete from public.case_participants
    where case_id = case_id_value
      and profile_id = old_lawyer_id
      and role = 'lawyer';
  end if;

  insert into public.case_participants (case_id, profile_id, role)
  values (case_id_value, target_lawyer_id, 'lawyer')
  on conflict (case_id, profile_id) do update
  set role = 'lawyer';

  update public.conversations
  set
    law_firm_id = law_firm_id_value,
    lawyer_id = target_lawyer_id,
    updated_at = now()
  where case_id = case_id_value
    and type <> 'firm_internal'
    and (
      law_firm_id = law_firm_id_value
      or law_firm_id is null
    );

  if old_lawyer_id is distinct from target_lawyer_id then
    insert into public.messages (
      conversation_id,
      sender_id,
      sender_type,
      body,
      metadata
    )
    select
      c.id,
      auth.uid(),
      'system',
      'Caso atribuído a ' || target_lawyer_name || '.',
      jsonb_build_object(
        'type', 'case_assignment',
        'case_id', case_id_value,
        'lawyer_id', target_lawyer_id,
        'law_firm_id', law_firm_id_value
      )
    from public.conversations c
    where c.case_id = case_id_value
      and c.type <> 'firm_internal'
      and c.law_firm_id = law_firm_id_value;
  end if;

  return target_lawyer_id;
end;
$$;

revoke all on function public.fetch_law_firm_cases(uuid)
from public, anon, authenticated;

revoke all on function public.assign_law_firm_case(uuid, uuid, uuid)
from public, anon, authenticated;

grant execute on function public.fetch_law_firm_cases(uuid)
to authenticated;

grant execute on function public.assign_law_firm_case(uuid, uuid, uuid)
to authenticated;

select pg_notify('pgrst', 'reload schema');

-- Verificacao pos-patch (substitua os ids e rode como membro do escritorio):
--
--   -- 1) A lista do escritorio deve conter apenas casos do proprio escritorio.
--   select *
--   from public.fetch_law_firm_cases('<LAW_FIRM_ID>'::uuid);
--
--   -- 2) Atribuir caso pessoal/de outro escritorio deve falhar:
--   select public.assign_law_firm_case(
--     '<LAW_FIRM_ID>'::uuid,
--     '<CASE_ID_COM_LAW_FIRM_ID_DIFERENTE_OU_NULL>'::uuid,
--     '<PROFILE_ID_DO_ADVOGADO_ALVO>'::uuid
--   );
--   -- Esperado: "Case does not belong to this office".
--
--   -- 3) Diagnostico de casos que antes poderiam vazar por membership:
--   select lc.id, lc.title, lc.law_firm_id, lc.assigned_lawyer_id
--   from public.legal_cases lc
--   where lc.law_firm_id is null
--     and exists (
--       select 1
--       from public.law_firm_members lfm
--       where lfm.law_firm_id = '<LAW_FIRM_ID>'::uuid
--         and lfm.status = 'active'
--         and (
--           lfm.profile_id = lc.assigned_lawyer_id
--           or lfm.lawyer_id = lc.assigned_lawyer_id
--         )
--     );
--   -- Esperado para fetch_law_firm_cases: esses casos NAO aparecem.
