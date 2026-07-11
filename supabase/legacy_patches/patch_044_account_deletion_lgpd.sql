-- Patch 044 -- Auditoria da exclusao LGPD via Edge Function.
--
-- Rode depois do patch_043 e faca deploy da Edge Function
-- supabase/functions/delete-account.
--
-- O soft-delete historico continua em public.delete_current_account(), mas a
-- exclusao completa agora deve ser iniciada pela Edge Function `delete-account`,
-- que roda com service_role para:
--   1. apagar Storage sensivel de verificacao/avatar;
--   2. executar o soft-delete transacional existente;
--   3. banir o usuario em auth.users;
--   4. registrar auditoria tecnica nesta tabela.
--
-- Nao apagamos anexos de chat nem documentos de caso aqui: eles podem ser
-- prova/evidencia e precisam de politica de retencao propria.

create table if not exists public.account_deletion_audit (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null,
  requested_at timestamptz not null default now(),
  completed_at timestamptz,
  status text not null default 'started'
    check (status in ('started', 'completed', 'failed')),
  storage_summary jsonb not null default '{}'::jsonb,
  auth_banned_at timestamptz,
  error_message text
);

create index if not exists account_deletion_audit_profile_idx
on public.account_deletion_audit(profile_id, requested_at desc);

alter table public.account_deletion_audit enable row level security;

revoke all on table public.account_deletion_audit
from public, anon, authenticated;

grant select, insert, update on table public.account_deletion_audit
to service_role;

-- Corrige o literal antigo para novas exclusoes. O patch_041 corrigiu a
-- funcao de exibicao, mas delete_current_account ainda gravava o sufixo
-- historico em conversas diretas sem escritorio.
create or replace function public.delete_current_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  profile_id_value uuid;
  profile_row public.profiles%rowtype;
  deleted_name_value text;
  deleted_email_value text;
begin
  profile_id_value := auth.uid();

  if profile_id_value is null then
    raise exception 'User must be authenticated';
  end if;

  select *
  into profile_row
  from public.profiles
  where id = profile_id_value
  for update;

  if not found then
    return;
  end if;

  if profile_row.deleted_at is not null then
    return;
  end if;

  deleted_name_value := coalesce(
    nullif(trim(profile_row.deleted_display_name), ''),
    nullif(trim(profile_row.full_name), ''),
    'Usuário'
  );
  deleted_email_value := nullif(trim(profile_row.email), '');

  perform public.transfer_owned_law_firms_for_deleted_profile(profile_id_value);

  update public.conversations
  set
    title = deleted_name_value || ' (conta excluída)',
    updated_at = now()
  where lawyer_id = profile_id_value
    and law_firm_id is null;

  update public.law_firm_members
  set
    status = 'disabled',
    lawyer_id = null,
    pending_lawyer_id = null,
    lawyer_invite_status = 'disabled'
  where profile_id = profile_id_value
     or lawyer_id = profile_id_value
     or pending_lawyer_id = profile_id_value;

  delete from public.verification_documents
  where user_id = profile_id_value;

  delete from public.lawyer_verifications
  where user_id = profile_id_value;

  delete from public.lawyer_profiles
  where id = profile_id_value;

  delete from public.law_firm_verification_documents lfvd
  where lfvd.owner_profile_id = profile_id_value
    and exists (
      select 1
      from public.law_firm_verifications lfv
      where lfv.id = lfvd.verification_id
        and lfv.owner_profile_id = profile_id_value
        and lfv.status <> 'approved'
    );

  update public.law_firm_verifications
  set
    status = case
      when law_firm_id is null then 'rejected'::public.verification_status
      else status
    end,
    rejection_reason = case
      when law_firm_id is null then 'Conta solicitante excluída.'
      else rejection_reason
    end,
    updated_at = now()
  where owner_profile_id = profile_id_value;

  update public.profiles
  set
    deleted_at = now(),
    deleted_display_name = deleted_name_value,
    deleted_email = deleted_email_value,
    full_name = deleted_name_value,
    email = 'deleted+' || profile_id_value::text || '@deleted.jurii.local',
    cpf = null,
    phone = null,
    avatar_url = null,
    lawyer_status = 'client'
  where id = profile_id_value;
end;
$$;

revoke all on function public.delete_current_account()
from public, anon, authenticated;

grant execute on function public.delete_current_account()
to authenticated;

select pg_notify('pgrst', 'reload schema');

-- Verificacao pos-patch:
--
--   select column_name, data_type
--   from information_schema.columns
--   where table_schema = 'public'
--     and table_name = 'account_deletion_audit';
--
--   -- Depois de acionar a Edge Function:
--   select profile_id, status, completed_at, auth_banned_at, storage_summary
--   from public.account_deletion_audit
--   order by requested_at desc
--   limit 5;
