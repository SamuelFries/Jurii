-- Segments notifications by app flow.
--
-- Run after patch_024. Notifications are now scoped to the area that should
-- display them: client, lawyer or firm. The app filters each bell by this
-- scope, and the cards use the matching visual theme as reinforcement.

do $$
begin
  if not exists (
    select 1
    from pg_type
    where typname = 'notification_scope'
  ) then
    create type public.notification_scope as enum ('client', 'lawyer', 'firm');
  end if;
end $$;

alter table public.notifications
add column if not exists scope public.notification_scope not null default 'client';

create or replace function public.infer_notification_scope(
  type_value text,
  current_scope public.notification_scope default null
)
returns public.notification_scope
language sql
immutable
set search_path = public
as $$
  select case
    when type_value in ('team_invite', 'case_request_response') then 'lawyer'::public.notification_scope
    when type_value in ('firm_case_started') then 'firm'::public.notification_scope
    when type_value in ('case_request', 'message', 'case_update') then 'client'::public.notification_scope
    else coalesce(current_scope, 'client'::public.notification_scope)
  end;
$$;

create or replace function public.notifications_set_scope()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.scope := public.infer_notification_scope(new.type, new.scope);
  return new;
end;
$$;

drop trigger if exists notifications_set_scope on public.notifications;
create trigger notifications_set_scope
before insert or update of type, scope
on public.notifications
for each row execute function public.notifications_set_scope();

update public.notifications
set scope = public.infer_notification_scope(type, scope);

create index if not exists notifications_recipient_scope_created_idx
on public.notifications(recipient_profile_id, scope, created_at desc);

create index if not exists notifications_recipient_scope_unread_idx
on public.notifications(recipient_profile_id, scope)
where read_at is null;

notify pgrst, 'reload schema';
