-- Convite por link de uso único.
--
-- A porta de entrada de quem não tem OAB: o gestor gera, a pessoa PEDE com a
-- própria conta, e um gestor decide (20260914; a função que concedia na hora
-- saiu na 20260916). O que este arquivo trava: uso único de verdade, token
-- guardado como hash, papéis restritos, e as regras da casa valendo na porta
-- nova (gestor cria, congelado não inclui, orçamento de tentativas único).
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(31);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('c2000000-0000-4000-8000-00000000000a','authenticated','authenticated','socio@link.test','',now(),'{}','{"full_name":"Socia Gestora"}',now(),now()),
  ('c2000000-0000-4000-8000-00000000000b','authenticated','authenticated','sec@link.test','',now(),'{}','{"full_name":"Secretaria Nova"}',now(),now()),
  ('c2000000-0000-4000-8000-00000000000c','authenticated','authenticated','outro@link.test','',now(),'{}','{"full_name":"Outra Pessoa"}',now(),now()),
  ('c2000000-0000-4000-8000-00000000000d','authenticated','authenticated','intruso@link.test','',now(),'{}','{"full_name":"Intruso"}',now(),now());

insert into public.law_firms (id, name, initials, specialty, is_active, cep, oab_state)
values ('cf200000-0000-4000-8000-000000000001','Banca do Link','BL','Direito Cível',true,'90540140','RS');

insert into public.law_firm_members (law_firm_id, profile_id, roles, member_role, role, status)
values ('cf200000-0000-4000-8000-000000000001','c2000000-0000-4000-8000-00000000000a',
        array['owner'],'owner','owner','active');

-- ---------------------------------------------------------------------------
-- 1. Criar: quem pode, e para quais papéis
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','c2000000-0000-4000-8000-00000000000a', true);
set local role authenticated;

create temp table link_criado as
select * from public.criar_link_de_convite(
  'cf200000-0000-4000-8000-000000000001','secretary');
grant select on link_criado to public;

select is((select count(*)::int from link_criado), 1,
  'a gestora cria um link de secretaria');

select ok(
  (select length(token) = 48 from link_criado),
  'o token tem 48 hex (24 bytes de aleatorio)');

select ok(
  (select expires_at > now() + interval '6 days' from link_criado),
  'e vence em uma semana');

-- Papéis fora da lista fechada.
select throws_ok(
  $$select * from public.criar_link_de_convite(
      'cf200000-0000-4000-8000-000000000001','lawyer')$$,
  'Invite links are for secretary or intern roles only',
  'advogado NAO entra por link: a porta dele e a OAB, onde mora o teto pago');

select throws_ok(
  $$select * from public.criar_link_de_convite(
      'cf200000-0000-4000-8000-000000000001','admin')$$,
  'Invite links are for secretary or intern roles only',
  'admin por link seria escalacao de privilegio se o link vazar');

reset role;

-- O TOKEN NAO ESTA NA TABELA: só o hash. Conferido como postgres, porque a
-- tabela é trancada até para a gestora (teste da seção 8).
select is(
  (select count(*)::int from public.law_firm_invite_links l
   where l.token_hash = (select token from link_criado)),
  0,
  'o token cru NAO aparece na tabela');

select is(
  (select count(*)::int from public.law_firm_invite_links l
   where l.token_hash = encode(extensions.digest((select token from link_criado),'sha256'),'hex')),
  1,
  'o que a tabela guarda e o hash dele');

-- Quem não administra não cria.
select set_config('request.jwt.claim.sub','c2000000-0000-4000-8000-00000000000d', true);
set local role authenticated;

select throws_ok(
  $$select * from public.criar_link_de_convite(
      'cf200000-0000-4000-8000-000000000001','secretary')$$,
  'Only active office owners and admins can invite',
  'quem nao e gestor da banca nao gera link para ela');

reset role;

-- ---------------------------------------------------------------------------
-- 2. Espiar: o que a página vê antes do aceite
-- ---------------------------------------------------------------------------
set local role anon;

select results_eq(
  format($$select situacao, firm_name, member_role
           from public.espiar_link_de_convite(%L)$$,
         (select token from link_criado)),
  $$values ('valido'::text,'Banca do Link'::text,'secretary'::text)$$,
  'quem chega DESLOGADO com o link ve a banca e o papel');

select results_eq(
  $$select situacao from public.espiar_link_de_convite('token-que-nao-existe')$$,
  $$values ('inexistente'::text)$$,
  'token inventado responde inexistente, sem vazar nada');

reset role;

-- ---------------------------------------------------------------------------
-- 3. Pedir consome o link, mas quem coloca na equipe é a decisão do gestor
--
-- O link PEDE desde a 20260914. A função que concedia na hora
-- (aceitar_link_de_convite) saiu na 20260916: continuava concedida a
-- authenticated e entregava a equipe a quem tivesse o token, contornando a
-- aprovação inteira.
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','c2000000-0000-4000-8000-00000000000b', true);
set local role authenticated;

