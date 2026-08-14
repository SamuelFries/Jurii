-- A cobrança com consequência.
--
-- Este arquivo existe porque o produto tinha status de assinatura sem que
-- status de assinatura significasse nada: o teste de 30 dias nunca vencia, e
-- quem ficava sem assinatura viva ganhava teto INFINITO de advogados em vez de
-- teto nenhum. Cancelar era o upgrade mais barato da casa.
--
-- A regra em uma frase: sem assinatura viva o escritório não CRESCE, e quem já
-- está dentro continua trabalhando.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(23);

-- ---------------------------------------------------------------------------
-- Cenário
-- ---------------------------------------------------------------------------
insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('d1000000-0000-0000-0000-00000000000a','authenticated','authenticated','socio@d.test','',now(),'{}','{"full_name":"Socio Pagante"}',now(),now()),
  ('d1000000-0000-0000-0000-00000000000b','authenticated','authenticated','veterano@d.test','',now(),'{}','{"full_name":"Socio Veterano"}',now(),now()),
  ('d1000000-0000-0000-0000-00000000000c','authenticated','authenticated','alvo@d.test','',now(),'{}','{"full_name":"Advogado Alvo"}',now(),now());

-- O advogado que os convites tentam trazer: verificado e aprovado, para que a
-- recusa venha do TETO e nunca da verificação dele.
update public.profiles set lawyer_status = 'approved'
where id = 'd1000000-0000-0000-0000-00000000000c';

insert into public.lawyer_profiles
  (id, oab_number, oab_state, primary_area, practice_areas, approved_at)
values
  ('d1000000-0000-0000-0000-00000000000c','818181','RS','Direito Cível',
   array['Direito Cível'], now());

insert into public.lawyer_verifications
  (user_id, oab_number, oab_state, practice_area, practice_areas, status)
values
  ('d1000000-0000-0000-0000-00000000000c','818181','RS','Direito Cível',
   array['Direito Cível'],'approved');

insert into public.law_firms (id, name, initials, specialty, is_active, cep, oab_state)
values
  ('df000000-0000-0000-0000-000000000001','Banca Pagante','BP','Direito Cível',true,'90540140','RS'),
  -- Nunca teve licença: é uma das aprovadas antes do licenciamento, e a regra
  -- não é retroativa.
  ('df000000-0000-0000-0000-000000000002','Banca Veterana','BV','Direito Cível',true,'90540140','RS');

insert into public.law_firm_members (law_firm_id, profile_id, roles, member_role, role, status)
values
  ('df000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-00000000000a',array['owner'],'owner','owner','active'),
  ('df000000-0000-0000-0000-000000000002','d1000000-0000-0000-0000-00000000000b',array['owner'],'owner','owner','active');

insert into public.law_firm_license_subscriptions
  (id, owner_profile_id, law_firm_id, plan_code, billing_cycle, status, trial_ends_at)
values
  ('da000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-00000000000a',
   'df000000-0000-0000-0000-000000000001','essencial','monthly','trialing',
   now() + interval '10 days');

-- ---------------------------------------------------------------------------
-- 1. assinatura_esta_viva: a tabela-verdade inteira
-- ---------------------------------------------------------------------------
select is(public.assinatura_esta_viva('active', null), true,
  'ativa esta viva, com ou sem data de teste');

select is(public.assinatura_esta_viva('trialing', now() + interval '1 day'), true,
  'teste que ainda nao venceu esta vivo');

-- O FURO 1, no menor tamanho possivel: era este `false` que nao existia, e por
-- isso trinta dias eram para sempre.
select is(public.assinatura_esta_viva('trialing', now() - interval '1 day'), false,
  'teste VENCIDO nao esta vivo');

select is(public.assinatura_esta_viva('trialing', null), false,
  'teste sem data de fim vale como vencido, e nao como eterno');

