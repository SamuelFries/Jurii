-- Testes da migration 20260821120000: licenciamento do escritorio.
--
-- As tres coisas que precisam estar travadas:
--   1. A PAYWALL: verificar escritorio sem assinatura nao entra (e a policy,
--      nao a tela — portao que so existe na tela nao e portao).
--   2. O TESTE GRATIS nao renova trocando de plano.
--   3. O TETO de advogados morde no convite — mas SO para quem tem
--      assinatura: os 40 escritorios aprovados antes da regra nao ganham
--      trava retroativa.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(22);

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('f3000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'fundador@licenca.test', '', now(), '{}'::jsonb,
   '{"full_name":"Fundador Licenca"}'::jsonb, now(), now()),
  ('f3000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'veterano@licenca.test', '', now(), '{}'::jsonb,
   '{"full_name":"Dono Veterano"}'::jsonb, now(), now());

-- ---------------------------------------------------------------------------
-- Planos: dados na mesa
-- ---------------------------------------------------------------------------

select results_eq(
  $$select code, max_lawyers, monthly_price_cents
    from public.law_firm_license_plans where is_active
    order by sort_order$$,
  $$values ('essencial', 3, 14900),
           ('escritorio', 10, 34900),
           ('banca', 25, 69900)$$,
  'os tres planos com preco por tamanho de equipe');

-- ---------------------------------------------------------------------------
-- A PAYWALL
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'f3000000-0000-0000-0000-000000000001', true);
set local role authenticated;

-- Sem plano, o cadastro nem entra. E RLS (42501), nao mensagem de tela.
select throws_ok(
  $$insert into public.law_firm_verifications
      (owner_profile_id, firm_name, cnpj, practice_areas)
    values ('f3000000-0000-0000-0000-000000000001', 'Sem Plano',
            '11222333000181', array['Direito Cível'])$$,
  '42501',
  null,
  'PAYWALL: verificar escritorio sem assinatura e barrado pelo banco');

select is(
  (select status from public.choose_law_firm_plan('essencial')),
  'trialing',
  'escolher plano cria a assinatura em teste gratis');

select ok(
  (select trial_ends_at > now() + interval '29 days'
     and trial_ends_at < now() + interval '31 days'
   from public.law_firm_license_subscriptions
   where owner_profile_id = 'f3000000-0000-0000-0000-000000000001'),
  'o teste gratis dura 30 dias');

select lives_ok(
  $$insert into public.law_firm_verifications
      (owner_profile_id, firm_name, cnpj, practice_areas)
    values ('f3000000-0000-0000-0000-000000000001', 'Fundador Advocacia',
            '11222333000181', array['Direito Cível'])$$,
  'com assinatura, o MESMO insert passa');

-- Trocar de plano nao renova o teste: pular de plano em plano nao pode virar
-- teste infinito.
select is(
  (select p.trocou from (
     select (select trial_ends_at from public.choose_law_firm_plan('banca'))
       = (select trial_ends_at
          from public.law_firm_license_subscriptions
          where owner_profile_id = 'f3000000-0000-0000-0000-000000000001')
     as trocou) p),
  true,
  'trocar de plano preserva o fim do teste gratis');

select is(
  (select plan_code from public.law_firm_license_subscriptions
    where owner_profile_id = 'f3000000-0000-0000-0000-000000000001'),
  'banca',
  'e o plano novo valeu');

select throws_ok(
  $$select public.choose_law_firm_plan('plano_inventado')$$,
  'Unknown plan: plano_inventado',
  'plano inexistente e recusado nomeando o valor');

reset role;

-- ---------------------------------------------------------------------------
-- Aprovacao vincula a assinatura ao escritorio
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select public.approve_law_firm_verification(
      (select id from public.law_firm_verifications
        where firm_name = 'Fundador Advocacia'),
      'f3000000-0000-0000-0000-000000000002')$$,
  'aprovacao roda');

select ok(
  (select law_firm_id is not null
   from public.law_firm_license_subscriptions
   where owner_profile_id = 'f3000000-0000-0000-0000-000000000001'),
  'a assinatura foi vinculada ao escritorio criado');

