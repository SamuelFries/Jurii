-- Enables realtime chat updates and lets office members display client names
-- in firm conversations.
--
-- Run after patch_009.

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'messages'
  ) then
    alter publication supabase_realtime add table public.messages;
  end if;
end $$;

create or replace function public.can_select_profile(profile_id_value uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    profile_id_value = auth.uid()
    or exists (
      select 1
      from public.legal_cases lc
      where (
        lc.client_id = auth.uid()
        and lc.assigned_lawyer_id = profile_id_value
      )
      or (
        lc.assigned_lawyer_id = auth.uid()
        and lc.client_id = profile_id_value
      )
    )
    or exists (
      select 1
      from public.case_participants cp
      where cp.profile_id = profile_id_value
        and public.can_access_case(cp.case_id)
    )
    or exists (
      select 1
      from public.conversations c
      where (
        c.client_id = auth.uid()
        and c.lawyer_id = profile_id_value
      )
      or (
        c.lawyer_id = auth.uid()
        and c.client_id = profile_id_value
      )
    )
    or exists (
      select 1
      from public.law_firm_members viewer
      join public.law_firm_members target
        on target.law_firm_id = viewer.law_firm_id
      where viewer.profile_id = auth.uid()
        and viewer.status in ('active', 'invited')
        and target.profile_id = profile_id_value
        and target.status in ('active', 'invited')
    )
    or exists (
      select 1
      from public.conversations c
      join public.law_firm_members viewer
        on viewer.law_firm_id = c.law_firm_id
      where c.client_id = profile_id_value
        and c.law_firm_id is not null
        and viewer.profile_id = auth.uid()
        and viewer.status = 'active'
    );
$$;