-- past_due FORA de proposito: se inadimplencia ainda desse acesso, derivar o
-- vencimento do teste nao mudaria nada, porque teste vencido viraria past_due
-- e seguiria valendo.
select is(public.assinatura_esta_viva('past_due', now() + interval '1 day'), false,
  'inadimplencia nao esta viva nem com data de teste no futuro');

select is(public.assinatura_esta_viva('canceled', now() + interval '1 day'), false,
  'cancelada nao esta viva');

-- ---------------------------------------------------------------------------
-- 2. teto_de_advogados: null, 0 e N são três coisas diferentes
-- ---------------------------------------------------------------------------
select is(public.teto_de_advogados('df000000-0000-0000-0000-000000000001'), 3,
  'com teste valido, o teto e o do plano contratado');

-- SEM TRAVA RETROATIVA. As bancas aprovadas antes do licenciamento nunca
-- tiveram assinatura, e continuam convidando como sempre.
select is(public.teto_de_advogados('df000000-0000-0000-0000-000000000002'), null,
  'banca que nunca teve licenca segue sem teto');

update public.law_firm_license_subscriptions
set trial_ends_at = now() - interval '1 day'
where id = 'da000000-0000-0000-0000-000000000001';

select is(public.teto_de_advogados('df000000-0000-0000-0000-000000000001'), 0,
  'teste vencido derruba o teto para ZERO, e nao para "sem teto"');

update public.law_firm_license_subscriptions
set status = 'canceled', trial_ends_at = now() + interval '10 days'
where id = 'da000000-0000-0000-0000-000000000001';

-- O FURO 2 na forma em que ele custava dinheiro: estorno e chargeback cancelam
-- a assinatura, e cancelar TIRAVA o teto em vez de fechar a porta.
select is(public.teto_de_advogados('df000000-0000-0000-0000-000000000001'), 0,
  'cancelamento fecha a porta, e nao vira equipe ilimitada');

update public.law_firm_license_subscriptions
set status = 'past_due'
where id = 'da000000-0000-0000-0000-000000000001';

select is(public.teto_de_advogados('df000000-0000-0000-0000-000000000001'), 0,
  'inadimplencia congela o crescimento igual ao teste vencido');

-- ---------------------------------------------------------------------------
-- 3. E o convite obedece
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-00000000000a', true);
set local role authenticated;

select throws_ok(
  $$select public.invite_verified_lawyer_to_law_firm(
      'df000000-0000-0000-0000-000000000001','RS','818181')$$,
  'Subscription is not active',
  'sem assinatura viva o escritorio nao convida, e o erro diz o motivo certo');

reset role;

-- O erro é PRÓPRIO, e não o de teto cheio: "limite do plano" mandaria a pessoa
-- fazer upgrade quando o que resolve o caso dela é pagar.
update public.law_firm_license_subscriptions
set status = 'active'
where id = 'da000000-0000-0000-0000-000000000001';

select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-00000000000a', true);
set local role authenticated;

select lives_ok(
  $$select public.invite_verified_lawyer_to_law_firm(
      'df000000-0000-0000-0000-000000000001','RS','818181')$$,
  'com a assinatura ativa o mesmo convite passa');

reset role;

-- A banca veterana, sem assinatura nenhuma, continua convidando.
select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-00000000000b', true);
set local role authenticated;

select lives_ok(
  $$select public.invite_verified_lawyer_to_law_firm(
      'df000000-0000-0000-0000-000000000002','RS','818181')$$,
  'e a banca sem licenca nenhuma segue convidando (sem trava retroativa)');

reset role;

-- ---------------------------------------------------------------------------
-- 4. Uma licença, um escritório: a segunda aprovação FALHA
-- ---------------------------------------------------------------------------
--
-- O portão (has_law_firm_license) é conferido quando a pessoa PEDE a abertura,
-- e não quando a equipe aprova. Com uma licença só dava para pedir duas
-- bancas, e a segunda aprovação amarrava zero linhas em silêncio: o escritório
-- nascia sem assinatura, o que pela seção 2 significava equipe ilimitada.
insert into public.law_firm_license_subscriptions
  (id, owner_profile_id, plan_code, billing_cycle, status, trial_ends_at)
