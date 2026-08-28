begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(39);

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
    '93000000-0000-0000-0000-000000000001',
    'authenticated',
    'authenticated',
    'firm-avatar-owner@jurii.test',
    '',
    now(),
    '{}'::jsonb,
    '{"full_name":"Dona do Escritorio"}'::jsonb,
    now(),
    now()
  ),
  (
    '93000000-0000-0000-0000-000000000002',
    'authenticated',
    'authenticated',
    'firm-avatar-other@jurii.test',
    '',
    now(),
    '{}'::jsonb,
    '{"full_name":"Outro Responsavel"}'::jsonb,
    now(),
    now()
  ),
  (
    '93000000-0000-0000-0000-000000000003',
    'authenticated',
    'authenticated',
    'firm-avatar-client@jurii.test',
    '',
    now(),
    '{}'::jsonb,
    '{"full_name":"Cliente do Escritorio"}'::jsonb,
    now(),
    now()
  ),
  (
    '93000000-0000-0000-0000-000000000004',
    'authenticated',
    'authenticated',
    'firm-avatar-reviewer@jurii.test',
    '',
    now(),
    '{}'::jsonb,
    '{"full_name":"Revisora Jurii"}'::jsonb,
    now(),
    now()
  );

insert into public.law_firm_verifications (
  id,
  owner_profile_id,
  firm_name,
  cnpj,
  phone,
  email,
  address,
  practice_areas,
  status,
  avatar_storage_path
)
values
  (
    '93100000-0000-0000-0000-000000000001',
    '93000000-0000-0000-0000-000000000001',
    'Avatar Advocacia',
    '00000000000191',
    '51999990001',
    'contato@avatar.test',
    'Rua da Foto, 100',
    array['Direito Civil'],
    'pending',
    null
  ),
  (
    '93100000-0000-0000-0000-000000000002',
    '93000000-0000-0000-0000-000000000002',
    'Sem Foto Legal',
    '00000000000272',
    null,
    null,
    null,
    array['Direito Trabalhista'],
    'pending',
    null
  ),
  (
    '93100000-0000-0000-0000-000000000003',
    '93000000-0000-0000-0000-000000000001',
    'Foto Recusada Legal',
    '00000000000353',
    null,
    null,
    null,
    array['Direito Civil'],
    'rejected',
    '93000000-0000-0000-0000-000000000001/93100000-0000-0000-0000-000000000003/rejeitada.png'
  ),
  (
    '93100000-0000-0000-0000-000000000004',
    '93000000-0000-0000-0000-000000000001',
    'Objeto Ausente Legal',
    '00000000000434',
    null,
    null,
    null,
    array['Direito Civil'],
    'pending',
    '93000000-0000-0000-0000-000000000001/93100000-0000-0000-0000-000000000004/ausente.png'
  );

insert into storage.objects (bucket_id, name, owner_id, metadata)
values
  (
    'law-firm-avatars',
    '93000000-0000-0000-0000-000000000001/93100000-0000-0000-0000-000000000001/avatar.png',
    '93000000-0000-0000-0000-000000000001',
    '{"mimetype":"image/png"}'::jsonb
  ),
  (
    'law-firm-avatars',
    '93000000-0000-0000-0000-000000000001/93100000-0000-0000-0000-000000000003/rejeitada.png',
    '93000000-0000-0000-0000-000000000001',
    '{"mimetype":"image/png"}'::jsonb
  );

select has_column(
  'public',
  'law_firm_verifications',
  'avatar_storage_path',
  'verificacao de escritorio guarda caminho opcional do avatar'
);

select has_column(
  'public',
  'law_firms',
  'avatar_url',
  'escritorio aprovado guarda URL publica do avatar'
);

select ok(
  (
    select bucket.public
      and bucket.file_size_limit = 10485760
      and bucket.allowed_mime_types =
        array['image/jpeg', 'image/png', 'image/webp']::text[]
    from storage.buckets bucket
    where bucket.id = 'law-firm-avatars'
  ),
  'bucket dedicado e publico com limite e allowlist de imagens'
);

