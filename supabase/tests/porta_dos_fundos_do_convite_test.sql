-- O convite por link PEDE, e não concede: sem porta dos fundos.
--
-- A migration 20260914120000 trocou o desenho mas deixou a RPC antiga viva e
-- concedida, e quem tinha o token entrava sozinho pela API. Este arquivo
-- trava as duas metades: a função antiga não existe, e o caminho que existe
-- não coloca ninguém na equipe sem decisão de um gestor.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(6);

-- ---------------------------------------------------------------------------
-- 1. A função antiga não voltou
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::int from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'aceitar_link_de_convite'),
  0,
  'aceitar_link_de_convite não existe (concedia entrada sem aprovação)'
);

-- Barreira mais larga: nenhuma função de convite pode ser executável por
-- quem está logado sem passar pela decisão do gestor. Se alguém criar uma
-- "aceitar_convite_v2", este teste cai junto.
select is(
  (select coalesce(string_agg(p.proname, ', ' order by p.proname), '')
   from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and (p.proname like 'aceitar%convite%' or p.proname like 'entrar%escritorio%')
     and exists (
       select 1 from information_schema.role_routine_grants g
       where g.routine_schema = 'public' and g.routine_name = p.proname
         and g.grantee in ('anon', 'authenticated')
     )),
  '',
  'nenhuma função de "aceitar convite" fica executável para quem está logado'
);

-- ---------------------------------------------------------------------------
-- 2. O caminho que existe não entrega a equipe
-- ---------------------------------------------------------------------------
insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('ab000000-0000-4000-8000-00000000000a','authenticated','authenticated','socio@porta.test','',now(),'{}','{"full_name":"Socio Gestor"}',now(),now()),
  ('ab000000-0000-4000-8000-00000000000b','authenticated','authenticated','pediu@porta.test','',now(),'{}','{"full_name":"Quem Recebeu O Link"}',now(),now());

insert into public.law_firms (id, name, initials, specialty, is_active, cep, oab_state)
values ('ac000000-0000-4000-8000-000000000001','Banca da Porta','BP','Direito Cível',true,'90540140','RS');

insert into public.law_firm_members (law_firm_id, profile_id, roles, member_role, role, status)
values ('ac000000-0000-4000-8000-000000000001','ab000000-0000-4000-8000-00000000000a',
        array['owner'],'owner','owner','active');

insert into public.law_firm_license_subscriptions
  (id, owner_profile_id, law_firm_id, plan_code, billing_cycle, status)
values ('ad000000-0000-4000-8000-000000000001','ab000000-0000-4000-8000-00000000000a',
        'ac000000-0000-4000-8000-000000000001','essencial','monthly','active');

select set_config('request.jwt.claim.sub','ab000000-0000-4000-8000-00000000000a', true);
set local role authenticated;

create temp table convite as
select token from public.criar_link_de_convite(
  'ac000000-0000-4000-8000-000000000001', 'secretary');
grant select on convite to public;

-- Quem recebeu o link.
select set_config('request.jwt.claim.sub','ab000000-0000-4000-8000-00000000000b', true);

select isnt(
  public.solicitar_entrada_por_link((select token from convite))::text,
  null,
  'quem recebeu o link consegue PEDIR entrada'
);

reset role;
select is(
  (select count(*)::int from public.law_firm_members
   where law_firm_id = 'ac000000-0000-4000-8000-000000000001'
     and profile_id = 'ab000000-0000-4000-8000-00000000000b'),
  0,
  'e pedir NÃO coloca ninguém na equipe'
);

-- ---------------------------------------------------------------------------
-- 3. Só a decisão do gestor coloca
-- ---------------------------------------------------------------------------
-- O id sai daqui, fora do papel de cliente, de propósito: nem quem decide lê
-- a fila por consulta direta (a leitura é pela RPC listar_pedidos_de_entrada),
-- e é isso que o teste da seção 2 do pedido_de_entrada_test já trava.
create temp table pedido as
select r.id from public.law_firm_join_requests r
where r.law_firm_id = 'ac000000-0000-4000-8000-000000000001';
grant select on pedido to public;

select set_config('request.jwt.claim.sub','ab000000-0000-4000-8000-00000000000a', true);
set local role authenticated;

select is(
  public.decidir_entrada_no_escritorio((select id from pedido), true),
  'approved',
  'o gestor aprova'
);

reset role;
select is(
  (select status from public.law_firm_members
   where law_firm_id = 'ac000000-0000-4000-8000-000000000001'
     and profile_id = 'ab000000-0000-4000-8000-00000000000b'),
  'active',
  'e só então a pessoa entra na equipe'
);

select * from finish();
rollback;
