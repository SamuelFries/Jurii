-- O teto não pode ter porta dos fundos, e a assinatura não pode ter duas vidas.
--
-- Estes três casos vieram de uma revisão adversarial das PRÓPRIAS correções da
-- 20260906120000. Todos são do tipo que faz o resto do trabalho não valer
-- nada: a trava existia, e havia um caminho ao lado dela.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(20);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('e1000000-0000-0000-0000-00000000000a','authenticated','authenticated','dono@e.test','',now(),'{}','{"full_name":"Dono"}',now(),now()),
  ('e1000000-0000-0000-0000-00000000000b','authenticated','authenticated','sec1@e.test','',now(),'{}','{"full_name":"Secretario Um"}',now(),now()),
  ('e1000000-0000-0000-0000-00000000000c','authenticated','authenticated','sec2@e.test','',now(),'{}','{"full_name":"Secretario Dois"}',now(),now()),
  ('e1000000-0000-0000-0000-00000000000d','authenticated','authenticated','sec3@e.test','',now(),'{}','{"full_name":"Secretario Tres"}',now(),now());

insert into public.law_firms (id, name, initials, specialty, is_active, cep, oab_state)
values ('ef000000-0000-0000-0000-000000000001','Banca Teto','BT','Direito Cível',true,'90540140','RS');

insert into public.law_firm_members (law_firm_id, profile_id, roles, member_role, role, status)
values
  ('ef000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-00000000000a',array['owner'],'owner','owner','active'),
  ('ef000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-00000000000b',array['secretary'],'secretary','secretary','active'),
  ('ef000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-00000000000c',array['secretary'],'secretary','secretary','active'),
  ('ef000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-00000000000d',array['secretary'],'secretary','secretary','active');

-- Essencial: teto de 3 advogados. E a assinatura está INADIMPLENTE, ou seja,
-- teto efetivo zero.
insert into public.law_firm_license_subscriptions
  (id, owner_profile_id, law_firm_id, plan_code, billing_cycle, status)
values
  ('ea000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-00000000000a',
   'ef000000-0000-0000-0000-000000000001','essencial','monthly','past_due');

-- ---------------------------------------------------------------------------
-- 1. A PORTA DOS FUNDOS: promover, em vez de convidar
-- ---------------------------------------------------------------------------
select is(public.teto_de_advogados('ef000000-0000-0000-0000-000000000001'), 0,
  'a banca esta inadimplente, entao o teto e zero');

select set_config('request.jwt.claim.sub','e1000000-0000-0000-0000-00000000000a', true);
set local role authenticated;

-- O convite já era barrado pela 20260906120000. O que NÃO era: promover
-- alguém que já está dentro. Eram dois cliques na tela de equipe.
select throws_ok(
  $$select public.update_law_firm_member_roles(
      'ef000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-00000000000b',
      array['lawyer'])$$,
  'Subscription is not active',
  'promover secretario a advogado com assinatura parada e RECUSADO');

reset role;

select is(
  (select count(*)::int from public.law_firm_members m
   where m.law_firm_id = 'ef000000-0000-0000-0000-000000000001'
     and 'lawyer' = any(m.roles)),
  0,
  'e a banca continua sem advogado nenhum');

-- ---------------------------------------------------------------------------
-- 2. Com a assinatura VIVA, o teto do plano também vale na promoção
-- ---------------------------------------------------------------------------
update public.law_firm_license_subscriptions
set status = 'active' where id = 'ea000000-0000-0000-0000-000000000001';

select set_config('request.jwt.claim.sub','e1000000-0000-0000-0000-00000000000a', true);
set local role authenticated;

-- Essencial tem teto 3, e o dono não é advogado: cabem três promoções.
select lives_ok(
  $$select public.update_law_firm_member_roles(
      'ef000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-00000000000b', array['lawyer'])$$,
  'com assinatura ativa, a primeira promocao passa');

select lives_ok(
  $$select public.update_law_firm_member_roles(
      'ef000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-00000000000c', array['lawyer'])$$,
  'a segunda tambem');

select lives_ok(
  $$select public.update_law_firm_member_roles(
      'ef000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-00000000000d', array['lawyer'])$$,
  'a terceira fecha o teto do essencial');

reset role;

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('e1000000-0000-0000-0000-00000000000e','authenticated','authenticated','sec4@e.test','',now(),'{}','{"full_name":"Secretario Quatro"}',now(),now());

insert into public.law_firm_members (law_firm_id, profile_id, roles, member_role, role, status)
values ('ef000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-00000000000e',array['secretary'],'secretary','secretary','active');

select set_config('request.jwt.claim.sub','e1000000-0000-0000-0000-00000000000a', true);
set local role authenticated;

select throws_ok(
  $$select public.update_law_firm_member_roles(
      'ef000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-00000000000e', array['lawyer'])$$,
  'Lawyer seat limit reached for the current plan',
  'a quarta promocao bate no teto do plano, com a mensagem do teto');

-- REBAIXAR nunca e barrado: nao ocupa vaga nova, e um teto cheio nao pode
-- impedir a banca de encolher.
select lives_ok(
  $$select public.update_law_firm_member_roles(
      'ef000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-00000000000d', array['secretary'])$$,
  'rebaixar advogado a secretario passa mesmo com o teto cheio');

-- E a vaga liberada pode ser reocupada: o teto conta, nao proibe.
select lives_ok(
  $$select public.update_law_firm_member_roles(
      'ef000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-00000000000e', array['lawyer'])$$,
  'e a vaga que abriu pode ser ocupada por outro');

reset role;