select is(
  (
    select count(*)::int
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      -- A de leitura virou own_folder na 20260922120000: dava select ao
      -- papel `public` no balde inteiro, e com isso a listagem anônima
      -- entregava quem tem verificação de escritório em andamento. O
      -- download do logo não depende dela (o balde é public=true e
      -- /object/public/ não passa por RLS).
      and policyname in (
        'law_firm_avatars_own_folder_read',
        'law_firm_avatars_pending_owner_insert',
        'law_firm_avatars_unapproved_owner_delete'
      )
  ),
  3,
  'bucket possui policies explicitas de leitura, envio e remocao'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.set_current_law_firm_verification_avatar(uuid,text)',
    'EXECUTE'
  ),
  'authenticated pode associar avatar a propria verificacao'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.set_current_law_firm_verification_avatar(uuid,text)',
    'EXECUTE'
  ),
  'anon nao associa avatar de escritorio'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.safe_law_firm_avatar_url(uuid,uuid,text)',
    'EXECUTE'
  ),
  'helper interno de validacao nao fica exposto ao app'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.approve_law_firm_verification(uuid,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.approve_law_firm_verification(uuid,uuid)',
    'EXECUTE'
  ),
  'aprovacao continua exclusiva do service_role'
);

select ok(
  not has_column_privilege(
    'authenticated',
    'public.law_firm_verifications',
    'avatar_storage_path',
    'UPDATE'
  ),
  'avatar_storage_path nao aceita update direto'
);

select ok(
  not has_column_privilege(
    'authenticated',
    'public.law_firm_verifications',
    'law_firm_id',
    'INSERT'
  )
  and not has_column_privilege(
    'authenticated',
    'public.law_firm_verifications',
    'law_firm_id',
    'UPDATE'
  ),
  'cliente nao escolhe o escritorio vinculado'
);

select ok(
  not has_column_privilege(
    'authenticated',
    'public.law_firm_verifications',
    'id',
    'INSERT'
  )
  and not has_column_privilege(
    'authenticated',
    'public.law_firm_verifications',
    'id',
    'UPDATE'
  ),
  'cliente nao escolhe nem altera o id da verificacao'
);

select ok(
  not has_column_privilege(
    'authenticated',
    'public.law_firm_verifications',
    'reviewer_id',
    'INSERT'
  )
  and not has_column_privilege(
    'authenticated',
    'public.law_firm_verifications',
    'reviewer_id',
    'UPDATE'
  ),
  'cliente nao escolhe nem altera o revisor'
);

select set_config(
  'request.jwt.claim.sub',
  '93000000-0000-0000-0000-000000000001',
  true
);
-- A paywall do licenciamento (20260821120000) exige assinatura para INSERIR
-- verificacao; o fixture abaixo e o pedagio deste teste, que testa OUTRA
-- coisa.
-- Uma por dono: desde a 20260906120000 a APROVACAO tambem exige licenca nao
-- gasta, e nao so o pedido. Sem a linha do segundo dono, a aprovacao dele
-- falharia por falta de licenca num teste que fala de foto.
insert into public.law_firm_license_subscriptions
  (owner_profile_id, plan_code, status, trial_ends_at)
values
  ('93000000-0000-0000-0000-000000000001', 'escritorio', 'trialing',
   now() + interval '30 days'),
  ('93000000-0000-0000-0000-000000000002', 'escritorio', 'trialing',
   now() + interval '30 days');

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"93000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

select lives_ok(
  $$
    insert into public.law_firm_verifications (
      owner_profile_id,
      firm_name,
      cnpj,
      status,
      practice_areas
    ) values (
      '93000000-0000-0000-0000-000000000001',
      'Cadastro Compativel',
      '00000000000515',
      'pending',
      array['Direito Civil']
    )
  $$,
  'insert usado pelo app permanece permitido'
);

select throws_ok(
  $$
    insert into public.law_firm_verifications (
      id,
      owner_profile_id,
      firm_name,
      cnpj,
      status
    ) values (
      '93100000-0000-0000-0000-000000000099',
      '93000000-0000-0000-0000-000000000001',
      'ID Forjado',
      '00000000000949',
      'pending'
    )
  $$,
  '42501',
  null,
  'insert direto nao aceita id escolhido pelo cliente'
);

select throws_ok(
  $$
    insert into public.law_firm_verifications (
      owner_profile_id,
      firm_name,
      cnpj,
      status
    ) values (
      '93000000-0000-0000-0000-000000000001',
      'Aprovacao Forjada',
      '00000000000604',
      'approved'
    )
  $$,
  '42501',
  null,
  'cliente nao insere verificacao ja aprovada'
);

select throws_ok(
  $$
    insert into public.law_firm_verifications (
      owner_profile_id,
      firm_name,
      cnpj,
      status
    ) values (
      '93000000-0000-0000-0000-000000000002',
      'Cadastro de Terceiro',
      '00000000000787',
      'pending'
    )
  $$,
  '42501',
  null,
  'cliente nao cria verificacao para outro titular'
);

