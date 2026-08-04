-- Testes da migration 20260804180000: apresentação do profissional gravável.
-- Grava/limpa, teto de tamanho, gate do escritório (secretária não edita),
-- e a escrita direta na coluna deixou de existir.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(14);

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('e1000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'advogada@bio.test', '', now(), '{}'::jsonb,
   '{"full_name":"Advogada Bio"}'::jsonb, now(), now()),
  ('e1000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'dono@bio.test', '', now(), '{}'::jsonb,
   '{"full_name":"Dono Bio"}'::jsonb, now(), now()),
  ('e1000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'secretaria@bio.test', '', now(), '{}'::jsonb,
   '{"full_name":"Secretaria Bio"}'::jsonb, now(), now()),
  ('e1000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated',
   'cliente@bio.test', '', now(), '{}'::jsonb,
   '{"full_name":"Cliente Bio"}'::jsonb, now(), now());

update public.profiles set lawyer_status = 'approved'
where id = 'e1000000-0000-0000-0000-000000000001';

insert into public.lawyer_profiles (id, oab_number, oab_state, primary_area, practice_areas)
values ('e1000000-0000-0000-0000-000000000001', '515151', 'RS',
        'Direito Cível', array['Direito Cível']);

insert into public.law_firms (id, name, initials, specialty, is_active)
values ('e2000000-0000-0000-0000-000000000001', 'Firma Bio', 'FB', 'Civil', true);

insert into public.law_firm_members (law_firm_id, profile_id, member_role, roles, status)
values
  ('e2000000-0000-0000-0000-000000000001',
   'e1000000-0000-0000-0000-000000000002', 'owner', array['owner'], 'active'),
  ('e2000000-0000-0000-0000-000000000001',
   'e1000000-0000-0000-0000-000000000003', 'secretary', array['secretary'], 'active');

-- ---------------------------------------------------------------------------
-- Bio da advogada
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'e1000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select is(
  public.update_lawyer_bio('  Atuo com direito de familia ha 12 anos.  '),
  'Atuo com direito de familia ha 12 anos.',
  'bio gravada com espacos aparados');

select is(
  (select bio from public.lawyer_profiles
    where id = 'e1000000-0000-0000-0000-000000000001'),
  'Atuo com direito de familia ha 12 anos.',
  'bio persiste na tabela');

-- O texto do profissional tem que chegar ao cliente: e o ponto da feature.
select is(
  (select bio from public.fetch_lawyer_public_profile(
    'e1000000-0000-0000-0000-000000000001')),
  'Atuo com direito de familia ha 12 anos.',
  'perfil publico devolve a bio escrita (nao o fallback generico)');

select is(
  public.update_lawyer_bio('   '),
  null,
  'so espacos vira NULL (fallback generico volta)');

select is(
  (select bio from public.fetch_lawyer_public_profile(
    'e1000000-0000-0000-0000-000000000001')),
  'Perfil profissional verificado pela Jurii.',
  'sem bio, o perfil publico volta ao texto padrao');

select throws_ok(
  format($$select public.update_lawyer_bio(%L)$$, repeat('a', 801)),
  'Bio is too long',
  'bio acima do teto e recusada');

select lives_ok(
  format($$select public.update_lawyer_bio(%L)$$, repeat('a', 800)),
  'exatamente no teto passa');

-- Quem nao tem perfil de advogado nao grava bio nenhuma.
reset role;
select set_config('request.jwt.claim.sub', 'e1000000-0000-0000-0000-000000000004', true);
set local role authenticated;

select throws_ok(
  $$select public.update_lawyer_bio('sou advogado sim')$$,
  'Lawyer profile not found',
  'cliente sem perfil de advogado nao grava bio');

-- ---------------------------------------------------------------------------
-- Descrição do escritório
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'e1000000-0000-0000-0000-000000000002', true);
set local role authenticated;

select is(
  public.update_law_firm_description(
    'e2000000-0000-0000-0000-000000000001', 'Banca de familia e sucessoes.'),
  'Banca de familia e sucessoes.',
  'dono grava a descricao');

select is(
  (select description from public.law_firms
    where id = 'e2000000-0000-0000-0000-000000000001'),
  'Banca de familia e sucessoes.',
  'descricao persiste');

select throws_ok(
  format($$select public.update_law_firm_description(
    'e2000000-0000-0000-0000-000000000001', %L)$$, repeat('b', 801)),
  'Description is too long',
  'descricao acima do teto e recusada');

reset role;
select set_config('request.jwt.claim.sub', 'e1000000-0000-0000-0000-000000000003', true);
set local role authenticated;

select throws_ok(
  $$select public.update_law_firm_description(
    'e2000000-0000-0000-0000-000000000001', 'texto da secretaria')$$,
  'Only firm owners and admins can edit the description',
  'secretaria NAO edita a apresentacao do escritorio');

reset role;
select set_config('request.jwt.claim.sub', 'e1000000-0000-0000-0000-000000000004', true);
set local role authenticated;

select throws_ok(
  $$select public.update_law_firm_description(
    'e2000000-0000-0000-0000-000000000001', 'texto de estranho')$$,
  'Only firm owners and admins can edit the description',
  'estranho nao edita a apresentacao');

reset role;

-- ---------------------------------------------------------------------------
-- A RPC é o único caminho: escrita direta na coluna foi revogada
-- ---------------------------------------------------------------------------

select ok(
  not has_column_privilege('authenticated', 'public.lawyer_profiles', 'bio', 'update'),
  'authenticated NAO escreve bio direto na tabela (so pela RPC)');

select * from finish();
rollback;
