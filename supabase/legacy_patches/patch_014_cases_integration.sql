-- Case listing entry points for client, lawyer and office areas.
--
-- Run after patch_013.

create or replace function public.case_status_label(status_value public.lawyer_case_status)
returns text
language sql
immutable
set search_path = public
as $$
  select case status_value
    when 'new_message' then 'Nova mensagem'
    when 'deadline' then 'Prazo crítico'
    when 'closed' then 'Encerrado'
    else 'Em andamento'
  end;
$$;

create or replace function public.fetch_client_cases()
returns table (
  id uuid,
  title text,
  area text,
  status text,
  status_label text,
  last_update_label text,
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
    lc.area,
    lc.status::text as status,
    public.case_status_label(lc.status) as status_label,
    coalesce(lc.last_update_label, 'Atualizado hoje') as last_update_label,
    lc.updated_at
  from public.legal_cases lc
  where lc.client_id = auth.uid()
  order by lc.updated_at desc;
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
     )
  order by lc.updated_at desc;
$$;

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
  select
    lc.id,
    lc.title,
    coalesce(client_profile.full_name, 'Cliente') as client_name,
    coalesce(client_profile.initials, 'CL') as client_initials,
    coalesce(lawyer_profile.full_name, 'Sem advogado definido') as assigned_lawyer,
    lc.area,
    public.case_status_label(lc.status) as status_label,
    coalesce(lc.last_update_label, 'Atualizado hoje') as next_step,
    lc.status = 'deadline' as urgent,
    lc.updated_at
  from public.legal_cases lc
  left join public.profiles client_profile
    on client_profile.id = lc.client_id
  left join public.profiles lawyer_profile
    on lawyer_profile.id = lc.assigned_lawyer_id
  where lc.law_firm_id = law_firm_id_value
    and exists (
      select 1
      from public.law_firm_members lfm
      where lfm.law_firm_id = law_firm_id_value
        and lfm.profile_id = auth.uid()
        and lfm.status = 'active'
    )
  order by lc.updated_at desc;
$$;

revoke all on function public.case_status_label(public.lawyer_case_status)
from public, anon, authenticated;

revoke all on function public.fetch_client_cases()
from public, anon, authenticated;

revoke all on function public.fetch_lawyer_cases()
from public, anon, authenticated;

revoke all on function public.fetch_law_firm_cases(uuid)
from public, anon, authenticated;

grant execute on function public.fetch_client_cases()
to authenticated;

grant execute on function public.fetch_lawyer_cases()
to authenticated;

grant execute on function public.fetch_law_firm_cases(uuid)
to authenticated;