select throws_ok(
  $$
    update public.law_firm_verifications
    set avatar_storage_path =
      '93000000-0000-0000-0000-000000000001/93100000-0000-0000-0000-000000000001/direto.png'
    where id = '93100000-0000-0000-0000-000000000001'
  $$,
  '42501',
  null,
  'cliente nao contorna a RPC com update direto do avatar'
);

select throws_ok(
  $$
    update public.law_firm_verifications
    set law_firm_id = '93200000-0000-0000-0000-000000000001'
    where id = '93100000-0000-0000-0000-000000000001'
  $$,
  '42501',
  null,
  'cliente nao aponta verificacao pendente para firma arbitraria'
);

select throws_ok(
  $$
    update public.law_firm_verifications
    set reviewer_id = '93000000-0000-0000-0000-000000000004'
    where id = '93100000-0000-0000-0000-000000000001'
  $$,
  '42501',
  null,
  'update direto nao aceita revisor escolhido pelo cliente'
);

select lives_ok(
  $$
    update public.law_firm_verifications
    set phone = '51988887777'
    where id = '93100000-0000-0000-0000-000000000001'
  $$,
  'edicao dos campos do formulario pendente continua permitida'
);

select is(
  public.set_current_law_firm_verification_avatar(
    '93100000-0000-0000-0000-000000000001',
    '93000000-0000-0000-0000-000000000001/93100000-0000-0000-0000-000000000001/avatar.png'
  ),
  '/storage/v1/object/public/law-firm-avatars/93000000-0000-0000-0000-000000000001/93100000-0000-0000-0000-000000000001/avatar.png',
  'setter associa objeto valido e retorna somente URL relativa'
);

select throws_ok(
  $$
    select public.set_current_law_firm_verification_avatar(
      '93100000-0000-0000-0000-000000000001',
      '93000000-0000-0000-0000-000000000001/93100000-0000-0000-0000-000000000001/inexistente.png'
    )
  $$,
  'P0001',
  'Invalid law firm avatar path',
  'setter rejeita path sem objeto no bucket'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  '93000000-0000-0000-0000-000000000002',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"93000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  $$
    select public.set_current_law_firm_verification_avatar(
      '93100000-0000-0000-0000-000000000001',
      '93000000-0000-0000-0000-000000000001/93100000-0000-0000-0000-000000000001/avatar.png'
    )
  $$,
  'P0001',
  'Law firm verification not found',
  'outro usuario nao associa nem enumera avatar alheio'
);

reset role;

select throws_ok(
  $$
    update public.law_firm_verifications
    set avatar_storage_path = 'caminho-invalido'
    where id = '93100000-0000-0000-0000-000000000004'
  $$,
  '23514',
  null,
  'constraint rejeita formato de path adulterado'
);

select throws_ok(
  $$
    update public.law_firm_verifications
    set avatar_storage_path =
      '93000000-0000-0000-0000-000000000001/avatar.png'
    where id = '93100000-0000-0000-0000-000000000004'
  $$,
  '23514',
  null,
  'constraint rejeita path com somente uma pasta'
);

set local role service_role;

select lives_ok(
  $$
    select public.approve_law_firm_verification(
      '93100000-0000-0000-0000-000000000001',
      '93000000-0000-0000-0000-000000000004'
    )
  $$,
  'aprovacao com foto valida conclui'
);

reset role;

select is(
  (
    select firm.avatar_url
    from public.law_firms firm
    join public.law_firm_verifications verification
      on verification.law_firm_id = firm.id
    where verification.id = '93100000-0000-0000-0000-000000000001'
  ),
  '/storage/v1/object/public/law-firm-avatars/93000000-0000-0000-0000-000000000001/93100000-0000-0000-0000-000000000001/avatar.png',
  'aprovacao copia URL relativa validada para o escritorio'
);

select is(
  (
    select member.roles
    from public.law_firm_members member
    join public.law_firm_verifications verification
      on verification.law_firm_id = member.law_firm_id
    where verification.id = '93100000-0000-0000-0000-000000000001'
      and member.profile_id = '93000000-0000-0000-0000-000000000001'
  ),
  array['owner']::text[],
  'aprovacao cria membership com papel owner efetivo'
);

set local role service_role;

select lives_ok(
  $$
    select public.approve_law_firm_verification(
      '93100000-0000-0000-0000-000000000002',
      '93000000-0000-0000-0000-000000000004'
    )
  $$,
  'foto ausente continua valida na aprovacao'
);

reset role;

