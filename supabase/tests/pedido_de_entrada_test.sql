-- O link pede em vez de conceder.
--
-- O link autorizava um PAPEL e nunca verificou uma IDENTIDADE: quem abrisse
-- primeiro entrava. E membro novo lê TODA conversa com cliente da banca
-- (can_access_conversation não filtra papel nem corta por data), então link
-- encaminhado era estranho lendo correspondência sigilosa.
--
-- Agora clicar CONSOME o link e cria um pedido; quem decide vê quem é.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(29);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('e5000000-0000-4000-8000-00000000000a','authenticated','authenticated','socia@pedido.test','',now(),'{}','{"full_name":"Socia Gestora"}',now(),now()),
  ('e5000000-0000-4000-8000-00000000000b','authenticated','authenticated','admin@pedido.test','',now(),'{}','{"full_name":"Admin Segundo"}',now(),now()),
  ('e5000000-0000-4000-8000-00000000000c','authenticated','authenticated','sec@pedido.test','',now(),'{}','{"full_name":"Secretaria Certa"}',now(),now()),
  ('e5000000-0000-4000-8000-00000000000d','authenticated','authenticated','estranho@pedido.test','',now(),'{}','{"full_name":"Estranho Do Grupo"}',now(),now()),
  ('e5000000-0000-4000-8000-00000000000e','authenticated','authenticated','tardia@pedido.test','',now(),'{}','{"full_name":"Candidata Tardia"}',now(),now());

update public.profiles set cpf = '24971563792'
where id = 'e5000000-0000-4000-8000-00000000000c';

insert into public.law_firms (id, name, initials, specialty, is_active, cep, oab_state)
values ('ef500000-0000-4000-8000-000000000001','Banca do Pedido','BP','Direito Cível',true,'90540140','RS');

insert into public.law_firm_members (law_firm_id, profile_id, roles, member_role, role, status)
values
  ('ef500000-0000-4000-8000-000000000001','e5000000-0000-4000-8000-00000000000a',array['owner'],'owner','owner','active'),
  ('ef500000-0000-4000-8000-000000000001','e5000000-0000-4000-8000-00000000000b',array['admin'],'admin','admin','active');

-- ---------------------------------------------------------------------------
-- 1. Clicar o link cria PEDIDO e consome o link
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','e5000000-0000-4000-8000-00000000000a', true);
set local role authenticated;
create temp table link1 as
select * from public.criar_link_de_convite('ef500000-0000-4000-8000-000000000001','secretary');
grant select on link1 to public;
reset role;

select set_config('request.jwt.claim.sub','e5000000-0000-4000-8000-00000000000c', true);
set local role authenticated;

create temp table pedido1 as
select public.solicitar_entrada_por_link((select token from link1)) as id;
grant select on pedido1 to public;

select ok((select id from pedido1) is not null, 'clicar o link cria um pedido');
reset role;

select is(
  (select count(*)::int from public.law_firm_members
   where law_firm_id='ef500000-0000-4000-8000-000000000001'),
  2,
  'e NINGUEM virou membro clicando: a banca segue com socia e admin');

select ok(
  (select used_at is not null from public.law_firm_invite_links
   where id = (select id from link1)),
  'o link foi CONSUMIDO no clique, e nao no aceite');

-- Segunda pessoa com o mesmo link nao pede.
select set_config('request.jwt.claim.sub','e5000000-0000-4000-8000-00000000000d', true);
set local role authenticated;
select throws_ok(
  format($$select public.solicitar_entrada_por_link(%L)$$, (select token from link1)),
  'Invite link already used',
  'link consumido nao aceita um segundo pedido');
reset role;

-- ---------------------------------------------------------------------------
-- 2. Quem decide foi avisado, no sino do ESCRITORIO
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::int from public.notifications
   where type='firm_join_requested' and scope='firm'),
  2,
  'os DOIS gestores foram avisados, no escopo firm');

select is(
  (select count(*)::int from public.notifications
   where type='firm_join_requested'
     and recipient_profile_id='e5000000-0000-4000-8000-00000000000c'),
  0,
  'e quem pediu nao recebe o aviso de gestao');

-- ---------------------------------------------------------------------------
-- 3. A listagem: quem e a pessoa
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','e5000000-0000-4000-8000-00000000000a', true);
set local role authenticated;

select results_eq(
  $$select requester_name, requester_email, cpf_confirmado, member_role
    from public.listar_pedidos_de_entrada('ef500000-0000-4000-8000-000000000001')$$,
  $$values ('Secretaria Certa'::text,'sec@pedido.test'::text,true,'secretary'::text)$$,
  'quem decide ve nome, e-mail e se o CPF esta confirmado');

reset role;

