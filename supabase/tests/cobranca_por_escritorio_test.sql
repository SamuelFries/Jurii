-- A cobrança por escritório.
--
-- A regra em uma frase: assinatura SEM escritório é licença comprada e não
-- gasta; assinatura COM escritório é licença gasta naquela banca. O portão de
-- abrir escritório pede uma licença não gasta, e é isso que impede uma
-- assinatura de pagar duas bancas.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(18);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('c1000000-0000-0000-0000-00000000000a','authenticated','authenticated','socio@c.test','',now(),'{}','{"full_name":"Socio Fundador"}',now(),now()),
  ('c1000000-0000-0000-0000-00000000000b','authenticated','authenticated','estagiario@c.test','',now(),'{}','{"full_name":"Estagiario Curioso"}',now(),now());

insert into public.law_firms (id, name, initials, specialty, is_active, cep, oab_state)
values ('cf100000-0000-0000-0000-000000000001','Banca Um','B1','Direito Civel',true,'90540140','RS');

insert into public.law_firm_members (law_firm_id, profile_id, roles, member_role, role, status)
values
  ('cf100000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-00000000000a',array['owner'],'owner','owner','active'),
  ('cf100000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-00000000000b',array['intern'],'intern','intern','active');

-- ---------------------------------------------------------------------------
-- Contratar a primeira licença
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-00000000000a', true);
set local role authenticated;

select is(
  public.has_law_firm_license('c1000000-0000-0000-0000-00000000000a'),
  false,
  'sem assinatura, o portao de abrir escritorio esta fechado');

select is(
  (select status from public.choose_law_firm_plan('essencial','monthly')),
  'trialing',
  'contratar cria o teste gratis');

select is(
  public.has_law_firm_license('c1000000-0000-0000-0000-00000000000a'),
  true,
  'com licenca NAO GASTA, o portao abre');

-- Trocar de plano antes de abrir a banca reaproveita a licenca em vez de
-- criar a segunda: mudar de ideia nao pode virar duas cobrancas.
select is(
  (select billing_cycle from public.choose_law_firm_plan('banca','annual')),
  'annual',
  'trocar de plano antes de abrir reaproveita a mesma licenca');

reset role;

select is(
  (select count(*)::int from public.law_firm_license_subscriptions
    where owner_profile_id = 'c1000000-0000-0000-0000-00000000000a'),
  1,
  'e continua sendo UMA assinatura, nao duas');

-- ---------------------------------------------------------------------------
-- A licença é GASTA ao abrir a banca
-- ---------------------------------------------------------------------------
update public.law_firm_license_subscriptions
set law_firm_id = 'cf100000-0000-0000-0000-000000000001', status = 'active'
where owner_profile_id = 'c1000000-0000-0000-0000-00000000000a';

select set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-00000000000a', true);
set local role authenticated;

-- O CASO QUE ESTA MIGRATION EXISTE PARA RESOLVER: antes, a assinatura ja
-- gasta no escritorio A respondia "sim" e abria o B de graca.
select is(
  public.has_law_firm_license('c1000000-0000-0000-0000-00000000000a'),
  false,
  'licenca JA GASTA nao abre um segundo escritorio');

-- E o portao do banco recusa de verdade, nao so a funcao.
select throws_ok(
  $$insert into public.law_firm_verifications (owner_profile_id, firm_name, cnpj, status)
    values ('c1000000-0000-0000-0000-00000000000a','Banca Dois','11222333000181','pending')$$,
  '42501',
  'new row violates row-level security policy for table "law_firm_verifications"',
  'sem licenca nova, o pedido de abertura e recusado pela RLS');

-- Comprando a SEGUNDA licenca, a porta abre. Antes isso era impossivel: a
-- funcao achava a assinatura existente e trocava o plano dela.
select is(
  (select law_firm_id from public.choose_law_firm_plan('essencial','monthly')),
  null,
  'a segunda licenca nasce sem escritorio');