select is(
  (
    select firm.avatar_url
    from public.law_firms firm
    join public.law_firm_verifications verification
      on verification.law_firm_id = firm.id
    where verification.id = '93100000-0000-0000-0000-000000000002'
  ),
  null::text,
  'escritorio aprovado sem foto preserva fallback por iniciais'
);

set local role service_role;

select throws_ok(
  $$
    select public.approve_law_firm_verification(
      '93100000-0000-0000-0000-000000000004',
      '93000000-0000-0000-0000-000000000004'
    )
  $$,
  'P0001',
  'Invalid law firm avatar path',
  'aprovacao falha fechada quando o objeto referenciado sumiu'
);

reset role;

select is(
  (
    select status
    from public.law_firm_verifications
    where id = '93100000-0000-0000-0000-000000000004'
  ),
  'pending'::public.verification_status,
  'falha do avatar nao aprova parcialmente a verificacao'
);

select set_config(
  'request.jwt.claim.sub',
  '93000000-0000-0000-0000-000000000003',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"93000000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);
set local role authenticated;

select is(
  (
    select recommended.avatar_url
    from public.fetch_recommended_law_firms(30, 'Avatar Advocacia') recommended
  ),
  '/storage/v1/object/public/law-firm-avatars/93000000-0000-0000-0000-000000000001/93100000-0000-0000-0000-000000000001/avatar.png',
  'cards recomendados recebem avatar do escritorio'
);

reset role;

insert into public.conversations (
  id,
  client_id,
  law_firm_id,
  title,
  type,
  specialty
)
select
  '93300000-0000-0000-0000-000000000001',
  '93000000-0000-0000-0000-000000000003',
  verification.law_firm_id,
  'Conversa com escritorio avatar',
  'client_firm',
  'Direito Civil'
from public.law_firm_verifications verification
where verification.id = '93100000-0000-0000-0000-000000000001';

insert into public.messages (
  id,
  conversation_id,
  sender_id,
  sender_type,
  body
)
values (
  '93400000-0000-0000-0000-000000000001',
  '93300000-0000-0000-0000-000000000001',
  '93000000-0000-0000-0000-000000000003',
  'client',
  'Mensagem que torna a conversa visivel'
);

set local role authenticated;

select is(
  (
    select conversation.avatar_url
    from public.fetch_conversations_for_current_user('client', null) conversation
    where conversation.id = '93300000-0000-0000-0000-000000000001'
  ),
  '/storage/v1/object/public/law-firm-avatars/93000000-0000-0000-0000-000000000001/93100000-0000-0000-0000-000000000001/avatar.png',
  'lista de conversas do cliente recebe avatar do escritorio'
);

select is(
  (
    select conversation.avatar_url
    from public.fetch_conversation_for_current_user(
      '93300000-0000-0000-0000-000000000001'
    ) conversation
  ),
  '/storage/v1/object/public/law-firm-avatars/93000000-0000-0000-0000-000000000001/93100000-0000-0000-0000-000000000001/avatar.png',
  'cabecalho do chat recebe avatar do escritorio'
);

reset role;

select ok(
  has_function_privilege(
    'service_role',
    'public.get_account_deletion_storage_paths(uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.get_account_deletion_storage_paths(uuid)',
    'EXECUTE'
  ),
  'RPC de paths permanece administrativa'
);

set local role service_role;

select is(
  (
    select count(*)::int
    from public.get_account_deletion_storage_paths(
      '93000000-0000-0000-0000-000000000001'
    ) paths
    where paths.bucket_id = 'law-firm-avatars'
      and paths.storage_path =
        '93000000-0000-0000-0000-000000000001/93100000-0000-0000-0000-000000000001/avatar.png'
  ),
  0,
  'exclusao de owner preserva avatar de escritorio aprovado'
);

select is(
  (
    select count(*)::int
    from public.get_account_deletion_storage_paths(
      '93000000-0000-0000-0000-000000000001'
    ) paths
    where paths.bucket_id = 'law-firm-avatars'
      and paths.storage_path =
        '93000000-0000-0000-0000-000000000001/93100000-0000-0000-0000-000000000003/rejeitada.png'
  ),
  1,
  'exclusao inclui avatar de verificacao nao aprovada'
);

reset role;

select throws_ok(
  $$
    insert into public.law_firms (
      name,
      initials,
      specialty,
      avatar_url
    ) values (
      'URL Externa',
      'UE',
      'Civil',
      'https://tracker.example/logo.png'
    )
  $$,
  '23514',
  null,
  'constraint impede URL externa no avatar do escritorio'
);

select * from finish();
rollback;
