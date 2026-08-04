-- Testes da migration 20260801120000: denúncia e bloqueio no chat.
-- Bloqueio congela a conversa para OS DOIS lados; só quem bloqueou destrava;
-- denúncia só de participante, com razão whitelistada, texto sanitizado e
-- teto diário.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(24);

-- ---------------------------------------------------------------------------
-- Fixtures: cliente + advogada aprovada + um terceiro sem relação
-- ---------------------------------------------------------------------------

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('91000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'cliente@block.test', '', now(), '{}'::jsonb,
   '{"full_name":"Cliente Block"}'::jsonb, now(), now()),
  ('91000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'advogada@block.test', '', now(), '{}'::jsonb,
   '{"full_name":"Advogada Block"}'::jsonb, now(), now()),
  ('91000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'estranho@block.test', '', now(), '{}'::jsonb,
   '{"full_name":"Estranho Block"}'::jsonb, now(), now());

update public.profiles set lawyer_status = 'approved'
where id = '91000000-0000-0000-0000-000000000002';

insert into public.lawyer_profiles (id, oab_number, oab_state, primary_area, practice_areas)
values ('91000000-0000-0000-0000-000000000002', '626262', 'RS',
        'Direito Cível', array['Direito Cível']);

-- Conversa real criada pelo caminho oficial, como cliente.
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

create temporary table t_ids (name text primary key, id uuid);
insert into t_ids
select 'conv', public.start_or_get_lawyer_conversation(
  '91000000-0000-0000-0000-000000000002', 'oi');

-- ---------------------------------------------------------------------------
-- Bloqueio congela os dois lados
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select public.block_conversation((select id from t_ids where name = 'conv'))$$,
  'cliente bloqueia a conversa');

reset role;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000002', true);
set local role authenticated;

select throws_ok(
  $$insert into public.messages (conversation_id, sender_id, sender_type, body)
    values ((select id from t_ids where name = 'conv'),
            '91000000-0000-0000-0000-000000000002', 'lawyer', 'tentativa')$$,
  'conversation_blocked',
  'advogada nao envia mensagem em conversa bloqueada');

select results_eq(
  $$select * from public.fetch_conversation_block_state(
      (select id from t_ids where name = 'conv'))$$,
  $$values (true, false)$$,
  'advogada ve conversa bloqueada, mas nao por ela');

-- A advogada nao consegue destravar o bloqueio do cliente.
select lives_ok(
  $$select public.unblock_conversation((select id from t_ids where name = 'conv'))$$,
  'unblock de quem nao bloqueou nao explode');

select results_eq(
  $$select * from public.fetch_conversation_block_state(
      (select id from t_ids where name = 'conv'))$$,
  $$values (true, false)$$,
  'a trava do cliente continua depois do unblock alheio');

reset role;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select throws_ok(
  $$insert into public.messages (conversation_id, sender_id, sender_type, body)
    values ((select id from t_ids where name = 'conv'),
            '91000000-0000-0000-0000-000000000001', 'client', 'eu tambem nao')$$,
  'conversation_blocked',
  'quem bloqueou tambem nao envia (conversa congelada)');

select lives_ok(
  $$select public.unblock_conversation((select id from t_ids where name = 'conv'))$$,
  'cliente desbloqueia');

reset role;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000002', true);
set local role authenticated;

select lives_ok(
  $$insert into public.messages (conversation_id, sender_id, sender_type, body)
    values ((select id from t_ids where name = 'conv'),
            '91000000-0000-0000-0000-000000000002', 'lawyer', 'voltei')$$,
  'desbloqueada, a conversa volta a receber mensagens');

-- ---------------------------------------------------------------------------
-- Terceiros não bloqueiam nem aprendem nada
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000003', true);
set local role authenticated;

select throws_ok(
  $$select public.block_conversation((select id from t_ids where name = 'conv'))$$,
  'Conversation not found',
  'quem nao participa nao bloqueia');

select results_eq(
  $$select * from public.fetch_conversation_block_state(
      (select id from t_ids where name = 'conv'))$$,
  $$values (false, false)$$,
  'quem nao participa nao aprende o estado da conversa');

-- ---------------------------------------------------------------------------
-- Denúncia
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select lives_ok(
  $$select public.report_conversation(
      (select id from t_ids where name = 'conv'), 'spam')$$,
  'participante denuncia a conversa');

reset role;

select is(
  (select reported_profile_id from public.user_reports
    where reporter_profile_id = '91000000-0000-0000-0000-000000000001'
    order by created_at limit 1),
  '91000000-0000-0000-0000-000000000002'::uuid,
  'denuncia do cliente aponta a contraparte (advogada)');

select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select throws_ok(
  $$select public.report_conversation(
      (select id from t_ids where name = 'conv'), 'motivo_inventado')$$,
  'Invalid report reason',
  'razao fora da whitelist e recusada');

reset role;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000003', true);
set local role authenticated;

select throws_ok(
  $$select public.report_conversation(
      (select id from t_ids where name = 'conv'), 'spam')$$,
  'Conversation not found',
  'quem nao participa nao denuncia');

-- Texto livre: controle vira espaço, bordas aparadas (blindagem de log).
reset role;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select public.report_conversation(
  (select id from t_ids where name = 'conv'), 'outro',
  E'ameacas\ncom quebra\tde linha  ');

reset role;

select is(
  (select details from public.user_reports
    where reporter_profile_id = '91000000-0000-0000-0000-000000000001'
      and reason = 'outro'),
  'ameacas com quebra de linha',
  'detalhes sao sanitizados: sem caracteres de controle, sem bordas');

