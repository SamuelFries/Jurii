-- ---------------------------------------------------------------------------
-- Exclusao LGPD: leitura administrativa minima dos caminhos no Storage
-- ---------------------------------------------------------------------------
-- A Edge Function delete-account precisa localizar documentos de verificacao
-- e o avatar antes de executar o soft-delete. O service_role nao recebe SELECT
-- direto nas tabelas sensiveis: esta RPC SECURITY DEFINER expoe somente bucket
-- e caminho dos objetos pertencentes ao perfil solicitado.
-- ---------------------------------------------------------------------------

create or replace function public.get_account_deletion_storage_paths(
  profile_id_value uuid
)
returns table (
  bucket_id text,
  storage_path text
)
language sql
stable
security definer
set search_path = ''
as $$
  with avatar_paths as (
    select split_part(
      split_part(
        split_part(
          p.avatar_url,
          '/storage/v1/object/public/profile-avatars/',
          2
        ),
        '?',
        1
      ),
      '#',
      1
    ) as storage_path
    from public.profiles p
    where p.id = profile_id_value
      and position(
        '/storage/v1/object/public/profile-avatars/' in p.avatar_url
      ) > 0
  )
  select
    'verification-documents'::text as bucket_id,
    vd.storage_path
  from public.verification_documents vd
  where vd.user_id = profile_id_value
    and nullif(btrim(vd.storage_path), '') is not null
    and vd.storage_path like profile_id_value::text || '/%'

  union

  select
    'verification-documents'::text,
    lfvd.storage_path
  from public.law_firm_verification_documents lfvd
  where lfvd.owner_profile_id = profile_id_value
    and nullif(btrim(lfvd.storage_path), '') is not null
    and lfvd.storage_path like profile_id_value::text || '/%'

  union

  select
    'profile-avatars'::text,
    avatar_paths.storage_path
  from avatar_paths
  where nullif(btrim(avatar_paths.storage_path), '') is not null
    and avatar_paths.storage_path like profile_id_value::text || '/%';
$$;

comment on function public.get_account_deletion_storage_paths(uuid) is
  'Retorna somente os caminhos de Storage usados pela exclusao LGPD; service_role only.';

revoke all on function public.get_account_deletion_storage_paths(uuid)
from public, anon, authenticated;

grant execute on function public.get_account_deletion_storage_paths(uuid)
to service_role;

select pg_notify('pgrst', 'reload schema');
