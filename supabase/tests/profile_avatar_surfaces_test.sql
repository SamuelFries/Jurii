begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(20);

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
    '92000000-0000-0000-0000-000000000001',
    'authenticated',
    'authenticated',
    'avatar-client@jurii.test',
    '',
    now(),
    '{}'::jsonb,
    '{"full_name":"Cliente Avatar"}'::jsonb,
    now(),
    now()
  ),
  (
    '92000000-0000-0000-0000-000000000002',
    'authenticated',
    'authenticated',
    'avatar-lawyer@jurii.test',
    '',
    now(),
    '{}'::jsonb,
    '{"full_name":"Advogada Avatar"}'::jsonb,
    now(),
    now()
  );

insert into storage.objects (bucket_id, name, owner_id, metadata)
values
  (
    'profile-avatars',
    '92000000-0000-0000-0000-000000000001/avatar.png',
    '92000000-0000-0000-0000-000000000001',
    '{}'::jsonb
  ),
  (
    'profile-avatars',
    '92000000-0000-0000-0000-000000000002/avatar.png',
    '92000000-0000-0000-0000-000000000002',
    '{}'::jsonb
  );

update public.profiles
set
  avatar_url = case id
    when '92000000-0000-0000-0000-000000000001'
      then 'https://tracker.example/storage/v1/object/public/profile-avatars/92000000-0000-0000-0000-000000000001/avatar.png'
    else 'https://tracker.example/storage/v1/object/public/profile-avatars/92000000-0000-0000-0000-000000000002/avatar.png'
  end,
  lawyer_status = case id
    when '92000000-0000-0000-0000-000000000002'
      then 'approved'::public.lawyer_status
    else lawyer_status
  end
where id in (
  '92000000-0000-0000-0000-000000000001',
  '92000000-0000-0000-0000-000000000002'
);

insert into public.lawyer_profiles (
  id,
  oab_number,
  oab_state,
  primary_area,
  practice_areas,
  approved_at
)
values (
  '92000000-0000-0000-0000-000000000002',
  '920002',
  'RS',
  'Direito Civil',
  array['Direito Civil'],
  now()
);

insert into public.conversations (
  id,
  client_id,
  lawyer_id,
  title,
  type
)
values (
  '92000000-0000-0000-0000-000000000003',
  '92000000-0000-0000-0000-000000000001',
  '92000000-0000-0000-0000-000000000002',
  'Conversa com avatar',
  'client_firm'
);

insert into public.messages (
  id,
  conversation_id,
  sender_id,
  sender_type,
  body
)
values (
  '92000000-0000-0000-0000-000000000004',
  '92000000-0000-0000-0000-000000000003',
  '92000000-0000-0000-0000-000000000001',
  'client',
  'Mensagem para tornar a conversa visivel'
);

select ok(
  has_function_privilege(
    'authenticated',
    -- Assinatura ganhou offset_value na 20260803120000 (paginação).
    'public.fetch_recommended_lawyers(integer,text,integer)',
    'EXECUTE'
  ),
  'authenticated pode listar advogados com avatar'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.fetch_lawyer_public_profile(uuid)',
    'EXECUTE'
  ),
  'authenticated pode abrir mini perfil de advogado'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.fetch_chat_profile(uuid)',
    'EXECUTE'
  ),
  'authenticated pode abrir mini perfil de contraparte autorizada'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.fetch_conversation_for_current_user(uuid)',
    'EXECUTE'
  ),
  'authenticated pode buscar uma conversa com avatar'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.fetch_conversations_for_current_user(text,uuid)',
    'EXECUTE'
  ),
  'authenticated pode listar conversas com avatar'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.fetch_recommended_lawyers(integer,text,integer)',
    'EXECUTE'
  ),
  'anon nao lista advogados por RPC'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.fetch_lawyer_public_profile(uuid)',
    'EXECUTE'
  ),
  'anon nao abre mini perfil de advogado'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.fetch_chat_profile(uuid)',
    'EXECUTE'
  ),
  'anon nao abre mini perfil de contraparte'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.fetch_conversation_for_current_user(uuid)',
    'EXECUTE'
  ),
  'anon nao busca conversa'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.fetch_conversations_for_current_user(text,uuid)',
    'EXECUTE'
  ),
  'anon nao lista conversas'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.safe_profile_avatar_url(uuid,text)',
    'EXECUTE'
  ),
  'helper de normalizacao nao fica exposto ao app'
);
select is(
  public.safe_profile_avatar_url(
    '92000000-0000-0000-0000-000000000001',
    'https://tracker.example/storage/v1/object/public/profile-avatars/92000000-0000-0000-0000-000000000001/avatar.png'
  ),
  '/storage/v1/object/public/profile-avatars/92000000-0000-0000-0000-000000000001/avatar.png',
  'helper troca host legado pelo caminho relativo de objeto valido'
);
select is(
  public.safe_profile_avatar_url(
    '92000000-0000-0000-0000-000000000001',
    'https://tracker.example/avatar.png'
  ),
  null::text,
  'helper rejeita URL externa sem objeto local correspondente'
);

select set_config(
  'request.jwt.claim.sub',
  '92000000-0000-0000-0000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"92000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

select is(
  (
    select avatar_url
    from public.fetch_recommended_lawyers(6, null)
    where id = '92000000-0000-0000-0000-000000000002'
  ),
  '/storage/v1/object/public/profile-avatars/92000000-0000-0000-0000-000000000002/avatar.png',
  'card recomendado recebe o avatar do advogado'
);
select is(
  (
    select avatar_url
    from public.fetch_lawyer_public_profile(
      '92000000-0000-0000-0000-000000000002'
    )
  ),
  '/storage/v1/object/public/profile-avatars/92000000-0000-0000-0000-000000000002/avatar.png',
  'mini perfil do advogado recebe o avatar'
);
select is(
  (
    select avatar_url
    from public.fetch_conversations_for_current_user('client', null)
    where id = '92000000-0000-0000-0000-000000000003'
  ),
  '/storage/v1/object/public/profile-avatars/92000000-0000-0000-0000-000000000002/avatar.png',
  'cliente recebe avatar do advogado na lista de conversas'
);
select is(
  (
    select avatar_url
    from public.fetch_conversation_for_current_user(
      '92000000-0000-0000-0000-000000000003'
    )
  ),
  '/storage/v1/object/public/profile-avatars/92000000-0000-0000-0000-000000000002/avatar.png',
  'cliente recebe avatar do advogado ao abrir a conversa'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  '92000000-0000-0000-0000-000000000002',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"92000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);
set local role authenticated;

select is(
  (
    select avatar_url
    from public.fetch_chat_profile(
      '92000000-0000-0000-0000-000000000001'
    )
  ),
  '/storage/v1/object/public/profile-avatars/92000000-0000-0000-0000-000000000001/avatar.png',
  'mini perfil do cliente recebe o avatar sem expor PII adicional'
);
select is(
  (
    select avatar_url
    from public.fetch_conversations_for_current_user('lawyer', null)
    where id = '92000000-0000-0000-0000-000000000003'
  ),
  '/storage/v1/object/public/profile-avatars/92000000-0000-0000-0000-000000000001/avatar.png',
  'advogado recebe avatar do cliente na lista de conversas'
);
select is(
  (
    select avatar_url
    from public.fetch_conversation_for_current_user(
      '92000000-0000-0000-0000-000000000003'
    )
  ),
  '/storage/v1/object/public/profile-avatars/92000000-0000-0000-0000-000000000001/avatar.png',
  'advogado recebe avatar do cliente ao abrir a conversa'
);

reset role;

select * from finish();
rollback;