-- Antiflood: 10 por dia; as 2 acima + 8 = teto, a 11a cai.
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select lives_ok(
  $$select public.report_conversation(
      (select id from t_ids where name = 'conv'), 'spam')
    from generate_series(1, 8)$$,
  'ate 10 denuncias no dia entram');

select throws_ok(
  $$select public.report_conversation(
      (select id from t_ids where name = 'conv'), 'spam')$$,
  'Report limit reached',
  'a 11a denuncia do dia e recusada');

-- ---------------------------------------------------------------------------
-- Anexo em mensagem antiga não fura o bloqueio
-- ---------------------------------------------------------------------------

select public.block_conversation((select id from t_ids where name = 'conv'));

reset role;
insert into t_ids
select 'msg_antiga', id from public.messages
where conversation_id = (select id from t_ids where name = 'conv')
  and body = 'voltei';

-- Desde a 20260806120000 o INSERT direto nem chega ao trigger: o grant foi
-- revogado e a RPC (SECURITY DEFINER) virou o único caminho. As duas garantias
-- ficam presas separadamente — a porta fechada e o trigger que continua lá.
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000002', true);
set local role authenticated;

select throws_ok(
  $$insert into public.message_attachments
      (message_id, conversation_id, uploaded_by, file_name, mime_type,
       file_size_bytes, storage_path, kind)
    values ((select id from t_ids where name = 'msg_antiga'),
            (select id from t_ids where name = 'conv'),
            '91000000-0000-0000-0000-000000000002', 'furada.pdf',
            'application/pdf', 10,
            '91000000-0000-0000-0000-000000000002/furada.pdf', 'document')$$,
  '42501', null,
  'anexar arquivo direto nem e mais possivel para authenticated');

reset role;

-- O trigger permanece como defesa em profundidade: se um dia o grant voltar
-- (ou um caminho com privilegio inserir), o bloqueio da conversa ainda vale.
select throws_ok(
  $$insert into public.message_attachments
      (message_id, conversation_id, uploaded_by, file_name, mime_type,
       file_size_bytes, storage_path, kind)
    values ((select id from t_ids where name = 'msg_antiga'),
            (select id from t_ids where name = 'conv'),
            '91000000-0000-0000-0000-000000000002', 'furada.pdf',
            'application/pdf', 10,
            '91000000-0000-0000-0000-000000000002/furada.pdf', 'document')$$,
  'conversation_blocked',
  'o trigger de bloqueio continua valendo para quem tem privilegio');

select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000002', true);
set local role authenticated;

-- ---------------------------------------------------------------------------
-- Escritório: canal interno fora da moderação; dono destrava operador
-- ---------------------------------------------------------------------------

reset role;

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('91000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated',
   'dono@block.test', '', now(), '{}'::jsonb,
   '{"full_name":"Dono Block"}'::jsonb, now(), now()),
  ('91000000-0000-0000-0000-000000000005', 'authenticated', 'authenticated',
   'secretaria@block.test', '', now(), '{}'::jsonb,
   '{"full_name":"Secretaria Block"}'::jsonb, now(), now());

insert into public.law_firms (id, name, initials, specialty, is_active)
values ('92000000-0000-0000-0000-000000000001', 'Firma Block', 'FB', 'Civil', true);

insert into public.law_firm_members (law_firm_id, profile_id, member_role, roles, status)
values
  ('92000000-0000-0000-0000-000000000001',
   '91000000-0000-0000-0000-000000000004', 'owner', array['owner'], 'active'),
  ('92000000-0000-0000-0000-000000000001',
   '91000000-0000-0000-0000-000000000005', 'secretary', array['secretary'], 'active');

insert into public.conversations (id, type, client_id, law_firm_id, title)
values
  ('93000000-0000-0000-0000-000000000001', 'client_firm',
   '91000000-0000-0000-0000-000000000001',
   '92000000-0000-0000-0000-000000000001', 'Balcao'),
  ('93000000-0000-0000-0000-000000000002', 'firm_internal',
   '91000000-0000-0000-0000-000000000004',
   '92000000-0000-0000-0000-000000000001', 'Equipe');

select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000004', true);
set local role authenticated;

select throws_ok(
  $$select public.block_conversation('93000000-0000-0000-0000-000000000002')$$,
  'Internal conversation',
  'canal interno de equipe nao e bloqueavel');

select throws_ok(
  $$select public.report_conversation('93000000-0000-0000-0000-000000000002', 'spam')$$,
  'Internal conversation',
  'canal interno de equipe nao e denunciavel');

-- Operadora bloqueia o balcão; a dona destrava (senão operador que sai do
-- escritório congelaria a conversa para sempre).
reset role;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000005', true);
set local role authenticated;

select lives_ok(
  $$select public.block_conversation('93000000-0000-0000-0000-000000000001')$$,
  'operadora do escritorio bloqueia o balcao');

reset role;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000004', true);
set local role authenticated;

select public.unblock_conversation('93000000-0000-0000-0000-000000000001');

select results_eq(
  $$select * from public.fetch_conversation_block_state(
      '93000000-0000-0000-0000-000000000001')$$,
  $$values (false, false)$$,
  'dona destrava o bloqueio deixado pela operadora');

-- A trava do CLIENTE não é destravável pelo escritório.
reset role;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select public.block_conversation('93000000-0000-0000-0000-000000000001');

reset role;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000004', true);
set local role authenticated;
select public.unblock_conversation('93000000-0000-0000-0000-000000000001');

select results_eq(
  $$select * from public.fetch_conversation_block_state(
      '93000000-0000-0000-0000-000000000001')$$,
  $$values (true, false)$$,
  'a trava do cliente sobrevive ao unblock do escritorio');

select * from finish();
rollback;
