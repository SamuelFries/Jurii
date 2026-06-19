-- Removes the deprecated office lawyer-count field from verification records.
--
-- Run after patch_036. The app no longer asks for or sends this value; actual
-- office members are tracked through law_firm_members instead.

alter table if exists public.law_firm_verifications
drop column if exists lawyers_count;

select pg_notify('pgrst', 'reload schema');
