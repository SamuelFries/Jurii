-- Conta com e-mail de verdade.
--
-- O que este arquivo trava: a recusa acontece no BANCO (não na tela), pega
-- subdomínio, sobrevive a maiúsculas e espaços, vale também na troca de
-- endereço, e não atrapalha quem usa provedor legítimo. O caso mais
-- importante é o penúltimo: o "Ocultar meu e-mail" da Apple precisa passar,
-- senão o login com Apple deixa de criar conta.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(22);

-- ---------------------------------------------------------------------------
-- 1. A função que decide
-- ---------------------------------------------------------------------------
select ok(
  public.email_e_descartavel('abusador@mailinator.com'),
  'domínio da lista é descartável'
);

select ok(
  public.email_e_descartavel('abusador@qualquer.mailinator.com'),
  'subdomínio não contorna (o contorno mais barato que existe)'
);

select ok(
  public.email_e_descartavel('abusador@a.b.c.mailinator.com'),
  'subdomínio de vários níveis também não contorna'
);

select ok(
  public.email_e_descartavel('ABUSADOR@MAILINATOR.COM'),
  'caixa alta não contorna'
);

select ok(
  public.email_e_descartavel('  abusador@YopMail.com  '),
  'espaço em volta não contorna'
);

select ok(
  public.email_e_descartavel('abusador@mailinator.com.'),
  'ponto final do FQDN absoluto não contorna'
);

select ok(
  public.email_e_descartavel('abusador@emailtemporario.com.br'),
  'descartável brasileiro está coberto'
);

select ok(
  not public.email_e_descartavel('ana@gmail.com'),
  'provedor comum passa'
);

select ok(
  not public.email_e_descartavel('ana@escritorio.adv.br'),
  'domínio próprio de escritório passa'
);

-- O "Ocultar meu e-mail" da Apple. Se um dia alguém puser este domínio na
-- lista, o login com Apple para de criar conta e ninguém vai entender por quê.
select ok(
  not public.email_e_descartavel('abc123@privaterelay.appleid.com'),
  'o e-mail privado da Apple passa (login com Apple depende disso)'
);

select ok(
  not public.email_e_descartavel('ana@uol.com.br'),
  'provedor brasileiro comum passa'
);

-- Nunca casar pelo TLD sozinho: bloquearia um país inteiro.
select is(
  (select count(*)::int from public.disposable_email_domains
    where domain not like '%.%'),
  0,
  'a lista não tem entrada sem ponto (TLD solto bloquearia domínio legítimo)'
);

select ok(
  not public.email_e_descartavel('sem-arroba'),
  'entrada sem @ não estoura nem bloqueia'
);

select ok(
  not public.email_e_descartavel(null),
  'nulo não estoura nem bloqueia'
);

-- ---------------------------------------------------------------------------
-- 2. A barreira: o gatilho em auth.users
-- ---------------------------------------------------------------------------
select throws_ok(
  $$insert into auth.users (id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    values ('e1000000-0000-4000-8000-000000000001','authenticated','authenticated',
      'abusador@mailinator.com','',now(),'{}','{"full_name":"Abusador"}',now(),now())$$,
  '23514',
  'Disposable email domains are not allowed',
  'cadastro com e-mail descartável é recusado pelo banco, não pela tela'
);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('e1000000-0000-4000-8000-000000000002','authenticated','authenticated',
  'ana@gmail.com','',now(),'{}','{"full_name":"Ana Legitima"}',now(),now());

select ok(
  exists (select 1 from public.profiles where id = 'e1000000-0000-4000-8000-000000000002'),
  'cadastro legítimo continua nascendo com perfil'
);

-- Trocar o endereço depois de entrar seria a porta dos fundos.
select throws_ok(
  $$update auth.users set email = 'ana@mailinator.com'
      where id = 'e1000000-0000-4000-8000-000000000002'$$,
  '23514',
  'Disposable email domains are not allowed',
  'trocar para e-mail descartável depois do cadastro também é recusado'
);

-- O pedido de troca (email_change) é onde o link de confirmação nasce:
-- recusar só no final deixaria a pessoa esperar um e-mail que não vale.
select throws_ok(
  $$update auth.users set email_change = 'ana@yopmail.com'
      where id = 'e1000000-0000-4000-8000-000000000002'$$,
  '23514',
  'Disposable email domains are not allowed',
  'pedido de troca para descartável é recusado já na origem'
);

select lives_ok(
  $$update auth.users set email = 'ana.nova@uol.com.br'
      where id = 'e1000000-0000-4000-8000-000000000002'$$,
  'trocar para e-mail legítimo continua permitido'
);

-- ---------------------------------------------------------------------------
-- 3. A lista não é leitura de cliente
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = 'e1000000-0000-4000-8000-000000000002';

-- Nem "zero linhas": a tabela não é sequer legível. Uma policy futura que
-- abrisse leitura passaria despercebida num teste que só contasse linhas.
select throws_ok(
  'select count(*) from public.disposable_email_domains',
  '42501',
  'permission denied for table disposable_email_domains',
  'usuário autenticado não lê a lista (sem grant, sem policy)'
);

-- A função definer continua respondendo: é ela que a tela consulta.
select ok(
  public.email_e_descartavel('abusador@mailinator.com'),
  'mas a função definer responde a quem está logado (a tela pergunta por ela)'
);

reset role;

set local role anon;
select ok(
  public.email_e_descartavel('abusador@mailinator.com'),
  'e responde a anon também: quem ainda não tem conta é justamente quem cadastra'
);
reset role;

select * from finish();
rollback;
