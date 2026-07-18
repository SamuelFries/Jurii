begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(61);

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

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
  ('10000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'owner@jurii.test', '', now(), '{}'::jsonb, '{"full_name":"Owner Ativo"}'::jsonb, now(), now()),
  ('10000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'outsider@jurii.test', '', now(), '{}'::jsonb, '{"full_name":"Pessoa Externa"}'::jsonb, now(), now()),
  ('10000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'lawyer@jurii.test', '', now(), '{}'::jsonb, '{"full_name":"Advogada Aprovada"}'::jsonb, now(), now()),
  ('10000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'client@jurii.test', '', now(), '{}'::jsonb, '{"full_name":"Cliente Relacionado"}'::jsonb, now(), now()),
  ('10000000-0000-0000-0000-000000000005', 'authenticated', 'authenticated', 'former@jurii.test', '', now(), '{}'::jsonb, '{"full_name":"Ex Dono"}'::jsonb, now(), now()),
  ('10000000-0000-0000-0000-000000000006', 'authenticated', 'authenticated', 'member@jurii.test', '', now(), '{}'::jsonb, '{"full_name":"Membro Ativo"}'::jsonb, now(), now()),
  ('10000000-0000-0000-0000-000000000007', 'authenticated', 'authenticated', 'lawyer2@jurii.test', '', now(), '{}'::jsonb, '{"full_name":"Advogado Dois"}'::jsonb, now(), now());

update public.profiles
set
  cpf = case id
    when '10000000-0000-0000-0000-000000000004' then '52998224725'
    else cpf
  end,
  phone = case id
    when '10000000-0000-0000-0000-000000000004' then '11999999999'
    else phone
  end,
  lawyer_status = case
    when id in (
      '10000000-0000-0000-0000-000000000003',
      '10000000-0000-0000-0000-000000000007'
    ) then 'approved'::public.lawyer_status
    else lawyer_status
  end;

insert into public.law_firms (
  id,
  name,
  initials,
  specialty,
  is_active
)
values
  ('20000000-0000-0000-0000-000000000001', 'Firma A', 'FA', 'Civil', true),
  ('20000000-0000-0000-0000-000000000002', 'Firma B', 'FB', 'Civil', true),
  ('20000000-0000-0000-0000-000000000003', 'Firma C', 'FC', 'Civil', true);

insert into public.lawyer_profiles (
  id,
  oab_number,
  oab_state,
  primary_area,
  practice_areas,
  approved_at
)
values
  ('10000000-0000-0000-0000-000000000003', '12345', 'SP', 'Direito Civil', array['Direito Civil'], now() - interval '2 days'),
  ('10000000-0000-0000-0000-000000000007', '77777', 'RJ', 'Direito Civil', array['Direito Civil'], now() - interval '2 days');

insert into public.lawyer_verifications (
  id,
  user_id,
  oab_number,
  oab_state,
  practice_area,
  practice_areas,
  status,
  submitted_at,
  reviewed_at
)
values
  ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000003', '12345', 'SP', 'Direito Civil', array['Direito Civil'], 'approved', now() - interval '3 days', now() - interval '2 days'),
  ('30000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000007', '77777', 'RJ', 'Direito Civil', array['Direito Civil'], 'approved', now() - interval '3 days', now() - interval '2 days');

insert into public.law_firm_members (
  law_firm_id,
  profile_id,
  role,
  member_role,
  roles,
  status
)
values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'owner', 'owner', array['owner'], 'active'),
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000006', 'secretary', 'secretary', array['secretary'], 'active'),
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000005', 'owner', 'owner', array['owner'], 'disabled'),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 'owner', 'owner', array['owner'], 'active'),
  ('20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', 'owner', 'owner', array['owner'], 'active');

insert into public.law_firm_verifications (
  owner_profile_id,
  law_firm_id,
  firm_name,
  cnpj,
  status,
  reviewed_at
)
values (
  '10000000-0000-0000-0000-000000000005',
  '20000000-0000-0000-0000-000000000001',
  'Firma A',
  '00000000000100',
  'approved',
  now() - interval '10 days'
);

insert into public.conversations (
  id,
  client_id,
  lawyer_id,
  title,
  type
)
values (
  '40000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000004',
  '10000000-0000-0000-0000-000000000003',
  'Atendimento de teste',
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
  '50000000-0000-0000-0000-000000000001',
  '40000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000004',
  'client',
  'Anexo enviado'
);

insert into public.message_attachments (
  id,
  message_id,
  conversation_id,
  uploaded_by,
  file_name,
  mime_type,
  file_size_bytes,
  storage_path,
  kind
)
values (
  '60000000-0000-0000-0000-000000000001',
  '50000000-0000-0000-0000-000000000001',
  '40000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000004',
  'prova.pdf',
  'application/pdf',
  128,
  '10000000-0000-0000-0000-000000000004/prova.pdf',
  'document'
);

-- ---------------------------------------------------------------------------
-- Grants e contratos
-- ---------------------------------------------------------------------------

select ok(
  not has_column_privilege('authenticated', 'public.profiles', 'email', 'SELECT'),
  'authenticated nao seleciona email diretamente'
);
select ok(
  not has_column_privilege('authenticated', 'public.profiles', 'cpf', 'SELECT'),
  'authenticated nao seleciona CPF diretamente'
);
select ok(
  not has_column_privilege('authenticated', 'public.profiles', 'phone', 'SELECT'),
  'authenticated nao seleciona telefone diretamente'
);
select ok(
  has_column_privilege('authenticated', 'public.profiles', 'full_name', 'SELECT'),
  'authenticated seleciona o nome publico'
);
select ok(
  has_function_privilege('authenticated', 'public.fetch_current_profile()', 'EXECUTE'),
  'titular pode executar fetch_current_profile'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.upsert_current_profile(text,text,text)',
    'EXECUTE'
  ),
  'titular pode executar upsert_current_profile'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.upsert_current_profile(text,text,text)',
    'EXECUTE'
  ),
  'anon nao executa upsert_current_profile'
);
select ok(
  not has_any_column_privilege(
    'authenticated',
    'public.profiles',
    'INSERT'
  ),
  'insert direto em profiles foi revogado'
);
select ok(
  not has_column_privilege(
    'authenticated',
    'public.profiles',
    'email',
    'UPDATE'
  ),
  'update direto de email foi revogado'
);
select ok(
  not has_column_privilege(
    'authenticated',
    'public.profiles',
    'avatar_url',
    'UPDATE'
  ),
  'update direto de avatar foi substituido por RPC validada'
);
select ok(
  not has_table_privilege('authenticated', 'public.conversations', 'INSERT'),
  'insert direto em conversas foi revogado'
);
select ok(
  not has_table_privilege('authenticated', 'public.conversations', 'UPDATE'),
  'update direto em conversas foi revogado'
);
select ok(
  not has_table_privilege('authenticated', 'public.appointments', 'INSERT'),
  'insert direto em agenda foi revogado'
);
select ok(
  not has_table_privilege('authenticated', 'public.appointments', 'UPDATE'),
  'update direto em agenda foi revogado'
);
select ok(
  not has_table_privilege('authenticated', 'public.law_firm_members', 'INSERT'),
  'insert direto em memberships foi revogado'
);
select ok(
  not has_table_privilege('authenticated', 'public.law_firm_members', 'UPDATE'),
  'update direto em memberships foi revogado'
);
select ok(
  has_function_privilege('authenticated', 'public.start_or_get_lawyer_conversation(uuid,text)', 'EXECUTE'),
  'RPC segura de conversa com advogado continua disponivel'
);
select ok(
  has_function_privilege('authenticated', 'public.start_or_get_law_firm_conversation(uuid,text)', 'EXECUTE'),
  'RPC segura de conversa com escritorio continua disponivel'
);
select ok(
  not has_function_privilege('anon', 'public.current_law_firm_member_roles(uuid,uuid)', 'EXECUTE'),
  'anon nao consulta cargos de escritorio'
);

-- ---------------------------------------------------------------------------
-- RLS, PII e autoridade de escritorio
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select is(
  (select count(*)::int from public.law_firm_members where law_firm_id = '20000000-0000-0000-0000-000000000001'),
  3,
  'owner ativo ve o roster completo do proprio escritorio'
);
select ok(
  public.is_active_law_firm_manager('20000000-0000-0000-0000-000000000001'),
  'owner ativo e manager'
);
select ok(
  public.is_active_law_firm_case_manager('20000000-0000-0000-0000-000000000001'),
  'owner ativo gerencia casos'
);

reset role;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
set local role authenticated;

select is(
  (select count(*)::int from public.law_firm_members where law_firm_id = '20000000-0000-0000-0000-000000000001'),
  0,
  'pessoa externa nao enumera roster de escritorio ativo'
);

reset role;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000005', true);
set local role authenticated;

select is(
  (select count(*)::int from public.law_firm_members where law_firm_id = '20000000-0000-0000-0000-000000000001'),
  1,
  'ex-membro ve somente a propria linha'
);
select is(
  public.current_law_firm_member_roles(
    '20000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001'
  ),
  '{}'::text[],
  'helper de cargos nao aceita consultar terceiro'
);
select ok(
  not public.is_active_law_firm_manager('20000000-0000-0000-0000-000000000001'),
  'verificacao historica nao mantem ex-dono como manager'
);
select ok(
  not public.is_active_law_firm_case_manager('20000000-0000-0000-0000-000000000001'),
  'verificacao historica nao mantem ex-dono nos casos'
);
select ok(
  not public.can_recommend_law_firm_lawyer('20000000-0000-0000-0000-000000000001'),
  'verificacao historica nao permite recomendar advogado'
);

reset role;
insert into public.law_firm_members (
  id,
  law_firm_id,
  role,
  member_role,
  roles,
  status,
  lawyer_invite_status
)
values (
  '21000000-0000-0000-0000-000000000010',
  '20000000-0000-0000-0000-000000000001',
  'lawyer',
  'lawyer',
  array['lawyer'],
  'invited',
  'invited'
);

insert into public.law_firm_members (
  id,
  law_firm_id,
  pending_lawyer_id,
  role,
  member_role,
  roles,
  status,
  lawyer_invite_status
)
values (
  '21000000-0000-0000-0000-000000000011',
  '20000000-0000-0000-0000-000000000002',
  '10000000-0000-0000-0000-000000000003',
  'lawyer',
  'lawyer',
  array['lawyer'],
  'invited',
  'invited'
);

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', true);
set local role authenticated;
select throws_ok(
  $$
    select public.respond_to_law_firm_invite(
      '21000000-0000-0000-0000-000000000010',
      false
    )
  $$,
  'P0001',
  'Only the invited lawyer can respond to this invite',
  'convite orfao falha fechado quando nao identifica destinatario'
);
select is(
  public.respond_to_law_firm_invite(
    '21000000-0000-0000-0000-000000000011',
    false
  ),
  'disabled'::public.law_firm_member_status,
  'destinatario responde convite legado identificado por pending_lawyer_id'
);

reset role;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000004', true);
set local role authenticated;

select is(
  (select full_name from public.profiles where id = '10000000-0000-0000-0000-000000000003'),
  'Advogada Aprovada',
  'contraparte relacionada ve nome publico'
);
select throws_ok(
  $$select cpf from public.profiles where id = '10000000-0000-0000-0000-000000000003'$$,
  '42501',
  null,
  'contraparte nao consulta CPF'
);
select is(
  (select email from public.fetch_chat_profile('10000000-0000-0000-0000-000000000003')),
  '',
  'perfil de chat nao entrega email da contraparte'
);
select is(
  (select cpf from public.fetch_current_profile()),
  '52998224725',
  'titular recupera o proprio CPF pela RPC privada'
);
select lives_ok(
  $$
    select public.upsert_current_profile(
      'Cliente Relacionado',
      '52998224725',
      '11999999999'
    )
  $$,
  'RPC atualiza o proprio perfil sem SELECT direto de PII'
);
select is(
  (select email from public.fetch_current_profile()),
  'client@jurii.test',
  'RPC deriva o email do usuario autenticado'
);
select lives_ok(
  $$
    select public.upsert_current_profile(
      E'  Cliente\t Relacionado\nFinal  ',
      null,
      null
    )
  $$,
  'RPC aceita atualizacao parcial do proprio perfil'
);
select is(
  (select full_name from public.fetch_current_profile()),
  'Cliente Relacionado Final',
  'RPC normaliza espacos no nome'
);
select is(
  (select initials from public.fetch_current_profile()),
  'CF',
  'RPC calcula iniciais no servidor'
);
select is(
  (select cpf from public.fetch_current_profile()),
  '52998224725',
  'atualizacao parcial preserva CPF existente'
);
select is(
  (select phone from public.fetch_current_profile()),
  '11999999999',
  'atualizacao parcial preserva telefone existente'
);
select throws_ok(
  $$
    update public.profiles
    set avatar_url = 'https://example.invalid/avatar.png'
    where id = '10000000-0000-0000-0000-000000000004'
  $$,
  '42501',
  'permission denied for table profiles',
  'titular nao aponta avatar diretamente para URL externa'
);
select is(
  (select avatar_url from public.fetch_current_profile()),
  null::text,
  'tentativa direta nao altera o avatar'
);
select ok(
  public.can_delete_unlinked_chat_attachment(
    '10000000-0000-0000-0000-000000000004/rascunho.pdf'
  ),
  'rollback pode apagar upload proprio ainda nao vinculado'
);
select ok(
  not public.can_delete_unlinked_chat_attachment(
    '10000000-0000-0000-0000-000000000004/prova.pdf'
  ),
  'anexo entregue nao pode ser apagado pelo uploader'
);
select ok(
  not public.can_delete_unlinked_chat_attachment(
    '10000000-0000-0000-0000-000000000003/arquivo.pdf'
  ),
  'usuario nao apaga pasta de terceiro'
);

reset role;
update public.profiles
set
  deleted_at = now(),
  avatar_url = null
where id = '10000000-0000-0000-0000-000000000004';
set local role authenticated;
select throws_ok(
  $$
    select public.upsert_current_profile(
      'Cliente Reativado',
      null,
      null
    )
  $$,
  'P0001',
  'Deleted profile cannot be restored',
  'RPC nao reativa perfil excluido'
);
select throws_ok(
  $$
    update public.profiles
    set avatar_url = 'https://example.invalid/restored.png'
    where id = '10000000-0000-0000-0000-000000000004'
  $$,
  '42501',
  'permission denied for table profiles',
  'update direto de avatar em perfil excluido nao revela a linha'
);

reset role;
select is(
  (select avatar_url from public.profiles where id = '10000000-0000-0000-0000-000000000004'),
  null::text,
  'policy impede alterar avatar de perfil excluido'
);

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select is(
  (select count(*)::int from public.fetch_chat_profile('10000000-0000-0000-0000-000000000003')),
  0,
  'estranho nao carrega perfil de chat sem relacao'
);

-- ---------------------------------------------------------------------------
-- Convite por OAB
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select isnt(
  public.invite_verified_lawyer_to_law_firm(
    '20000000-0000-0000-0000-000000000001', 'SP', '12345'
  ),
  public.invite_verified_lawyer_to_law_firm(
    '20000000-0000-0000-0000-000000000001', 'SP', '12345'
  ),
  'resposta do convite real e sempre opaca'
);
select isnt(
  public.invite_verified_lawyer_to_law_firm(
    '20000000-0000-0000-0000-000000000001', 'SP', '99999'
  ),
  public.invite_verified_lawyer_to_law_firm(
    '20000000-0000-0000-0000-000000000001', 'SP', '99999'
  ),
  'resposta para OAB inexistente tem o mesmo formato opaco'
);

reset role;
select is(
  (select count(*)::int from public.law_firm_members where law_firm_id = '20000000-0000-0000-0000-000000000001' and profile_id = '10000000-0000-0000-0000-000000000003'),
  1,
  'retry nao duplica membership do convite'
);
select is(
  (select count(*)::int from public.notifications where law_firm_id = '20000000-0000-0000-0000-000000000001' and recipient_profile_id = '10000000-0000-0000-0000-000000000003' and type = 'team_invite'),
  1,
  'retry nao duplica notificacao do convite'
);

-- Uma submissao alheia posterior com a mesma OAB nao bloqueia o titular real.
insert into public.lawyer_verifications (
  user_id,
  oab_number,
  oab_state,
  practice_area,
  status,
  submitted_at
)
values (
  '10000000-0000-0000-0000-000000000002',
  '12345',
  'SP',
  'Direito Civil',
  'pending',
  now() + interval '1 day'
);

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select lives_ok(
  $$select public.invite_verified_lawyer_to_law_firm('20000000-0000-0000-0000-000000000002', 'SP', '12345')$$,
  'submissao de terceiro nao causa bloqueio por OAB'
);
reset role;
select is(
  (select count(*)::int from public.law_firm_members where law_firm_id = '20000000-0000-0000-0000-000000000002' and profile_id = '10000000-0000-0000-0000-000000000003'),
  1,
  'convite foi criado para o titular aprovado'
);

-- Uma recusa mais recente do proprio titular bloqueia aprovacao antiga.
insert into public.lawyer_verifications (
  user_id,
  oab_number,
  oab_state,
  practice_area,
  status,
  submitted_at,
  reviewed_at
)
values (
  '10000000-0000-0000-0000-000000000003',
  '12345',
  'SP',
  'Direito Civil',
  'rejected',
  now() + interval '1 day',
  now() + interval '1 day'
);

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select lives_ok(
  $$select public.invite_verified_lawyer_to_law_firm('20000000-0000-0000-0000-000000000003', 'SP', '12345')$$,
  'OAB recusada mantem resposta externa generica'
);
reset role;
select is(
  (select count(*)::int from public.law_firm_members where law_firm_id = '20000000-0000-0000-0000-000000000003' and profile_id = '10000000-0000-0000-0000-000000000003'),
  0,
  'recusa recente impede criar convite com aprovacao antiga'
);

-- Recusa entre convite e aceite desativa o papel profissional.
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select public.invite_verified_lawyer_to_law_firm(
  '20000000-0000-0000-0000-000000000001', 'RJ', '77777'
);
reset role;

select public.reject_lawyer_verification(
  '30000000-0000-0000-0000-000000000002',
  'Documento invalido',
  null
);

select is(
  (select status::text from public.law_firm_members where law_firm_id = '20000000-0000-0000-0000-000000000001' and profile_id = '10000000-0000-0000-0000-000000000007'),
  'disabled',
  'recusa desativa membership exclusivamente profissional'
);

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000007', true);
set local role authenticated;
select throws_ok(
  format(
    'select public.respond_to_law_firm_invite(%L::uuid, true)',
    (select id from public.law_firm_members where law_firm_id = '20000000-0000-0000-0000-000000000001' and profile_id = '10000000-0000-0000-0000-000000000007')
  ),
  'P0001',
  'Invite is no longer pending',
  'convite antigo nao pode ser aceito depois da recusa'
);

reset role;
insert into public.law_firm_invitation_attempts (actor_profile_id, law_firm_id)
select
  '10000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000001'
from generate_series(1, 20);

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select throws_ok(
  $$select public.invite_verified_lawyer_to_law_firm('20000000-0000-0000-0000-000000000001', 'MG', '54321')$$,
  'P0001',
  'Too many invite attempts. Try again later',
  'rate limit bloqueia enumeracao em massa'
);

reset role;
select * from finish();
rollback;