-- E NASCE A PAGAR. O teste gratis e um por PESSOA (20260907120000): quem ja
-- experimentou o produto na primeira banca nao experimenta de novo na segunda.
-- Era por aqui que cancelar e recontratar rendia trinta dias novos em loop.
select is(
  (select status from public.law_firm_license_subscriptions
    where owner_profile_id = 'c1000000-0000-0000-0000-00000000000a'
      and law_firm_id is null),
  'past_due',
  'a segunda licenca nasce a pagar, e nao em teste');

-- Logo o portao segue FECHADO ate o dinheiro entrar: abrir escritorio com
-- licenca que ninguem pagou seria a segunda banca de graca por outro caminho.
select is(
  public.has_law_firm_license('c1000000-0000-0000-0000-00000000000a'),
  false,
  'licenca comprada e NAO PAGA ainda nao abre a segunda banca');

reset role;

-- O pagamento entra pela porta de sempre, que e o webhook.
select is(
  public.aplicar_efeito_de_pagamento(
    (select id from public.law_firm_license_subscriptions
      where owner_profile_id = 'c1000000-0000-0000-0000-00000000000a'
        and law_firm_id is null),
    'ativar'),
  'active',
  'o pagamento da segunda licenca e aplicado');

select set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-00000000000a', true);
set local role authenticated;

select is(
  public.has_law_firm_license('c1000000-0000-0000-0000-00000000000a'),
  true,
  'e SO entao o portao da segunda banca abre');

select lives_ok(
  $$insert into public.law_firm_verifications (owner_profile_id, firm_name, cnpj, status)
    values ('c1000000-0000-0000-0000-00000000000a','Banca Dois','11222333000181','pending')$$,
  'e o pedido da segunda banca passa');

reset role;

select is(
  (select count(*)::int from public.law_firm_license_subscriptions
    where owner_profile_id = 'c1000000-0000-0000-0000-00000000000a'),
  2,
  'duas bancas, duas assinaturas: um escritorio, uma licenca');

-- ---------------------------------------------------------------------------
-- Trocar o plano DE UM ESCRITÓRIO exige ser gestor dele
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-00000000000b', true);
set local role authenticated;

select throws_ok(
  $$select * from public.choose_law_firm_plan('banca','monthly','cf100000-0000-0000-0000-000000000001')$$,
  'Only active office owners and admins can change the plan',
  'estagiario nao troca o plano da banca');

reset role;

select set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-00000000000a', true);
set local role authenticated;

-- ASSINATURA JA COBRADA nao troca de plano por aqui. A assinatura da banca
-- esta 'active' desde a secao anterior, e trocar o plano seria um UPDATE no
-- nosso plan_code que nao muda o valor no provedor: o escritorio usaria o
-- plano caro pagando o barato, ou pagaria o caro tendo pedido o barato.
-- Ver a 20260906120000.
select throws_ok(
  $$select * from public.choose_law_firm_plan('banca','monthly','cf100000-0000-0000-0000-000000000001')$$,
  'Plan change requires billing update',
  'assinatura ja cobrada nao troca de plano sem falar com o provedor');

reset role;

-- Durante o TESTE nada foi cobrado ainda, entao nao ha valor no provedor para
-- divergir, e a troca passa.
update public.law_firm_license_subscriptions
set status = 'trialing', trial_ends_at = now() + interval '10 days'
where law_firm_id = 'cf100000-0000-0000-0000-000000000001';

select set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-00000000000a', true);
set local role authenticated;

select is(
  (select plan_code from public.choose_law_firm_plan('banca','monthly','cf100000-0000-0000-0000-000000000001')),
  'banca',
  'durante o teste o socio troca o plano da banca dele');

-- Trocar o plano do escritorio NAO pode mexer na licenca nova, que ainda nao
-- foi gasta: sao duas coisas separadas.
select is(
  (select plan_code from public.law_firm_license_subscriptions
    where owner_profile_id = 'c1000000-0000-0000-0000-00000000000a'
      and law_firm_id is null),
  'essencial',
  'e a licenca ainda nao gasta fica intocada');

reset role;

select * from finish();
rollback;
