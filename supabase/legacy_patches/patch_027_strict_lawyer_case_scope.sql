-- Ensures the professional case list never includes cases where the current
-- user only participates as the client.
--
-- Run after patch_026 if a user who is also a lawyer sees their own client
-- cases inside the lawyer flow. The client flow continues to use
-- fetch_client_cases().

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
  select distinct
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
        and cp.role in ('lawyer', 'firm_member')
     )
  order by lc.updated_at desc;
$$;

revoke all on function public.fetch_lawyer_cases()
from public, anon, authenticated;

grant execute on function public.fetch_lawyer_cases()
to authenticated;

notify pgrst, 'reload schema';
