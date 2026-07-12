-- Grants required table privileges for Supabase API roles.
--
-- RLS policies decide which rows each user can access, but PostgreSQL still
-- requires table-level privileges for the anon/authenticated roles first.
-- Run this patch if the app logs errors like:
-- "permission denied for table profiles"
-- "Grant SELECT ON public.profiles TO authenticated"

grant usage on schema public to anon, authenticated;

grant select on public.profiles to anon;

grant select, insert, update on public.profiles to authenticated;

grant select on public.legal_categories to anon, authenticated;
grant select on public.law_firms to anon, authenticated;
grant select on public.law_firm_categories to anon, authenticated;
grant select on public.lawyer_profiles to anon, authenticated;

grant select, insert, update on public.lawyer_verifications to authenticated;
grant select, insert on public.verification_documents to authenticated;

grant select, insert, update on public.law_firm_verifications to authenticated;
grant select, insert on public.law_firm_verification_documents to authenticated;
grant select, insert, update on public.law_firm_members to authenticated;

grant select, insert, update on public.legal_cases to authenticated;
grant select, insert, update on public.case_participants to authenticated;
grant select, insert, update on public.case_documents to authenticated;

grant select, insert, update on public.conversations to authenticated;
grant select, insert, update on public.messages to authenticated;
grant select, insert, update on public.appointments to authenticated;
