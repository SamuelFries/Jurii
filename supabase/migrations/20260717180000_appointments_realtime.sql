-- Agenda em tempo real
--
-- Publica public.appointments no realtime para a agenda atualizar sozinha
-- (outro dispositivo do advogado, um compromisso criado/editado/cancelado). O
-- Realtime respeita RLS: a policy de SELECT ja limita a `client_id = auth.uid()
-- or lawyer_id = auth.uid()`, entao cada usuario so recebe eventos dos proprios
-- compromissos.
--
-- Mesmo padrao idempotente que a baseline usou para messages e notifications.

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'appointments'
  ) then
    alter publication supabase_realtime add table public.appointments;
  end if;
end $$;
