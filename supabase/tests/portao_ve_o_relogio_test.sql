-- O portão de abrir escritório enxerga o relógio.
--
-- has_law_firm_license decidia por `status in ('trialing','active')` ao pé da
-- letra, e nada escreve por cima do 'trialing' quando o teste vence: a coluna
-- fica assim para sempre. Teste vencido abria banca de graça.
--
-- O que este arquivo trava é a fronteira: vivo libera, vencido nega, e o
-- status no banco NÃO precisa mudar para isso valer.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(12);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('d1000000-0000-4000-8000-00000000000a','authenticated','authenticated','viva@portao.test','',now(),'{}','{"full_name":"Teste Vivo"}',now(),now()),
  ('d1000000-0000-4000-8000-00000000000b','authenticated','authenticated','vencida@portao.test','',now(),'{}','{"full_name":"Teste Vencido"}',now(),now()),
  ('d1000000-0000-4000-8000-00000000000c','authenticated','authenticated','paga@portao.test','',now(),'{}','{"full_name":"Assinatura Paga"}',now(),now()),
  ('d1000000-0000-4000-8000-00000000000d','authenticated','authenticated','semdata@portao.test','',now(),'{}','{"full_name":"Teste Sem Data"}',now(),now());

insert into public.law_firm_license_subscriptions
  (owner_profile_id, plan_code, billing_cycle, status, trial_ends_at)
values
  ('d1000000-0000-4000-8000-00000000000a','essencial','monthly','trialing', now() + interval '3 days'),
  ('d1000000-0000-4000-8000-00000000000b','essencial','monthly','trialing', now() - interval '1 minute'),
  ('d1000000-0000-4000-8000-00000000000c','essencial','monthly','active',   null),
  ('d1000000-0000-4000-8000-00000000000d','essencial','monthly','trialing', null);

-- ---------------------------------------------------------------------------
-- 1. A fronteira
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','d1000000-0000-4000-8000-00000000000a', true);
set local role authenticated;
select ok(
  public.has_law_firm_license('d1000000-0000-4000-8000-00000000000a'),
  'teste ainda VIVO abre escritorio');
reset role;

select set_config('request.jwt.claim.sub','d1000000-0000-4000-8000-00000000000b', true);
set local role authenticated;
select ok(
  not public.has_law_firm_license('d1000000-0000-4000-8000-00000000000b'),
  'teste vencido ha UM MINUTO nao abre mais');
reset role;

select set_config('request.jwt.claim.sub','d1000000-0000-4000-8000-00000000000c', true);
set local role authenticated;
select ok(
  public.has_law_firm_license('d1000000-0000-4000-8000-00000000000c'),
  'assinatura ATIVA abre, e nem olha data de teste');
reset role;

select set_config('request.jwt.claim.sub','d1000000-0000-4000-8000-00000000000d', true);
set local role authenticated;
select ok(
  not public.has_law_firm_license('d1000000-0000-4000-8000-00000000000d'),
  'teste SEM data de fim vale como vencido, e nao como eterno');
reset role;

-- ---------------------------------------------------------------------------
-- 2. E o status no banco NAO mudou: a expiracao e derivada
-- ---------------------------------------------------------------------------
select is(
  (select status from public.law_firm_license_subscriptions
   where owner_profile_id = 'd1000000-0000-4000-8000-00000000000b'),
  'trialing',
  'a linha vencida CONTINUA trialing: nenhum job reescreveu nada');

-- A prova de que a decisão acompanha o relógio sem tocar na linha: mover só
-- a data de fim inverte a resposta, nos dois sentidos.
update public.law_firm_license_subscriptions
set trial_ends_at = now() + interval '1 day'
where owner_profile_id = 'd1000000-0000-4000-8000-00000000000b';

select set_config('request.jwt.claim.sub','d1000000-0000-4000-8000-00000000000b', true);
set local role authenticated;
select ok(
  public.has_law_firm_license('d1000000-0000-4000-8000-00000000000b'),
  'esticar a data reabre o portao, com o status intacto');
reset role;

