-- Testes da migration 20260819120000: numero e complemento em campos proprios.
--
-- O que isto protege: numero e complemento sao a UNICA coisa que distingue um
-- escritorio do outro quando eles dividem CEP — 18 dos 39 em producao. Perder
-- esses campos no meio do caminho nao produz endereco feio, produz endereco de
-- outro escritorio.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(11);

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('ee000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'dono@endereco.test', '', now(), '{}'::jsonb,
   '{"full_name":"Dono Endereco"}'::jsonb, now(), now()),
  ('ee000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'revisor@endereco.test', '', now(), '{}'::jsonb,
   '{"full_name":"Revisor"}'::jsonb, now(), now());

insert into public.law_firms
  (id, name, initials, specialty, practice_areas, address, cep, is_active)
values
  ('ef000000-0000-0000-0000-000000000001', 'Firma Endereco', 'FE',
   'Direito Cível', array['Direito Cível'],
   'Rua Germano Petersen Júnior, Auxiliadora, Porto Alegre - RS',
   '90540140', true);

insert into public.law_firm_members
  (law_firm_id, profile_id, member_role, roles, status)
values
  ('ef000000-0000-0000-0000-000000000001',
   'ee000000-0000-0000-0000-000000000001', 'owner', array['owner'], 'active');

-- ---------------------------------------------------------------------------
-- Cadastro antigo continua igual: as colunas novas nascem nulas
-- ---------------------------------------------------------------------------

select is(
  (select address_number from public.law_firms
    where id = 'ef000000-0000-0000-0000-000000000001'),
  null,
  'cadastro anterior a esta migration nasce sem numero, sem parser de texto');

-- ---------------------------------------------------------------------------
-- Gravacao pela RPC de edicao
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'ee000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select results_eq(
  $$select address_number, address_complement
    from public.update_law_firm_profile(
      'ef000000-0000-0000-0000-000000000001', 'Firma Endereco', null, null,
      null, 'Rua Germano Petersen Júnior, Auxiliadora, Porto Alegre - RS',
      '90540140', null, null, 'Direito Cível', array['Direito Cível'],
      'preserve', null, '  70  ', '  sala 1102  ')$$,
  $$values ('70', 'sala 1102')$$,
  'numero e complemento sao gravados e devolvidos, aparados');

-- Devolver os campos importa: e desta linha que o formulario se repreenche
-- depois de salvar. Sem eles no RETURNS TABLE, o campo abriria vazio na
-- proxima edicao e voltaria como NULL ao servidor.
select is(
  (select address_number from public.law_firms
    where id = 'ef000000-0000-0000-0000-000000000001'),
  '70',
  'e o que ficou no banco e o mesmo que a RPC devolveu');

-- Opcionais: existe "s/n", existe "Km 12", existe escritorio rural.
select lives_ok(
  $$select public.update_law_firm_profile(
      'ef000000-0000-0000-0000-000000000001', 'Firma Endereco', null, null,
      null, 'Estrada da Serra, Zona Rural, Canela - RS', '95680000', null,
      null, 'Direito Cível', array['Direito Cível'], 'preserve', null,
      null, null)$$,
  'numero e complemento vazios passam — nao sao obrigatorios');

select is(
  (select address_number from public.law_firms
    where id = 'ef000000-0000-0000-0000-000000000001'),
  null,
  'e limpar de verdade limpa (nao fica o valor antigo pendurado)');

select lives_ok(
  $$select public.update_law_firm_profile(
      'ef000000-0000-0000-0000-000000000001', 'Firma Endereco', null, null,
      null, 'Rodovia BR-116, Km 12, Guaíba - RS', '92500000', null, null,
      'Direito Cível', array['Direito Cível'], 'preserve', null,
      'Km 12', 'galpão 3')$$,
  'numero nao precisa ser numerico: "Km 12" e endereco de verdade');

-- Teto de tamanho: campo livre sem limite vira lugar de colar texto inteiro.
select throws_ok(
  $$select public.update_law_firm_profile(
      'ef000000-0000-0000-0000-000000000001', 'Firma Endereco', null, null,
      null, 'Rua X', '90540140', null, null, 'Direito Cível',
      array['Direito Cível'], 'preserve', null, repeat('9', 21), null)$$,
  'Address number is too long',
  'numero absurdamente longo e recusado');

select throws_ok(
  $$select public.update_law_firm_profile(
      'ef000000-0000-0000-0000-000000000001', 'Firma Endereco', null, null,
      null, 'Rua X', '90540140', null, null, 'Direito Cível',
      array['Direito Cível'], 'preserve', null, '70', repeat('a', 61))$$,
  'Address complement is too long',
  'complemento absurdamente longo e recusado');

reset role;

-- ---------------------------------------------------------------------------
-- A verificacao carrega os campos, e a aprovacao os copia
-- ---------------------------------------------------------------------------

-- law_firm_verifications tem INSERT coluna a coluna: sem grant explicito, o
-- primeiro cadastro real quebra com "permission denied" — e teste de widget
-- nao pega, porque nem chega no banco.
select ok(
  has_column_privilege('authenticated', 'public.law_firm_verifications',
    'address_number', 'insert')
  and has_column_privilege('authenticated', 'public.law_firm_verifications',
    'address_complement', 'insert'),
  'authenticated pode gravar numero e complemento na verificacao');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'ee000000-0000-0000-0000-000000000002', true);

insert into public.law_firm_verifications
  (owner_profile_id, firm_name, cnpj, address, address_number,
   address_complement, cep, practice_areas)
values
  ('ee000000-0000-0000-0000-000000000002', 'Firma Nova', '11222333000181',
   'Avenida Ipiranga, Praia de Belas, Porto Alegre - RS', '100', 'conjunto 5',
   '90160091', array['Direito Cível']);

-- A aprovacao roda com privilegio de revisor (a RPC nao e executavel por
-- authenticated); aqui, como dono do banco.
reset role;

select lives_ok(
  $$select public.approve_law_firm_verification(
      (select id from public.law_firm_verifications where firm_name = 'Firma Nova'),
      'ee000000-0000-0000-0000-000000000001')$$,
  'aprovacao roda');

-- Sem esta copia, todo escritorio aprovado nasceria sem numero — e a
-- aprovacao devolveria sucesso, entao ninguem descobriria.
select results_eq(
  $$select address_number, address_complement from public.law_firms
    where name = 'Firma Nova'$$,
  $$values ('100', 'conjunto 5')$$,
  'a aprovacao copia numero e complemento para o escritorio');

select * from finish();
rollback;