-- ---------------------------------------------------------------------------
-- 3. Recontratar reaproveita a LINHA, e não cria uma segunda referência
-- ---------------------------------------------------------------------------
--
-- O id da nossa assinatura é o `externalReference` que amarra tudo no
-- provedor. Uma linha nova teria id novo, a busca de idempotência do checkout
-- não acharia a assinatura ainda viva no Asaas, e nasceria a segunda: duas
-- mensalidades recorrentes ao mesmo tempo.
update public.law_firm_license_subscriptions
set status = 'canceled' where id = 'ea000000-0000-0000-0000-000000000001';

select set_config('request.jwt.claim.sub','e1000000-0000-0000-0000-00000000000a', true);
set local role authenticated;

select is(
  (select id from public.choose_law_firm_plan(
     'escritorio','monthly','ef000000-0000-0000-0000-000000000001')),
  'ea000000-0000-0000-0000-000000000001'::uuid,
  'recontratar REAPROVEITA a linha cancelada, mantendo a referencia do provedor');

reset role;

select is(
  (select count(*)::int from public.law_firm_license_subscriptions
   where law_firm_id = 'ef000000-0000-0000-0000-000000000001'),
  1,
  'e continua sendo UMA linha, nao duas');

-- ---------------------------------------------------------------------------
-- 4. O teste grátis é um POR PESSOA, e não um por linha
-- ---------------------------------------------------------------------------
--
-- A 20260906120000 fechou isto só no ramo COM escritório. No ramo da licença
-- não gasta, cancelar e recontratar seguia rendendo 30 dias novos, e o ciclo
-- podia se repetir para sempre no plano de 25 advogados.
insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('e1000000-0000-0000-0000-00000000000f','authenticated','authenticated','girador@e.test','',now(),'{}','{"full_name":"Girador"}',now(),now());

select set_config('request.jwt.claim.sub','e1000000-0000-0000-0000-00000000000f', true);
set local role authenticated;

select is(
  (select status from public.choose_law_firm_plan('banca','monthly')),
  'trialing',
  'a PRIMEIRA licenca da vida ganha o teste gratis');

reset role;

update public.law_firm_license_subscriptions
set status = 'canceled'
where owner_profile_id = 'e1000000-0000-0000-0000-00000000000f';

select set_config('request.jwt.claim.sub','e1000000-0000-0000-0000-00000000000f', true);
set local role authenticated;

select is(
  (select status from public.choose_law_firm_plan('banca','monthly')),
  'past_due',
  'cancelar e recontratar NAO devolve o teste: nasce a pagar');

select is(
  (select trial_ends_at from public.law_firm_license_subscriptions
   where owner_profile_id = 'e1000000-0000-0000-0000-00000000000f'
     and status <> 'canceled'),
  null,
  'e sem data de teste para o relogio recomecar');

reset role;

-- ---------------------------------------------------------------------------
-- 5. O árbitro da corrida: quem grava primeiro ganha, e o outro fica sabendo
-- ---------------------------------------------------------------------------
--
-- Procurar no provedor antes de criar não fecha corrida nenhuma: entre a busca
-- e o POST cabem três viagens de rede, e dois cliques simultâneos tiram a mesma
-- foto vazia. O compare-and-set desta função é o único ponto onde só um passa.
select set_config('request.jwt.claim.sub','e1000000-0000-0000-0000-00000000000a', true);
set local role authenticated;

select is(
  public.registrar_assinatura_no_provedor(
    'ea000000-0000-0000-0000-000000000001','sub_primeira'),
  'sub_primeira',
  'quem grava primeiro recebe de volta o proprio id');

-- O SEGUNDO CLIQUE. A resposta diferente do que ele mandou é como ele descobre
-- que perdeu, e que a assinatura que acabou de criar no provedor é duplicata a
-- apagar antes de virar mensalidade.
select is(
  public.registrar_assinatura_no_provedor(
    'ea000000-0000-0000-0000-000000000001','sub_segunda'),
  'sub_primeira',
  'quem chega depois recebe o VENCEDOR, e nao o proprio id');

select is(
  (select provider_subscription_id from public.law_firm_license_subscriptions
   where id = 'ea000000-0000-0000-0000-000000000001'),
  'sub_primeira',
  'e a coluna nao foi sobrescrita');

-- Texto qualquer não entra: a coluna é lida de volta para montar caminho de
-- URL na API do provedor.
select throws_ok(
  $$select public.registrar_assinatura_no_provedor(
      'ea000000-0000-0000-0000-000000000001','../../customers')$$,
  'Invalid provider subscription id',
  'id fora do formato do provedor e recusado');

reset role;

-- E a assinatura de OUTRA pessoa não se registra: a função responde só sobre
-- quem chama.
--
-- A linha alvo precisa estar com a coluna VAZIA, senão o teste passaria pelo
-- motivo errado: com a coluna já preenchida, o `is null` do compare-and-set
-- barra a escrita sozinho e a trava de dono nunca chega a ser exercida.
insert into public.law_firm_license_subscriptions
  (id, owner_profile_id, plan_code, billing_cycle, status, trial_ends_at)
values
  ('ea000000-0000-0000-0000-000000000002','e1000000-0000-0000-0000-00000000000b',
   'essencial','monthly','trialing', now() + interval '30 days');

select set_config('request.jwt.claim.sub','e1000000-0000-0000-0000-00000000000a', true);
set local role authenticated;

select throws_ok(
  $$select public.registrar_assinatura_no_provedor(
      'ea000000-0000-0000-0000-000000000002','sub_invasora')$$,
  'Subscription not found',
  'quem nao e dono da assinatura nao aponta ela para lugar nenhum');

reset role;

select is(
  (select provider_subscription_id from public.law_firm_license_subscriptions
   where id = 'ea000000-0000-0000-0000-000000000002'),
  null,
  'e a coluna da assinatura alheia continua vazia');

select * from finish();
rollback;