-- ---------------------------------------------------------------------------
-- O teto de advogados morde no convite
-- ---------------------------------------------------------------------------

-- Volta o plano para o menor (teto 3) e enche as vagas: 3 advogados entre
-- ativos e convidados. Convite pendente OCUPA vaga — senao daria para
-- convidar 50 e deixa-los pingar por cima do teto.
update public.law_firm_license_subscriptions
set plan_code = 'essencial'
where owner_profile_id = 'f3000000-0000-0000-0000-000000000001';

-- law_firm_members.profile_id tem FK para profiles: os advogados sinteticos
-- precisam de usuario de verdade (o gatilho de auth.users cria o profile).
insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select
  ('f5000000-0000-0000-0000-00000000000' || n)::uuid,
  'authenticated', 'authenticated',
  'vaga' || n || '@licenca.test', '', now(), '{}'::jsonb,
  '{"full_name":"Vaga"}'::jsonb, now(), now()
from generate_series(1, 8) n;

insert into public.law_firm_members
  (law_firm_id, profile_id, member_role, roles, status)
select
  (select law_firm_id from public.law_firm_license_subscriptions
    where owner_profile_id = 'f3000000-0000-0000-0000-000000000001'),
  ('f5000000-0000-0000-0000-00000000000' || n)::uuid, 'lawyer', array['lawyer'],
  (case when n = 3 then 'invited' else 'active' end)::public.law_firm_member_status
from generate_series(1, 3) n;

-- Advogado-alvo do convite, verificado e aprovado.
insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('f3000000-0000-0000-0000-000000000009', 'authenticated', 'authenticated',
   'alvo@licenca.test', '', now(), '{}'::jsonb,
   '{"full_name":"Alvo Convite"}'::jsonb, now(), now());

update public.profiles set lawyer_status = 'approved'
where id = 'f3000000-0000-0000-0000-000000000009';

insert into public.lawyer_profiles
  (id, oab_number, oab_state, primary_area, practice_areas, approved_at)
values
  ('f3000000-0000-0000-0000-000000000009', '909090', 'RS',
   'Direito Cível', array['Direito Cível'], now());

insert into public.lawyer_verifications
  (user_id, oab_number, oab_state, practice_area, practice_areas, status)
values
  ('f3000000-0000-0000-0000-000000000009', '909090', 'RS',
   'Direito Cível', array['Direito Cível'], 'approved');

select set_config('request.jwt.claim.sub', 'f3000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select throws_ok(
  $$select public.invite_verified_lawyer_to_law_firm(
      (select s.law_firm_id from public.law_firm_license_subscriptions s
        where s.owner_profile_id = 'f3000000-0000-0000-0000-000000000001'),
      'RS', '909090')$$,
  'Lawyer seat limit reached for the current plan',
  'com o teto cheio, o 4o convite e recusado nomeando o motivo');

reset role;

-- Upgrade libera na hora: e assim que o preco por tamanho vira receita.
update public.law_firm_license_subscriptions
set plan_code = 'escritorio'
where owner_profile_id = 'f3000000-0000-0000-0000-000000000001';

set local role authenticated;

select lives_ok(
  $$select public.invite_verified_lawyer_to_law_firm(
      (select s.law_firm_id from public.law_firm_license_subscriptions s
        where s.owner_profile_id = 'f3000000-0000-0000-0000-000000000001'),
      'RS', '909090')$$,
  'depois do upgrade o mesmo convite passa');

reset role;

-- ---------------------------------------------------------------------------
-- Escritorio SEM assinatura (os 40 de producao): nada muda para ele
-- ---------------------------------------------------------------------------

insert into public.law_firms (id, name, initials, specialty, practice_areas, is_active)
values ('f4000000-0000-0000-0000-000000000001', 'Firma Veterana', 'FV',
        'Direito Cível', array['Direito Cível'], true);

insert into public.law_firm_members (law_firm_id, profile_id, member_role, roles, status)
values ('f4000000-0000-0000-0000-000000000001',
        'f3000000-0000-0000-0000-000000000002', 'owner', array['owner'], 'active');