select set_config('request.jwt.claim.sub','e5000000-0000-4000-8000-00000000000d', true);
set local role authenticated;
select throws_ok(
  $$select * from public.listar_pedidos_de_entrada('ef500000-0000-4000-8000-000000000001')$$,
  'Only active office owners and admins can list requests',
  'quem nao e gestor nao lista pedidos');
select throws_ok(
  format($$select public.decidir_entrada_no_escritorio(%L::uuid, true)$$,
         (select id from pedido1)),
  'Only active office owners and admins can decide',
  'e nao decide');
reset role;

-- ---------------------------------------------------------------------------
-- 4. Aprovar
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','e5000000-0000-4000-8000-00000000000a', true);
set local role authenticated;

select is(
  (select public.decidir_entrada_no_escritorio((select id from pedido1), true)),
  'approved',
  'a socia aprova');

reset role;

select results_eq(
  $$select m.roles, m.status from public.law_firm_members m
    where m.law_firm_id='ef500000-0000-4000-8000-000000000001'
      and m.profile_id='e5000000-0000-4000-8000-00000000000c'$$,
  $$values (array['secretary']::text[], 'active'::public.law_firm_member_status)$$,
  'e SO agora a pessoa vira membro, com o papel do link');

-- QUEM PEDIU precisa saber, e le pelo sino que ela tem (cliente).
select results_eq(
  $$select type, scope::text from public.notifications
    where recipient_profile_id='e5000000-0000-4000-8000-00000000000c'
      and type='firm_join_decided'$$,
  $$values ('firm_join_decided'::text,'client'::text)$$,
  'quem pediu e avisado, no unico sino que ela tinha antes de entrar');

-- O OUTRO gestor soube quem decidiu; quem decidiu nao recebe aviso de si.
select is(
  (select count(*)::int from public.notifications
   where type='firm_join_decided_admin'
     and recipient_profile_id='e5000000-0000-4000-8000-00000000000b'),
  1,
  'o outro gestor soube da decisao');

select is(
  (select count(*)::int from public.notifications
   where type='firm_join_decided_admin'
     and recipient_profile_id='e5000000-0000-4000-8000-00000000000a'),
  0,
  'e quem decidiu nao recebe aviso da propria decisao');

select is(
  (select count(*)::int from public.listar_pedidos_de_entrada(
     'ef500000-0000-4000-8000-000000000001')),
  0,
  'o pedido decidido sai da lista de pendentes')
from (select set_config('request.jwt.claim.sub','e5000000-0000-4000-8000-00000000000a', true)) _;

-- ---------------------------------------------------------------------------
-- 5. A CORRIDA: dois gestores, uma decisao
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','e5000000-0000-4000-8000-00000000000a', true);
set local role authenticated;
create temp table link2 as
select * from public.criar_link_de_convite('ef500000-0000-4000-8000-000000000001','intern');
grant select on link2 to public;
reset role;

select set_config('request.jwt.claim.sub','e5000000-0000-4000-8000-00000000000d', true);
set local role authenticated;
create temp table pedido2 as
select public.solicitar_entrada_por_link((select token from link2)) as id;
grant select on pedido2 to public;
reset role;

select set_config('request.jwt.claim.sub','e5000000-0000-4000-8000-00000000000a', true);
set local role authenticated;
select is(
  (select public.decidir_entrada_no_escritorio((select id from pedido2), false)),
  'rejected',
  'a socia recusa o estranho');
reset role;

-- O segundo gestor chega depois e ouve QUEM decidiu.
select set_config('request.jwt.claim.sub','e5000000-0000-4000-8000-00000000000b', true);
set local role authenticated;
select throws_ok(
  format($$select public.decidir_entrada_no_escritorio(%L::uuid, true)$$,
         (select id from pedido2)),
  'Join request already decided by Socia Gestora',
  'o segundo gestor ouve QUEM decidiu, e nao um erro generico');
reset role;

select is(
  (select count(*)::int from public.law_firm_members
   where law_firm_id='ef500000-0000-4000-8000-000000000001'
     and profile_id='e5000000-0000-4000-8000-00000000000d'),
  0,
  'o recusado NAO entrou');

select results_eq(
  $$select title from public.notifications
    where recipient_profile_id='e5000000-0000-4000-8000-00000000000d'
      and type='firm_join_decided'$$,
  $$values ('Pedido não aprovado'::text)$$,
  'e ele soube da recusa, sem motivo escrito junto');

-- ---------------------------------------------------------------------------
-- 6. Um pedido pendente por pessoa
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','e5000000-0000-4000-8000-00000000000a', true);
set local role authenticated;
create temp table link3 as
select * from public.criar_link_de_convite('ef500000-0000-4000-8000-000000000001','intern');
grant select on link3 to public;
create temp table link4 as
select * from public.criar_link_de_convite('ef500000-0000-4000-8000-000000000001','intern');
grant select on link4 to public;
reset role;

