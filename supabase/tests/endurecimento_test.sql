-- Os três ataques do endurecimento de agosto, cada um refeito com a role
-- real. Todos funcionavam antes da 20260901120000.
--
-- O teste vale pelo que ele derruba: se alguém reabrir a policy de INSERT,
-- devolver o SELECT da coluna do token ou tirar a trava de
-- has_law_firm_license, alguma destas asserções cai.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(12);

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('d1000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'advogada@jurii.test', '', now(), '{}'::jsonb,
   '{"full_name":"Advogada Alvo"}'::jsonb, now(), now()),
  ('d1000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'curioso@jurii.test', '', now(), '{}'::jsonb,
   '{"full_name":"Curioso Qualquer"}'::jsonb, now(), now());

-- A vítima: advogada aprovada, com feed de calendário ligado.
insert into public.lawyer_profiles
  (id, oab_number, oab_state, primary_area, is_available, approved_at, calendar_feed_token)
values
  ('d1000000-0000-0000-0000-000000000001', '770099', 'RS', 'Direito Cível',
   true, now(), '11111111-1111-4111-8111-111111111111');

-- ---------------------------------------------------------------------------
-- 1. O token do calendário não sai para ninguém além do dono
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub',
  'd1000000-0000-0000-0000-000000000002', true);
set local role authenticated;

-- O perfil PÚBLICO continua legível: a correção é de coluna, não de policy,
-- e quebrar a vitrine para fechar o token seria trocar um defeito por outro.
select is(
  (select count(*)::int from public.lawyer_profiles
    where id = 'd1000000-0000-0000-0000-000000000001'),
  1,
  'o perfil da advogada aprovada continua visivel');

select throws_ok(
  $$select calendar_feed_token from public.lawyer_profiles
     where id = 'd1000000-0000-0000-0000-000000000001'$$,
  '42501',
  'permission denied for table lawyer_profiles',
  'curioso NAO le o token de calendario alheio');

-- Nem o `select *`, que é por onde isto voltaria sem ninguém perceber.
select throws_ok(
  $$select * from public.lawyer_profiles
     where id = 'd1000000-0000-0000-0000-000000000001'$$,
  '42501',
  'permission denied for table lawyer_profiles',
  'nem por select *');

reset role;

-- O DONO continua alcançando o dele, pelo caminho de sempre: a RPC
-- SECURITY DEFINER, que é como o app e o webapp leem.
select set_config('request.jwt.claim.sub',
  'd1000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select is(
  public.get_calendar_feed_token(),
  '11111111-1111-4111-8111-111111111111'::uuid,
  'a dona le o proprio token pela RPC');

reset role;

-- ---------------------------------------------------------------------------
-- 2. A verificação não se escreve à mão
--
-- Antes da 20260919 a tabela aceitava escrita direta e as policies é que
-- seguravam o essencial (ninguém se aprova). Continuavam passando as colunas
-- de tempo, e com elas o candidato reescrevia o próprio submitted_at para
-- passar na frente na fila que a equipe revisa por ordem de envio. Agora o
-- grant de escrita não existe, e as policies ficam como segunda camada: as
-- duas primeiras asserções aqui embaixo eram barradas pela RLS e passaram a
-- ser barradas antes dela, o que é a mesma recusa mais cedo.
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub',
  'd1000000-0000-0000-0000-000000000002', true);
set local role authenticated;

select throws_ok(
  $$insert into public.lawyer_verifications
      (user_id, oab_number, oab_state, practice_area, status, reviewed_at)
    values ('d1000000-0000-0000-0000-000000000002', '000001', 'RS',
            'Direito Civel', 'approved', now())$$,
  '42501',
  'permission denied for table lawyer_verifications',
  'ninguem insere verificacao ja APROVADA');

select throws_ok(
  $$insert into public.lawyer_verifications
      (user_id, oab_number, oab_state, practice_area, status, rejection_reason)
    values ('d1000000-0000-0000-0000-000000000002', '000002', 'RS',
            'Direito Civel', 'pending', 'motivo inventado')$$,
  '42501',
  'permission denied for table lawyer_verifications',
  'nem com motivo de recusa forjado');

-- A porta da frente não pode fechar junto: o envio legítimo passa pela RPC,
-- que é por onde o app e o webapp sempre enviaram.
select lives_ok(
  $$select public.submit_lawyer_verification('000003', 'RS', 'Direito Civel',
      array['Direito Civel'])$$,
  'envio legitimo, pela RPC, continua passando');

select is(
  (select status::text from public.lawyer_verifications
   where user_id = 'd1000000-0000-0000-0000-000000000002' and oab_number = '000003'),
  'pending',
  'e nasce pendente, para a equipe revisar');

reset role;

-- ---------------------------------------------------------------------------
-- 3. has_law_firm_license só responde sobre quem pergunta
-- ---------------------------------------------------------------------------
insert into public.law_firm_license_subscriptions
  (owner_profile_id, plan_code, billing_cycle, status, trial_ends_at)
values
  -- COM data de fim, que e como choose_law_firm_plan cria de verdade. Desde
  -- a 20260913120000 o portao deriva a expiracao em vez de olhar so o
  -- status, e teste sem data vale como vencido: sem esta coluna a fixture
  -- estaria testando visibilidade com uma licenca MORTA, e o teste passaria
  -- ou falharia pelo motivo errado.
  ('d1000000-0000-0000-0000-000000000001', 'essencial', 'annual', 'trialing',
   now() + interval '20 days');

select set_config('request.jwt.claim.sub',
  'd1000000-0000-0000-0000-000000000002', true);
set local role authenticated;

select is(
  public.has_law_firm_license('d1000000-0000-0000-0000-000000000001'),
  false,
  'ninguem descobre se OUTRO perfil paga a Jurii');

reset role;

select set_config('request.jwt.claim.sub',
  'd1000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select is(
  public.has_law_firm_license('d1000000-0000-0000-0000-000000000001'),
  true,
  'sobre si mesma a resposta continua verdadeira, que e o uso da policy');

reset role;

-- A BARREIRA da lista de colunas: derrubar o grant de tabela e devolver
-- coluna a coluna deixa coluna nova nascendo sem grant. Isto cobra a lista
-- inteira, para quem adicionar uma decidir de propósito em vez de descobrir
-- pela tela vazia.
select is(
  (select coalesce(string_agg(c.column_name, ',' order by c.ordinal_position), '')
     from information_schema.columns c
    where c.table_schema = 'public' and c.table_name = 'lawyer_profiles'
      and not exists (
        select 1 from information_schema.column_privileges g
         where g.table_schema = 'public' and g.table_name = 'lawyer_profiles'
           and g.column_name = c.column_name
           and g.grantee = 'authenticated' and g.privilege_type = 'SELECT'
      )),
  'calendar_feed_token',
  'a UNICA coluna fechada a authenticated e o token do calendario');

-- Nenhum balde pode ficar sem teto nem sem lista de tipos: foi assim que
-- case-documents passou despercebido.
select is(
  (select coalesce(string_agg(id, ',' order by id), '')
     from storage.buckets
    where file_size_limit is null or allowed_mime_types is null),
  '',
  'todo balde tem teto de tamanho e lista de tipos');

select * from finish();
rollback;