-- Ja tem 5 advogados — acima do teto do menor plano.
insert into public.law_firm_members (law_firm_id, profile_id, member_role, roles, status)
select 'f4000000-0000-0000-0000-000000000001',
       ('f5000000-0000-0000-0000-00000000000' || n)::uuid,
       'lawyer', array['lawyer'], 'active'
from generate_series(4, 8) n;

select set_config('request.jwt.claim.sub', 'f3000000-0000-0000-0000-000000000002', true);
set local role authenticated;

select lives_ok(
  $$select public.invite_verified_lawyer_to_law_firm(
      'f4000000-0000-0000-0000-000000000001', 'RS', '909090')$$,
  'escritorio aprovado ANTES da regra convida sem teto (sem trava retroativa)');

-- Dono de escritorio que ja tem assinatura de OUTRA pessoa nao abre a segunda.
select set_config('request.jwt.claim.sub', 'f3000000-0000-0000-0000-000000000009', true);
set local role authenticated;

reset role;
update public.law_firm_members
set status = 'active', lawyer_invite_status = 'active'
where profile_id = 'f3000000-0000-0000-0000-000000000009'
   or pending_lawyer_id = 'f3000000-0000-0000-0000-000000000009';
set local role authenticated;

select throws_ok(
  $$select public.choose_law_firm_plan('essencial')$$,
  'Firm already has a subscription',
  'membro de escritorio ja assinado nao abre segunda assinatura');

reset role;

-- ---------------------------------------------------------------------------
-- Cobranca anual (20260822120000)
-- ---------------------------------------------------------------------------

-- 20% de desconto com equivalente mensal REDONDO: e ele que a tela mostra.
select results_eq(
  $$select code, annual_price_cents from public.law_firm_license_plans
    where is_active order by sort_order$$,
  $$values ('essencial', 148800), ('escritorio', 348000), ('banca', 696000)$$,
  'preco anual seedado com 17% de desconto');

-- O equivalente mensal tem que dar reais inteiros: e o unico numero que a
-- tela mostra no ciclo anual. Preco que divide quebrado viraria "R$ 123,67".
select is(
  (select count(*)::int from public.law_firm_license_plans
    where is_active and annual_price_cents % 1200 <> 0),
  0,
  'todo preco anual divide em 12 parcelas de reais inteiros');

-- Os tres no MESMO desconto: a tela mostra o MENOR deles, entao um plano
-- fora da linha derruba o selo inteiro sem ninguem notar.
select is(
  (select count(distinct round(100 - annual_price_cents * 100.0
     / (monthly_price_cents * 12)))::int
   from public.law_firm_license_plans where is_active),
  1,
  'os tres planos fecham no mesmo desconto arredondado');

select set_config('request.jwt.claim.sub', 'f3000000-0000-0000-0000-000000000009', true);
set local role authenticated;

select throws_ok(
  $$select public.choose_law_firm_plan('essencial', 'quinzenal')$$,
  'Unknown billing cycle: quinzenal',
  'ciclo desconhecido e recusado nomeando o valor');

reset role;

-- O fundador troca para o anual: MESMA assinatura, ciclo novo, teste intacto.
select set_config('request.jwt.claim.sub', 'f3000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select is(
  (select billing_cycle from public.choose_law_firm_plan('banca', 'annual')),
  'annual',
  'trocar para o anual grava o ciclo na mesma assinatura');

select is(
  (select count(*)::int from public.law_firm_license_subscriptions
    where owner_profile_id = 'f3000000-0000-0000-0000-000000000001'
      and status <> 'canceled'),
  1,
  'continua UMA assinatura viva, nao duas');

reset role;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

select ok(
  has_table_privilege('authenticated', 'public.law_firm_license_plans', 'select')
  and not has_table_privilege('anon', 'public.law_firm_license_plans', 'select')
  and not has_table_privilege('authenticated',
    'public.law_firm_license_subscriptions', 'insert'),
  'planos legiveis; assinatura so por RPC');

select ok(
  has_function_privilege('authenticated',
    'public.choose_law_firm_plan(text, text)', 'execute')
  and not has_function_privilege('anon',
    'public.choose_law_firm_plan(text, text)', 'execute'),
  'so authenticated escolhe plano');

select * from finish();
rollback;