select isnt(
  (select public.solicitar_entrada_por_link((select token from link_criado)))::text,
  null,
  'a secretaria PEDE entrada e recebe o id do pedido');

reset role;

select is(
  (select count(*)::int from public.law_firm_members
   where law_firm_id='cf200000-0000-4000-8000-000000000001'
     and profile_id='c2000000-0000-4000-8000-00000000000b'),
  0,
  'e pedir NAO coloca ninguem na equipe');

-- USO ÚNICO: o link morre no pedido, então a segunda pessoa fica de fora.
select set_config('request.jwt.claim.sub','c2000000-0000-4000-8000-00000000000c', true);
set local role authenticated;

select throws_ok(
  format($$select public.solicitar_entrada_por_link(%L)$$,
         (select token from link_criado)),
  'Invite link already used',
  'o mesmo link NAO serve para uma segunda pessoa');

reset role;

-- O id do pedido é lido fora do papel de cliente de propósito: quem decide
-- enxerga a fila pela RPC listar_pedidos_de_entrada, não por leitura direta.
create temp table pedido_da_secretaria as
select r.id from public.law_firm_join_requests r
where r.law_firm_id='cf200000-0000-4000-8000-000000000001'
  and r.requester_id='c2000000-0000-4000-8000-00000000000b';
grant select on pedido_da_secretaria to public;

select set_config('request.jwt.claim.sub','c2000000-0000-4000-8000-00000000000a', true);
set local role authenticated;

select is(
  public.decidir_entrada_no_escritorio((select id from pedido_da_secretaria), true),
  'approved',
  'a gestora aprova o pedido');

reset role;

select results_eq(
  $$select m.roles, m.status from public.law_firm_members m
    where m.law_firm_id='cf200000-0000-4000-8000-000000000001'
      and m.profile_id='c2000000-0000-4000-8000-00000000000b'$$,
  $$values (array['secretary']::text[], 'active'::public.law_firm_member_status)$$,
  'e SO ENTAO vira membro ATIVO, com o papel do link');

select is(
  (select count(*)::int from public.law_firm_members
   where law_firm_id='cf200000-0000-4000-8000-000000000001'),
  2,
  'a banca tem exatamente a socia e a secretaria');

-- E quem pediu foi avisado da decisão, no sino de quem ainda não é da banca.
select results_eq(
  $$select n.type, n.scope::text from public.notifications n
    where n.recipient_profile_id='c2000000-0000-4000-8000-00000000000b'
      and n.type='firm_join_decided'$$,
  $$values ('firm_join_decided'::text,'client'::text)$$,
  'quem pediu e avisado, e no sino do CLIENTE (ainda nao e da banca)');

-- ---------------------------------------------------------------------------
-- 4. Membro ativo não entra de novo; desativado reentra com o papel do link
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','c2000000-0000-4000-8000-00000000000a', true);
set local role authenticated;

create temp table segundo_link as
select * from public.criar_link_de_convite(
  'cf200000-0000-4000-8000-000000000001','intern');
grant select on segundo_link to public;

reset role;

select set_config('request.jwt.claim.sub','c2000000-0000-4000-8000-00000000000b', true);
set local role authenticated;

select throws_ok(
  format($$select public.solicitar_entrada_por_link(%L)$$,
         (select token from segundo_link)),
  'Already a member of this firm',
  'quem ja esta na equipe nao consome link');

reset role;

-- Desativa a secretária; ela volta pelo link novo, como estagiária.
update public.law_firm_members
set status='disabled'
where profile_id='c2000000-0000-4000-8000-00000000000b';

select set_config('request.jwt.claim.sub','c2000000-0000-4000-8000-00000000000b', true);
set local role authenticated;

select lives_ok(
  format($$select public.solicitar_entrada_por_link(%L)$$,
         (select token from segundo_link)),
  'ex-membro desativado pede de novo por link novo');

reset role;

create temp table pedido_da_volta as
select r.id from public.law_firm_join_requests r
where r.requester_id='c2000000-0000-4000-8000-00000000000b' and r.status='pending';
grant select on pedido_da_volta to public;

select set_config('request.jwt.claim.sub','c2000000-0000-4000-8000-00000000000a', true);
set local role authenticated;

select is(
  public.decidir_entrada_no_escritorio((select id from pedido_da_volta), true),
  'approved',
  'a gestora aprova a volta');

reset role;

select results_eq(
  $$select m.roles, m.status from public.law_firm_members m
    where m.profile_id='c2000000-0000-4000-8000-00000000000b'$$,
  $$values (array['intern']::text[], 'active'::public.law_firm_member_status)$$,
  'e volta com o papel DO LINK, nao com o que tinha antes');

