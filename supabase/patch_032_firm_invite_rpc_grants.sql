-- Repairs execute grants and schema cache for office invite RPCs.
--
-- Run after patch_030 and patch_031 if inviting a lawyer still fails with a
-- function/schema/permission error.

do $$
begin
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'invite_verified_lawyer_to_law_firm'
      and pg_get_function_identity_arguments(p.oid) = 'law_firm_id_value uuid, oab_state_value text, oab_number_value text'
  ) then
    revoke all on function public.invite_verified_lawyer_to_law_firm(uuid, text, text)
    from public, anon;

    grant execute on function public.invite_verified_lawyer_to_law_firm(uuid, text, text)
    to authenticated;
  else
    raise exception 'Missing invite_verified_lawyer_to_law_firm(uuid, text, text). Run patch_030 first.';
  end if;

  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'respond_to_law_firm_invite'
      and pg_get_function_identity_arguments(p.oid) = 'membership_id_value uuid, accepted_value boolean'
  ) then
    revoke all on function public.respond_to_law_firm_invite(uuid, boolean)
    from public, anon;

    grant execute on function public.respond_to_law_firm_invite(uuid, boolean)
    to authenticated;
  end if;
end $$;

select pg_notify('pgrst', 'reload schema');
