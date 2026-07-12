-- Allows users to dismiss their own notifications from the app.
--
-- Run after patch_033. The notification bell uses this permission when the
-- user swipes a notification to the side.

alter table public.notifications enable row level security;

drop policy if exists "notifications_delete_own" on public.notifications;
create policy "notifications_delete_own"
on public.notifications for delete
to authenticated
using (recipient_profile_id = auth.uid());

grant delete on public.notifications to authenticated;

select pg_notify('pgrst', 'reload schema');
