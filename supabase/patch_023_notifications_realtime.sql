-- Enables realtime delivery for notifications used by the home bell.
--
-- Run after patch_022 if notifications are created in the database but the
-- in-app bell does not update until a manual refresh/rebuild.

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;

notify pgrst, 'reload schema';