-- ---------------------------------------------------------------------------
-- 5. Expiração e revogação
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','c2000000-0000-4000-8000-00000000000a', true);
set local role authenticated;

create temp table link_velho as
select * from public.criar_link_de_convite(
  'cf200000-0000-4000-8000-000000000001','secretary');
grant select on link_velho to public;
create temp table link_revogado as
select * from public.criar_link_de_convite(
  'cf200000-0000-4000-8000-000000000001','secretary');
grant select on link_revogado to public;

reset role;

update public.law_firm_invite_links
set expires_at = now() - interval '1 minute'
where token_hash = encode(extensions.digest((select token from link_velho),'sha256'),'hex');

set local role anon;
select results_eq(
  format($$select situacao from public.espiar_link_de_convite(%L)$$,
         (select token from link_velho)),
  $$values ('expirado'::text)$$,
  'a pagina diz expirado antes de a pessoa criar conta a toa');
reset role;

select set_config('request.jwt.claim.sub','c2000000-0000-4000-8000-00000000000c', true);
set local role authenticated;

select throws_ok(
  format($$select public.solicitar_entrada_por_link(%L)$$,
         (select token from link_velho)),
  'Invite link expired',
  'e o pedido recusa o vencido');

reset role;

-- Revogar: só gestor, e depois ninguém entra.
select set_config('request.jwt.claim.sub','c2000000-0000-4000-8000-00000000000d', true);
set local role authenticated;

select throws_ok(
  format($$select public.revogar_link_de_convite(%L::uuid)$$,
         (select id from link_revogado)),
  'Only active office owners and admins can revoke',
  'quem nao e gestor nao revoga');

reset role;

select set_config('request.jwt.claim.sub','c2000000-0000-4000-8000-00000000000a', true);
set local role authenticated;

select lives_ok(
  format($$select public.revogar_link_de_convite(%L::uuid)$$,
         (select id from link_revogado)),
  'a gestora revoga o link que vazou');

reset role;

select set_config('request.jwt.claim.sub','c2000000-0000-4000-8000-00000000000c', true);
set local role authenticated;

select throws_ok(
  format($$select public.solicitar_entrada_por_link(%L)$$,
         (select token from link_revogado)),
  'Invite link was revoked',
  'e o revogado nao serve mais nem para pedir');

reset role;

-- ---------------------------------------------------------------------------
-- 6. A listagem: só os abertos, e sem token
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','c2000000-0000-4000-8000-00000000000a', true);
set local role authenticated;

-- Restou aberto só o... nenhum: o 1º foi usado, o 2º usado, o 3º venceu, o
-- 4º revogado. Cria um limpo para a listagem ter o que listar.
create temp table link_aberto as
select * from public.criar_link_de_convite(
  'cf200000-0000-4000-8000-000000000001','intern');
grant select on link_aberto to public;

select is(
  (select count(*)::int from public.listar_links_de_convite(
     'cf200000-0000-4000-8000-000000000001')),
  1,
  'a listagem traz SO os links em aberto');

reset role;

-- ---------------------------------------------------------------------------
-- 7. Escritório congelado não inclui ninguém, nem pela porta nova
-- ---------------------------------------------------------------------------
insert into public.law_firm_license_subscriptions
  (id, owner_profile_id, law_firm_id, plan_code, billing_cycle, status)
values ('ca200000-0000-4000-8000-000000000001',
        'c2000000-0000-4000-8000-00000000000a',
        'cf200000-0000-4000-8000-000000000001','essencial','monthly','past_due');

select set_config('request.jwt.claim.sub','c2000000-0000-4000-8000-00000000000a', true);
set local role authenticated;

select throws_ok(
  $$select * from public.criar_link_de_convite(
      'cf200000-0000-4000-8000-000000000001','secretary')$$,
  'Subscription is not active',
  'assinatura parada: nao se CRIA link');

select throws_ok(
  format($$select public.solicitar_entrada_por_link(%L)$$,
         (select token from link_aberto)),
  'Already a member of this firm',
  'controle: a propria gestora esbarra primeiro em ja-ser-membro');

reset role;

-- O link criado ANTES do congelamento também não serve: a janela entre criar
-- e pedir não contorna a regra.
select set_config('request.jwt.claim.sub','c2000000-0000-4000-8000-00000000000c', true);
set local role authenticated;

select throws_ok(
  format($$select public.solicitar_entrada_por_link(%L)$$,
         (select token from link_aberto)),
  'Subscription is not active',
  'assinatura parada: link antigo tambem nao serve para PEDIR');

reset role;

-- ---------------------------------------------------------------------------
-- 8. A tabela em si está trancada
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','c2000000-0000-4000-8000-00000000000a', true);
set local role authenticated;

select throws_ok(
  $$select count(*) from public.law_firm_invite_links$$,
  '42501',
  null,
  'nem a gestora le a tabela crua: tudo passa pelas funcoes');

reset role;

select * from finish();
rollback;
