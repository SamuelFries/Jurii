-- Strengthens office case visibility and real operation metrics.
--
-- Run after patch_021. This patch makes accepted cases created by lawyers who
-- belong to an office visible in that office's case area, and exposes real
-- counters for the office home operation section.

alter table public.law_firm_members
add column if not exists created_at timestamptz;

update public.law_firm_members
set created_at = coalesce(created_at, joined_at, now());

alter table public.law_firm_members
alter column created_at set default now();

alter table public.law_firm_members
alter column created_at set not null;

create or replace function public.fetch_law_firm_cases(
  law_firm_id_value uuid
)
returns table (
  id uuid,
  title text,
  client_name text,
  client_initials text,
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
  with active_members as (
    select lfm.profile_id
    from public.law_firm_members lfm
    where lfm.law_firm_id = law_firm_id_value
      and lfm.profile_id is not null
      and lfm.status = 'active'
  ),
  scoped_cases as (
    select distinct lc.*
    from public.legal_cases lc
    where exists (
      select 1
      from active_members viewer
      where viewer.profile_id = auth.uid()
    )
    and (
      lc.law_firm_id = law_firm_id_value
      or exists (
        select 1
        from active_members assigned_member
        where assigned_member.profile_id = lc.assigned_lawyer_id
      )
      or exists (
        select 1
        from public.case_participants cp
        join active_members participant_member
          on participant_member.profile_id = cp.profile_id
        where cp.case_id = lc.id
          and cp.role in ('lawyer', 'firm_member')
      )
    )
  )
  select
    sc.id,
    sc.title,
    coalesce(client_profile.full_name, 'Cliente') as client_name,
    coalesce(client_profile.initials, 'CL') as client_initials,
    coalesce(lawyer_profile.full_name, 'Sem advogado definido') as assigned_lawyer,
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

create or replace function public.fetch_law_firm_operation_metrics(
  law_firm_id_value uuid
)
returns table (
  client_messages int,
  team_messages int,
  active_cases int,
  team_members int
)
language sql
stable
security definer
set search_path = public
as $$
  with active_members as (
    select lfm.profile_id
    from public.law_firm_members lfm
    where lfm.law_firm_id = law_firm_id_value
      and lfm.profile_id is not null
      and lfm.status = 'active'
  ),
  scoped_cases as (
    select distinct lc.id
    from public.legal_cases lc
    where lc.status <> 'closed'
      and (
        lc.law_firm_id = law_firm_id_value
        or exists (
          select 1
          from active_members assigned_member
          where assigned_member.profile_id = lc.assigned_lawyer_id
        )
        or exists (
          select 1
          from public.case_participants cp
          join active_members participant_member
            on participant_member.profile_id = cp.profile_id
          where cp.case_id = lc.id
            and cp.role in ('lawyer', 'firm_member')
        )
      )
  )
  select
    (
      select count(distinct c.id)::int
      from public.conversations c
      where c.law_firm_id = law_firm_id_value
        and c.type <> 'firm_internal'
        and exists (
          select 1
          from public.messages m
          where m.conversation_id = c.id
        )
    ) as client_messages,
    (
      select count(distinct c.id)::int
      from public.conversations c
      where c.law_firm_id = law_firm_id_value
        and c.type = 'firm_internal'
        and exists (
          select 1
          from public.messages m
          where m.conversation_id = c.id
        )
    ) as team_messages,
    (select count(*)::int from scoped_cases) as active_cases,
    (select count(*)::int from active_members) as team_members
  where exists (
    select 1
    from active_members viewer
    where viewer.profile_id = auth.uid()
  );
$$;

revoke all on function public.fetch_law_firm_cases(uuid)
from public, anon, authenticated;

revoke all on function public.fetch_law_firm_operation_metrics(uuid)
from public, anon, authenticated;

grant execute on function public.fetch_law_firm_cases(uuid)
to authenticated;

grant execute on function public.fetch_law_firm_operation_metrics(uuid)
to authenticated;

notify pgrst, 'reload schema';
