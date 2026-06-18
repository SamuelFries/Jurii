-- Repairs the missing practice-area normalizer used by the office invite RPC.
--
-- Run after patch_032 if inviting a lawyer fails with:
-- function public.normalize_practice_areas(text[]) does not exist.

create or replace function public.normalize_practice_areas(
  practice_areas_value text[]
)
returns text[]
language sql
immutable
set search_path = public
as $$
  select coalesce(array_agg(area order by first_ordinal), '{}'::text[])
  from (
    select area, min(ordinality) as first_ordinal
    from (
      select nullif(trim(area_value), '') as area, ordinality
      from unnest(coalesce(practice_areas_value, '{}'::text[]))
        with ordinality as areas(area_value, ordinality)
    ) cleaned_areas
    where area is not null
    group by area
  ) distinct_areas;
$$;

revoke all on function public.normalize_practice_areas(text[])
from public, anon;

grant execute on function public.normalize_practice_areas(text[])
to authenticated;

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_profile_id uuid not null references public.profiles(id) on delete cascade,
  actor_profile_id uuid references public.profiles(id) on delete set null,
  law_firm_id uuid references public.law_firms(id) on delete cascade,
  type text not null default 'system',
  title text not null,
  body text not null,
  metadata jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists notifications_recipient_created_idx
on public.notifications(recipient_profile_id, created_at desc);

create index if not exists notifications_recipient_unread_idx
on public.notifications(recipient_profile_id)
where read_at is null;

alter table public.notifications enable row level security;

drop policy if exists "notifications_select_own" on public.notifications;
create policy "notifications_select_own"
on public.notifications for select
to authenticated
using (recipient_profile_id = auth.uid());

drop policy if exists "notifications_update_own" on public.notifications;
create policy "notifications_update_own"
on public.notifications for update
to authenticated
using (recipient_profile_id = auth.uid())
with check (recipient_profile_id = auth.uid());

grant select, update on public.notifications to authenticated;

select pg_notify('pgrst', 'reload schema');
