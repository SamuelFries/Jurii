begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(28);

insert into auth.users (
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values
  (
    '91000000-0000-0000-0000-000000000001',
    'authenticated',
    'authenticated',
    'profile-customization@jurii.test',
    '',
    now(),
    '{}'::jsonb,
    '{"full_name":"Perfil Customizavel"}'::jsonb,
    now(),
    now()
  ),
  (
    '91000000-0000-0000-0000-000000000002',
    'authenticated',
    'authenticated',
    'other-profile@jurii.test',
    '',
    now(),
    '{}'::jsonb,
    '{"full_name":"Outro Perfil"}'::jsonb,
    now(),
    now()
  );

update public.profiles
set phone = '11999999999'
where id = '91000000-0000-0000-0000-000000000001';

insert into storage.objects (bucket_id, name, owner_id, metadata)
values
  (
    'profile-avatars',
    '91000000-0000-0000-0000-000000000001/avatar-source.png',
    '91000000-0000-0000-0000-000000000001',
    '{}'::jsonb
  ),
  (
    'profile-avatars',
    '91000000-0000-0000-0000-000000000001/avatar-delete.png',
    '91000000-0000-0000-0000-000000000001',
    '{}'::jsonb
  ),
  (
    'profile-avatars',
    '91000000-0000-0000-0000-000000000002/avatar-delete.png',
    '91000000-0000-0000-0000-000000000002',
    '{}'::jsonb
  ),
  (
    'case-documents',
    '91000000-0000-0000-0000-000000000001/not-an-avatar.png',
    '91000000-0000-0000-0000-000000000001',
    '{}'::jsonb
  );

-- Desde a 20260910120000 o bucket case-documents deixa o autor apagar objeto
-- SOLTO da propria pasta (rollback de upload). Para este teste seguir
-- provando que a policy do avatar nao vaza de bucket, o objeto vizinho
-- precisa sobreviver pelo motivo que passou a existir: estar LIGADO a uma
-- linha de case_documents.
insert into public.legal_cases (id, client_id, title, area, status)
values ('91caca00-0000-4000-8000-000000000001',
        '91000000-0000-0000-0000-000000000001',
        'Caso do avatar','Direito Cível','open');

insert into public.case_documents (case_id, uploaded_by, title, storage_path)
values ('91caca00-0000-4000-8000-000000000001',
        '91000000-0000-0000-0000-000000000001',
        'Nao e avatar',
        '91000000-0000-0000-0000-000000000001/not-an-avatar.png');

select ok(
  has_function_privilege(
    'authenticated',
    'public.upsert_current_profile(text,text,text)',
    'EXECUTE'
  ),
  'authenticated continua podendo completar o proprio perfil'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.upsert_current_profile(text,text,text)',
    'EXECUTE'
  ),
  'anon nao pode completar perfil'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.update_current_profile_customization(text,text,text,text)',
    'EXECUTE'
  ),
  'authenticated pode usar a RPC atomica de customizacao'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.update_current_profile_customization(text,text,text,text)',
    'EXECUTE'
  ),
  'anon nao pode usar a RPC de customizacao'
);

select ok(
  not has_column_privilege(
    'authenticated',
    'public.profiles',
    'avatar_url',
    'UPDATE'
  ),
  'avatar_url nao pode ser apontado diretamente para URL arbitraria'
);

select set_config(
  'request.jwt.claim.sub',
  '91000000-0000-0000-0000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"91000000-0000-0000-0000-000000000001","role":"authenticated","iss":"http://127.0.0.1:54321/auth/v1"}',
  true
);
set local role authenticated;

select lives_ok(
  $$select public.upsert_current_profile('  Maria   da Silva  ', null, null)$$,
  'NULL preserva telefone existente'
);

reset role;
select is(
  (
    select full_name || '|' || initials || '|' || phone
    from public.profiles
    where id = '91000000-0000-0000-0000-000000000001'
  ),
  'Maria da Silva|MS|11999999999',
  'nome e iniciais normalizam sem alterar telefone omitido'
);

set local role authenticated;
select lives_ok(
  $$select public.upsert_current_profile('Maria da Silva', null, '+55 (11) 98888-7777')$$,
  'telefone com codigo do Brasil e aceito'
);
reset role;

select is(
  (
    select phone
    from public.profiles
    where id = '91000000-0000-0000-0000-000000000001'
  ),
  '11988887777',
  'telefone fica persistido somente como numero nacional'
);

set local role authenticated;
select lives_ok(
  $$select public.upsert_current_profile('Maria da Silva', null, '')$$,
  'string vazia remove telefone'
);
reset role;

select is(
  (
    select phone
    from public.profiles
    where id = '91000000-0000-0000-0000-000000000001'
  ),
  null::text,
  'telefone foi removido'
);

set local role authenticated;
select throws_ok(
  $$select public.upsert_current_profile('Maria da Silva', null, '123')$$,
  'P0001',
  'Invalid phone',
  'telefone curto falha tambem no banco'
);

