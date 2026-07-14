begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(8);

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
values (
  '90000000-0000-0000-0000-000000000001',
  'authenticated',
  'authenticated',
  'account-deletion-rpc@jurii.test',
  '',
  now(),
  '{}'::jsonb,
  '{"full_name":"Burner RPC"}'::jsonb,
  now(),
  now()
);

update public.profiles
set avatar_url =
  'https://project.supabase.co/storage/v1/object/public/profile-avatars/' ||
  '90000000-0000-0000-0000-000000000001/avatar%20principal.png?width=256'
where id = '90000000-0000-0000-0000-000000000001';

insert into public.lawyer_verifications (
  id,
  user_id,
  oab_number,
  oab_state,
  practice_area,
  status
)
values (
  '90000000-0000-0000-0000-000000000002',
  '90000000-0000-0000-0000-000000000001',
  '900001',
  'SP',
  'Direito Civil',
  'pending'
);

insert into public.verification_documents (
  verification_id,
  user_id,
  document_type,
  title,
  storage_path
)
values (
  '90000000-0000-0000-0000-000000000002',
  '90000000-0000-0000-0000-000000000001',
  'identity',
  'Identidade',
  '90000000-0000-0000-0000-000000000001/identidade.pdf'
);

insert into public.verification_documents (
  verification_id,
  user_id,
  document_type,
  title,
  storage_path
)
values (
  '90000000-0000-0000-0000-000000000002',
  '90000000-0000-0000-0000-000000000001',
  'oab_card',
  'Path adulterado',
  '90000000-0000-0000-0000-000000000099/arquivo-alheio.pdf'
);

insert into public.law_firm_verifications (
  id,
  owner_profile_id,
  firm_name,
  cnpj,
  status
)
values (
  '90000000-0000-0000-0000-000000000003',
  '90000000-0000-0000-0000-000000000001',
  'Escritorio Burner RPC',
  '00000000000100',
  'pending'
);

insert into public.law_firm_verification_documents (
  verification_id,
  owner_profile_id,
  document_type,
  title,
  storage_path
)
values (
  '90000000-0000-0000-0000-000000000003',
  '90000000-0000-0000-0000-000000000001',
  'cnpj_registration',
  'Cartao CNPJ',
  '90000000-0000-0000-0000-000000000001/cartao-cnpj.pdf'
);

insert into public.law_firm_verification_documents (
  verification_id,
  owner_profile_id,
  document_type,
  title,
  storage_path
)
values (
  '90000000-0000-0000-0000-000000000003',
  '90000000-0000-0000-0000-000000000001',
  'address_proof',
  'Path adulterado',
  '90000000-0000-0000-0000-000000000099/endereco-alheio.pdf'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.get_account_deletion_storage_paths(uuid)',
    'EXECUTE'
  ),
  'service_role pode executar a RPC administrativa'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.get_account_deletion_storage_paths(uuid)',
    'EXECUTE'
  ),
  'authenticated nao pode executar a RPC administrativa'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.get_account_deletion_storage_paths(uuid)',
    'EXECUTE'
  ),
  'anon nao pode executar a RPC administrativa'
);

select ok(
  not has_table_privilege('service_role', 'public.profiles', 'SELECT'),
  'RPC nao exige liberar SELECT direto em profiles'
);

select ok(
  not has_table_privilege(
    'service_role',
    'public.verification_documents',
    'SELECT'
  ),
  'RPC nao exige liberar SELECT direto em verification_documents'
);

select ok(
  not has_table_privilege(
    'service_role',
    'public.law_firm_verification_documents',
    'SELECT'
  ),
  'RPC nao exige liberar SELECT direto em documentos de escritorio'
);

set local role service_role;

select results_eq(
  $$
    select bucket_id, storage_path
    from public.get_account_deletion_storage_paths(
      '90000000-0000-0000-0000-000000000001'
    )
    order by bucket_id, storage_path
  $$,
  $$
    values
      (
        'profile-avatars'::text,
        '90000000-0000-0000-0000-000000000001/avatar%20principal.png'::text
      ),
      (
        'verification-documents'::text,
        '90000000-0000-0000-0000-000000000001/cartao-cnpj.pdf'::text
      ),
      (
        'verification-documents'::text,
        '90000000-0000-0000-0000-000000000001/identidade.pdf'::text
      )
  $$,
  'service_role recebe somente bucket e caminho dos objetos da conta'
);

reset role;

update public.profiles
set avatar_url =
  'https://project.supabase.co/storage/v1/object/public/profile-avatars/' ||
  '90000000-0000-0000-0000-000000000099/avatar-alheio.png'
where id = '90000000-0000-0000-0000-000000000001';

set local role service_role;

select is(
  (
    select count(*)::int
    from public.get_account_deletion_storage_paths(
      '90000000-0000-0000-0000-000000000001'
    )
    where bucket_id = 'profile-avatars'
  ),
  0,
  'RPC ignora avatar que aponta para a pasta de outro usuario'
);

reset role;
select * from finish();
rollback;
