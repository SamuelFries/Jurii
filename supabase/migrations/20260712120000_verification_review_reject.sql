-- ---------------------------------------------------------------------------
-- Verificação: fechar o ciclo de revisão (reject) + hardening dos documentos
-- ---------------------------------------------------------------------------
-- O baseline já tinha approve_lawyer_verification / approve_law_firm_verification
-- (service_role only) mas NÃO tinha o caminho de recusa. Sem ele, uma
-- verificação só podia ser aprovada — o revisor não tinha como devolver com
-- motivo, e o app nunca via o estado 'rejected' (a coluna existe desde o
-- baseline). Esta migration adiciona as funções de recusa espelhando as de
-- aprovação (SECURITY DEFINER, executáveis só pelo service_role — back-office),
-- e endurece o bucket de documentos com teto de tamanho e allowlist de MIME.
--
-- Produção já tem o baseline aplicado; esta é uma migration nova e aditiva.
-- ---------------------------------------------------------------------------

-- 1. Recusa de verificação de advogado -------------------------------------
create or replace function public.reject_lawyer_verification(
  verification_id_value uuid,
  reason_value text default null,
  reviewer_id_value uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  verification_row public.lawyer_verifications%rowtype;
begin
  select *
  into verification_row
  from public.lawyer_verifications
  where id = verification_id_value;

  if not found then
    raise exception 'Lawyer verification not found: %', verification_id_value;
  end if;

  update public.lawyer_verifications
  set
    status = 'rejected',
    reviewed_at = now(),
    reviewer_id = reviewer_id_value,
    rejection_reason = nullif(trim(coalesce(reason_value, '')), '')
  where id = verification_id_value;

  -- Volta o perfil para 'client' (o enum profiles.lawyer_status não tem
  -- 'rejected'); o app enxerga a recusa pela linha de verificação, e o usuário
  -- pode reenviar do zero.
  update public.profiles
  set lawyer_status = 'client'
  where id = verification_row.user_id;

  return verification_row.user_id;
end;
$$;

revoke all on function public.reject_lawyer_verification(uuid, text, uuid)
from public, anon, authenticated;

grant execute on function public.reject_lawyer_verification(uuid, text, uuid)
to service_role;

-- 2. Recusa de verificação de escritório -----------------------------------
create or replace function public.reject_law_firm_verification(
  verification_id_value uuid,
  reason_value text default null,
  reviewer_id_value uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  verification_row public.law_firm_verifications%rowtype;
begin
  select *
  into verification_row
  from public.law_firm_verifications
  where id = verification_id_value;

  if not found then
    raise exception 'Law firm verification not found: %', verification_id_value;
  end if;

  update public.law_firm_verifications
  set
    status = 'rejected',
    reviewed_at = now(),
    reviewer_id = reviewer_id_value,
    rejection_reason = nullif(trim(coalesce(reason_value, '')), '')
  where id = verification_id_value;

  return verification_row.owner_profile_id;
end;
$$;

revoke all on function public.reject_law_firm_verification(uuid, text, uuid)
from public, anon, authenticated;

grant execute on function public.reject_law_firm_verification(uuid, text, uuid)
to service_role;

-- 3. Hardening do bucket de documentos -------------------------------------
-- Teto de 10 MB por arquivo e allowlist de MIME direto no Storage — vale
-- mesmo que o cliente burle a validação local (o app valida extensão, magic
-- bytes e tamanho antes de subir).
update storage.buckets
set
  file_size_limit = 10485760,
  allowed_mime_types = array[
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/webp'
  ]
where id = 'verification-documents';

-- 4. Guarda de tamanho na tabela de documentos do advogado -----------------
-- (law_firm_verification_documents não guarda file_size_bytes; o teto do
-- bucket cobre os dois fluxos.)
alter table public.verification_documents
  drop constraint if exists verification_documents_size_chk;

alter table public.verification_documents
  add constraint verification_documents_size_chk
  check (
    file_size_bytes is null
    or (file_size_bytes > 0 and file_size_bytes <= 10485760)
  );