select set_config('request.jwt.claim.sub','e5000000-0000-4000-8000-00000000000d', true);
set local role authenticated;
select lives_ok(
  format($$select public.solicitar_entrada_por_link(%L)$$, (select token from link3)),
  'quem foi recusado pode pedir de novo com um link novo');
select throws_ok(
  format($$select public.solicitar_entrada_por_link(%L)$$, (select token from link4)),
  '23505',
  null,
  'mas nao empilha DOIS pedidos pendentes na mesma banca');
reset role;

-- ---------------------------------------------------------------------------
-- 7. Ja-membro e congelamento
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','e5000000-0000-4000-8000-00000000000a', true);
set local role authenticated;
create temp table link5 as
select * from public.criar_link_de_convite('ef500000-0000-4000-8000-000000000001','secretary');
grant select on link5 to public;
reset role;

select set_config('request.jwt.claim.sub','e5000000-0000-4000-8000-00000000000c', true);
set local role authenticated;
select throws_ok(
  format($$select public.solicitar_entrada_por_link(%L)$$, (select token from link5)),
  'Already a member of this firm',
  'quem ja esta na equipe nao pede entrada');
reset role;

-- Congela a banca e confere as DUAS pontas: pedir e decidir.
insert into public.law_firm_license_subscriptions
  (owner_profile_id, law_firm_id, plan_code, billing_cycle, status)
values ('e5000000-0000-4000-8000-00000000000a',
        'ef500000-0000-4000-8000-000000000001','essencial','monthly','past_due');

-- Quem tenta precisa NAO ser membro, senao esbarra antes em ja-ser-membro
-- (que e a ordem certa das guardas, provada na secao anterior).
select set_config('request.jwt.claim.sub','e5000000-0000-4000-8000-00000000000e', true);
set local role authenticated;
select throws_ok(
  format($$select public.solicitar_entrada_por_link(%L)$$, (select token from link5)),
  'Subscription is not active',
  'assinatura parada: nao se PEDE entrada');
reset role;

-- E o pedido que ja estava pendente (do estranho, seccao 6) nao pode ser
-- aprovado enquanto a banca esta congelada: a janela entre pedir e decidir
-- nao contorna a regra de "nao cresce".
-- O id do pendente e lido como postgres: a tabela e trancada para
-- authenticated, que e exatamente o que o ultimo teste celebra.
create temp table pendente as
select id from public.law_firm_join_requests where status='pending' limit 1;
grant select on pendente to public;

select set_config('request.jwt.claim.sub','e5000000-0000-4000-8000-00000000000a', true);
set local role authenticated;
select throws_ok(
  format($$select public.decidir_entrada_no_escritorio(%L::uuid, true)$$,
         (select id from pendente)),
  'Subscription is not active',
  'e pedido pendente nao vira membro com a assinatura parada');

-- Mas RECUSAR continua possivel: fechar a porta nunca faz a banca crescer.
select is(
  (select public.decidir_entrada_no_escritorio((select id from pendente), false)),
  'rejected',
  'recusar segue possivel com a assinatura parada: recusar nao e crescer');
reset role;

-- ---------------------------------------------------------------------------
-- 8. A tabela esta trancada
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','e5000000-0000-4000-8000-00000000000a', true);
set local role authenticated;
select throws_ok(
  $$select count(*) from public.law_firm_join_requests$$,
  '42501',
  null,
  'nem a socia le a tabela crua: tudo passa pelas funcoes');
reset role;

-- ---------------------------------------------------------------------------
-- 9. A espiada reconhece o dono do pedido
-- ---------------------------------------------------------------------------
--
-- Quem clicou e voltou ao link nao pode ler "ja foi usado": foi ela quem
-- usou, e concluir que perdeu a vaga seria o oposto da verdade.
select set_config('request.jwt.claim.sub','e5000000-0000-4000-8000-00000000000c', true);
set local role authenticated;
select results_eq(
  format($$select situacao from public.espiar_link_de_convite(%L)$$,
         (select token from link1)),
  $$values ('meu_pedido_aprovado'::text)$$,
  'quem teve o pedido aprovado ve isso ao reabrir o link');
reset role;

select set_config('request.jwt.claim.sub','e5000000-0000-4000-8000-00000000000d', true);
set local role authenticated;
select results_eq(
  format($$select situacao from public.espiar_link_de_convite(%L)$$,
         (select token from link2)),
  $$values ('meu_pedido_recusado'::text)$$,
  'e quem foi recusado ve a recusa, nao "ja usado"');
reset role;

-- Para QUALQUER OUTRA PESSOA, inclusive deslogada, a resposta e a de antes.
set local role anon;
select results_eq(
  format($$select situacao from public.espiar_link_de_convite(%L)$$,
         (select token from link1)),
  $$values ('usado'::text)$$,
  'para o resto do mundo o link consumido segue apenas "usado"');
reset role;

select * from finish();
rollback;