select throws_ok(
  $$select public.upsert_current_profile('Maria da Silva', null, 'abc11988887777')$$,
  'P0001',
  'Invalid phone',
  'telefone com letras nao e silenciosamente higienizado'
);

select lives_ok(
  $$select public.upsert_current_profile('Maria da Silva', '529.982.247-25', null)$$,
  'perfil incompleto pode definir CPF valido uma vez'
);
reset role;

select is(
  (
    select cpf
    from public.profiles
    where id = '91000000-0000-0000-0000-000000000001'
  ),
  '52998224725',
  'CPF inicial fica normalizado'
);

set local role authenticated;
select lives_ok(
  $$select public.upsert_current_profile('Maria da Silva', '52998224725', null)$$,
  'reenvio do mesmo CPF e idempotente'
);

select throws_ok(
  $$select public.upsert_current_profile('Maria da Silva', '11144477735', null)$$,
  'P0001',
  'CPF cannot be changed',
  'CPF preenchido nao pode ser substituido por cliente adulterado'
);
reset role;

select is(
  (
    select cpf
    from public.profiles
    where id = '91000000-0000-0000-0000-000000000001'
  ),
  '52998224725',
  'tentativa de troca preserva o CPF original'
);

set local role authenticated;
select lives_ok(
  $$select * from public.update_current_profile_customization(
    'Maria Perfil',
    '+55 (51) 99999-8888',
    'replace',
    '91000000-0000-0000-0000-000000000001/avatar-source.png'
  )$$,
  'customizacao atomica aceita objeto da pasta do titular'
);
reset role;

select is(
  (
    select full_name || '|' || initials || '|' || phone || '|' || avatar_url
    from public.profiles
    where id = '91000000-0000-0000-0000-000000000001'
  ),
  'Maria Perfil|MP|51999998888|/storage/v1/object/public/profile-avatars/91000000-0000-0000-0000-000000000001/avatar-source.png',
  'RPC persiste dados e deriva a URL do issuer assinado'
);

set local role authenticated;
select throws_ok(
  $$select * from public.update_current_profile_customization(
    'Nome que nao deve persistir',
    '1133334444',
    'replace',
    '91000000-0000-0000-0000-000000000002/avatar-delete.png'
  )$$,
  'P0001',
  'Invalid avatar path',
  'RPC rejeita avatar da pasta de outro usuario'
);
reset role;

select is(
  (
    select full_name || '|' || phone
    from public.profiles
    where id = '91000000-0000-0000-0000-000000000001'
  ),
  'Maria Perfil|51999998888',
  'falha do avatar reverte nome e telefone na mesma transacao'
);

set local role authenticated;
select lives_ok(
  $$select public.set_current_profile_avatar(null)$$,
  'titular pode remover a referencia do avatar'
);
reset role;

select is(
  (
    select avatar_url
    from public.profiles
    where id = '91000000-0000-0000-0000-000000000001'
  ),
  null::text,
  'remocao limpa avatar_url'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'profile_avatars_own_folder_delete'
      and cmd = 'DELETE'
  ),
  'policy dedicada de exclusao existe'
);

select set_config('storage.allow_delete_query', 'true', true);
set local role authenticated;
delete from storage.objects
where bucket_id = 'profile-avatars'
  and name = '91000000-0000-0000-0000-000000000001/avatar-delete.png';
delete from storage.objects
where bucket_id = 'profile-avatars'
  and name = '91000000-0000-0000-0000-000000000002/avatar-delete.png';
delete from storage.objects
where bucket_id = 'case-documents'
  and name = '91000000-0000-0000-0000-000000000001/not-an-avatar.png';
reset role;

select ok(
  not exists (
    select 1 from storage.objects
    where bucket_id = 'profile-avatars'
      and name = '91000000-0000-0000-0000-000000000001/avatar-delete.png'
  )
  and exists (
    select 1 from storage.objects
    where bucket_id = 'profile-avatars'
      and name = '91000000-0000-0000-0000-000000000002/avatar-delete.png'
  )
  and exists (
    select 1 from storage.objects
    where bucket_id = 'case-documents'
      and name = '91000000-0000-0000-0000-000000000001/not-an-avatar.png'
  ),
  'titular apaga apenas avatar: pasta alheia e documento de caso LIGADO ficam'
);

select ok(
  (
    select allowed_mime_types @> array[
      'image/jpeg',
      'image/png',
      'image/webp'
    ]::text[]
      and cardinality(allowed_mime_types) = 3
    from storage.buckets
    where id = 'profile-avatars'
  ),
  'bucket aceita somente os MIME types de imagem previstos'
);

select ok(
  (
    select file_size_limit = 10485760
    from storage.buckets
    where id = 'profile-avatars'
  ),
  'bucket compartilhado de avatar tem teto de 10 MB'
);

select * from finish();
rollback;
