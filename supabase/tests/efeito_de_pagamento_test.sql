-- A porta do webhook.
--
-- O que este arquivo protege: que nenhum cliente alcance a função; que
-- reentrega do provedor não vire estrago; e que assinatura cancelada não
-- ressuscite por evento atrasado.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(12);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('a1000000-0000-0000-0000-000000000001','authenticated','authenticated','pagante@p.test','',now(),'{}','{"full_name":"Pagante"}',now(),now()),
  ('a1000000-0000-0000-0000-000000000002','authenticated','authenticated','curioso@p.test','',now(),'{}','{"full_name":"Curioso"}',now(),now());

insert into public.law_firm_license_subscriptions
  (id, owner_profile_id, plan_code, billing_cycle, status, trial_ends_at)
values
  ('a5000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001',
   'essencial','monthly','trialing', now() + interval '30 days');

-- ---------------------------------------------------------------------------
-- Ninguém do lado do cliente alcança a porta
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select throws_ok(
  $$select public.aplicar_efeito_de_pagamento(
      'a5000000-0000-0000-0000-000000000001', 'ativar')$$,
  '42501',
  'permission denied for function aplicar_efeito_de_pagamento',
  'nem o dono da assinatura ativa a propria assinatura');

reset role;
set local role anon;

select throws_ok(
  $$select public.aplicar_efeito_de_pagamento(
      'a5000000-0000-0000-0000-000000000001', 'ativar')$$,
  '42501',
  'permission denied for function aplicar_efeito_de_pagamento',
  'e anonimo muito menos');

reset role;

select is(
  (select count(*)::int from information_schema.role_routine_grants
    where routine_schema='public' and routine_name='aplicar_efeito_de_pagamento'
      and grantee in ('authenticated','anon','public')),
  0,
  'a porta so tem grant para service_role');

-- ---------------------------------------------------------------------------
-- O que o webhook faz, com a chave que ele tem
-- ---------------------------------------------------------------------------
set local role service_role;

select is(
  public.aplicar_efeito_de_pagamento('a5000000-0000-0000-0000-000000000001','ativar'),
  'active',
  'pagamento confirmado ativa a assinatura');

-- REENTREGA: o provedor manda de novo quando nao recebe 200 a tempo. Isso e
-- normal, e aplicar duas vezes tem que dar no mesmo.
select is(
  public.aplicar_efeito_de_pagamento('a5000000-0000-0000-0000-000000000001','ativar'),
  'sem mudanca',
  'reentrega do mesmo evento nao muda nada');

select is(
  public.aplicar_efeito_de_pagamento('a5000000-0000-0000-0000-000000000001','pagamento_pendente'),
  'past_due',
  'falha de cobranca leva a past_due');

select is(
  public.aplicar_efeito_de_pagamento('a5000000-0000-0000-0000-000000000001','ativar'),
  'active',
  'e o pagamento que vem depois traz de volta');

-- Assinatura que nao existe nao e erro: o provedor pode chamar sobre
-- cobranca de teste, e quem recebe precisa responder 200 em vez de fazer
-- o provedor reentregar para sempre.
select is(
  public.aplicar_efeito_de_pagamento('a5000000-0000-0000-0000-0000000000ff','ativar'),
  'desconhecida',
  'assinatura inexistente responde sem estourar');

select throws_ok(
  $$select public.aplicar_efeito_de_pagamento(
      'a5000000-0000-0000-0000-000000000001', 'liberar_geral')$$,
  'Unknown payment effect: liberar_geral',
  'efeito desconhecido e recusado nomeando o valor');

-- ---------------------------------------------------------------------------
-- Cancelada NÃO volta por webhook
-- ---------------------------------------------------------------------------
select is(
  public.aplicar_efeito_de_pagamento('a5000000-0000-0000-0000-000000000001','cancelar'),
  'canceled',
  'cancelamento cancela');

-- Evento atrasado de pagamento chegando DEPOIS do cancelamento nao pode
-- devolver acesso a quem ja saiu. Reativar e contratar de novo, e isso passa
-- por choose_law_firm_plan, com a pessoa decidindo.
select is(
  public.aplicar_efeito_de_pagamento('a5000000-0000-0000-0000-000000000001','ativar'),
  'ignorada',
  'evento atrasado NAO ressuscita assinatura cancelada');

reset role;

select is(
  (select status from public.law_firm_license_subscriptions
    where id = 'a5000000-0000-0000-0000-000000000001'),
  'canceled',
  'e a linha continua cancelada no banco');

select * from finish();
rollback;