update public.law_firm_license_subscriptions
set trial_ends_at = now() - interval '1 day'
where owner_profile_id = 'd1000000-0000-4000-8000-00000000000b';

select set_config('request.jwt.claim.sub','d1000000-0000-4000-8000-00000000000b', true);
set local role authenticated;
select ok(
  not public.has_law_firm_license('d1000000-0000-4000-8000-00000000000b'),
  'e encurtar fecha de novo');
reset role;

-- ---------------------------------------------------------------------------
-- 3. As travas que ja existiam continuam de pe
-- ---------------------------------------------------------------------------
--
-- A licenca GASTA (amarrada a uma banca) nunca abriu a segunda, e a resposta
-- so vale sobre quem pergunta.
update public.law_firm_license_subscriptions
set trial_ends_at = now() + interval '5 days'
where owner_profile_id = 'd1000000-0000-4000-8000-00000000000b';

insert into public.law_firms (id, name, initials, specialty, is_active, cep, oab_state)
values ('df100000-0000-4000-8000-000000000001','Banca Gasta','BG','Direito Cível',true,'90540140','RS');

update public.law_firm_license_subscriptions
set law_firm_id = 'df100000-0000-4000-8000-000000000001'
where owner_profile_id = 'd1000000-0000-4000-8000-00000000000b';

select set_config('request.jwt.claim.sub','d1000000-0000-4000-8000-00000000000b', true);
set local role authenticated;
select ok(
  not public.has_law_firm_license('d1000000-0000-4000-8000-00000000000b'),
  'licenca VIVA porem ja gasta segue sem abrir a segunda banca');

-- A trava da 20260901120000: a funcao so responde sobre QUEM PERGUNTA.
select ok(
  not public.has_law_firm_license('d1000000-0000-4000-8000-00000000000c'),
  'ninguem descobre a situacao de licenca de outra pessoa');
reset role;

-- ---------------------------------------------------------------------------
-- 4. O efeito real: a POLICY que usa o portao
-- ---------------------------------------------------------------------------
--
-- has_law_firm_license e o `with check` de law_firm_verifications_insert_own.
-- O teste de verdade nao e a funcao devolver false, e a pessoa nao conseguir
-- PEDIR a abertura.
select set_config('request.jwt.claim.sub','d1000000-0000-4000-8000-00000000000a', true);
set local role authenticated;

select lives_ok(
  $$insert into public.law_firm_verifications
      (owner_profile_id, firm_name, cnpj, phone, email, address, address_number, cep, practice_areas)
    values ('d1000000-0000-4000-8000-00000000000a','Banca do Teste Vivo','11222333000181',
            '51999990000','viva@portao.test','Rua Um','10','90540140', array['Direito Cível'])$$,
  'com teste vivo, a pessoa PEDE a abertura normalmente');

reset role;

select set_config('request.jwt.claim.sub','d1000000-0000-4000-8000-00000000000d', true);
set local role authenticated;

select throws_ok(
  $$insert into public.law_firm_verifications
      (owner_profile_id, firm_name, cnpj, phone, email, address, address_number, cep, practice_areas)
    values ('d1000000-0000-4000-8000-00000000000d','Banca do Teste Morto','11222333000181',
            '51999990000','semdata@portao.test','Rua Dois','20','90540140', array['Direito Cível'])$$,
  '42501',
  null,
  'com teste vencido, o PEDIDO de abertura e recusado pela policy');

reset role;

-- ---------------------------------------------------------------------------
-- 5. Cancelada nunca abriu, e segue sem abrir
-- ---------------------------------------------------------------------------
update public.law_firm_license_subscriptions
set status = 'canceled'
where owner_profile_id = 'd1000000-0000-4000-8000-00000000000a';

select set_config('request.jwt.claim.sub','d1000000-0000-4000-8000-00000000000a', true);
set local role authenticated;
select ok(
  not public.has_law_firm_license('d1000000-0000-4000-8000-00000000000a'),
  'licenca cancelada nao abre banca');
reset role;

select * from finish();
rollback;