values
  ('da000000-0000-0000-0000-000000000002','d1000000-0000-0000-0000-00000000000a',
   'essencial','monthly','trialing', now() + interval '30 days');

insert into public.law_firm_verifications (id, owner_profile_id, firm_name, cnpj, status)
values
  ('dc000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-00000000000a',
   'Banca Dois','11222333000181','pending'),
  ('dc000000-0000-0000-0000-000000000002','d1000000-0000-0000-0000-00000000000a',
   'Banca Tres','11222333000262','pending');

select lives_ok(
  $$select public.approve_law_firm_verification(
      'dc000000-0000-0000-0000-000000000001'::uuid,
      'd1000000-0000-0000-0000-00000000000b'::uuid)$$,
  'a primeira aprovacao gasta a licenca e abre a banca');

select throws_ok(
  $$select public.approve_law_firm_verification(
      'dc000000-0000-0000-0000-000000000002'::uuid,
      'd1000000-0000-0000-0000-00000000000b'::uuid)$$,
  'Owner has no unspent license',
  'a segunda aprovacao com a MESMA licenca falha em vez de abrir de graca');

-- E falha inteira: a banca não fica de pé sem assinatura.
select is(
  (select count(*)::int from public.law_firms where name = 'Banca Tres'),
  0,
  'e a banca sem licenca nao chega a existir');

-- E o invariante, e não só o caso: NENHUMA banca deste sócio existe sem
-- assinatura amarrada. Era exatamente essa a forma do furo, uma banca de pé
-- sem linha de cobrança para o teto se ancorar.
select is(
  (select count(*)::int
   from public.law_firms f
   join public.law_firm_members m
     on m.law_firm_id = f.id
    and m.profile_id = 'd1000000-0000-0000-0000-00000000000a'
   where not exists (
     select 1 from public.law_firm_license_subscriptions s
     where s.law_firm_id = f.id)),
  0,
  'nenhuma banca do socio ficou sem assinatura');

-- ---------------------------------------------------------------------------
-- 5. O caminho de volta depois do cancelamento
-- ---------------------------------------------------------------------------
update public.law_firm_license_subscriptions
set status = 'canceled'
where id = 'da000000-0000-0000-0000-000000000001';

select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-00000000000a', true);
set local role authenticated;

-- Antes isto era 'Firm has no subscription' e o escritorio ficava congelado
-- para sempre, sem caminho de volta na aplicacao.
select is(
  (select status from public.choose_law_firm_plan(
     'escritorio','monthly','df000000-0000-0000-0000-000000000001')),
  'past_due',
  'banca cancelada contrata de novo, e a assinatura nova nasce a pagar');

-- E NÃO ganha teste de novo: cancelar e recontratar seria teste infinito.
select is(
  (select trial_ends_at from public.law_firm_license_subscriptions
   where law_firm_id = 'df000000-0000-0000-0000-000000000001'
     and status <> 'canceled'),
  null,
  'a assinatura nova NAO vem com teste gratis outra vez');

reset role;

-- E nada é liberado antes do dinheiro entrar.
select is(public.teto_de_advogados('df000000-0000-0000-0000-000000000001'), 0,
  'e o escritorio segue congelado ate o webhook confirmar o pagamento');

select is(
  public.aplicar_efeito_de_pagamento(
    (select id from public.law_firm_license_subscriptions
     where law_firm_id = 'df000000-0000-0000-0000-000000000001'
       and status <> 'canceled'),
    'ativar'),
  'active',
  'o pagamento entra pela porta de sempre');

select is(public.teto_de_advogados('df000000-0000-0000-0000-000000000001'), 10,
  'e so entao o teto do plano novo vale');

select * from finish();
rollback;
