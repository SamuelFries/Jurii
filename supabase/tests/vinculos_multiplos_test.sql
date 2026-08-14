-- Vínculos múltiplos: os dez cenários, no nível do banco.
--
-- O banco é onde a regra tem que morar, porque é o único lugar que o
-- frontend não contorna. Cada cenário aqui roda com `set local role
-- authenticated` e o sub da pessoa, que é como uma requisição real chega.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(24);

-- ---------------------------------------------------------------------------
-- Cenário
-- ---------------------------------------------------------------------------
-- Joao:  Silva (RS) sócio  |  Costa (RS) advogado  |  Almeida (SP) admin
-- Maria: Silva (RS) secretária
-- Pedro: nenhum vínculo
insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('b0000000-0000-0000-0000-00000000000a','authenticated','authenticated','joao@t.test','',now(),'{}','{"full_name":"Joao"}',now(),now()),
  ('b0000000-0000-0000-0000-00000000000b','authenticated','authenticated','maria@t.test','',now(),'{}','{"full_name":"Maria"}',now(),now()),
  ('b0000000-0000-0000-0000-00000000000c','authenticated','authenticated','pedro@t.test','',now(),'{}','{"full_name":"Pedro"}',now(),now());

insert into public.law_firms (id, name, initials, specialty, is_active, cep, oab_state)
values
  ('bf000000-0000-0000-0000-000000000001','Silva Advogados','SA','Direito Civel',true,'90540140','RS'),
  ('bf000000-0000-0000-0000-000000000002','Costa Advogados','CA','Direito Civel',true,'90010000','RS'),
  ('bf000000-0000-0000-0000-000000000003','Almeida Advogados','AA','Direito Civel',true,'01310100','SP'),
  -- Sem CEP e sem Seccional: o cadastro antigo, de antes de a coluna existir.
  ('bf000000-0000-0000-0000-000000000004','Antigo Advogados','AN','Direito Civel',true,null,null);

insert into public.law_firm_members (law_firm_id, profile_id, roles, member_role, role, status, joined_at)
values
  ('bf000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-00000000000a',array['owner'],'owner','owner','active', now() - interval '30 days'),
  ('bf000000-0000-0000-0000-000000000002','b0000000-0000-0000-0000-00000000000a',array['lawyer'],'lawyer','lawyer','active', now() - interval '20 days'),
  ('bf000000-0000-0000-0000-000000000003','b0000000-0000-0000-0000-00000000000a',array['admin'],'admin','admin','active', now() - interval '10 days'),
  ('bf000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-00000000000b',array['secretary'],'secretary','secretary','active', now());

-- ---------------------------------------------------------------------------
-- 1, 2, 3, 7. Vários vínculos, cargos diferentes, cargo no VÍNCULO
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','b0000000-0000-0000-0000-00000000000a', true);
set local role authenticated;

select is(
  (select count(*)::int from public.fetch_law_firm_memberships()),
  3,
  'Joao ve os TRES vinculos dele');

select results_eq(
  $$select law_firm_name, primary_role
      from public.fetch_law_firm_memberships()$$,
  $$values ('Silva Advogados','owner'),
           ('Costa Advogados','lawyer'),
           ('Almeida Advogados','admin')$$,
  'cada vinculo traz o SEU cargo, na ordem estavel de entrada');

-- O cargo pertence ao vinculo: a mesma pessoa e gestora numa banca e nao na
-- outra, e quem responde isso e o banco, nao a tela.
select is(
  public.is_active_law_firm_manager('bf000000-0000-0000-0000-000000000001'),
  true,
  'Joao e gestor no escritorio onde e socio');

select is(
  public.is_active_law_firm_manager('bf000000-0000-0000-0000-000000000002'),
  false,
  'e NAO e gestor no escritorio onde e advogado');

select is(
  public.has_law_firm_role('bf000000-0000-0000-0000-000000000003', 'admin'),
  true,
  'e admin no terceiro, sem que isso vaze para os outros');

reset role;

-- ---------------------------------------------------------------------------
-- 1 (bis). Uma conta só: os vínculos são da MESMA identidade
-- ---------------------------------------------------------------------------
select is(
  (select count(distinct profile_id)::int
     from public.law_firm_members
    where profile_id = 'b0000000-0000-0000-0000-00000000000a'),
  1,
  'tres vinculos, uma conta so');

-- ---------------------------------------------------------------------------
-- 5. Escritório sem vínculo não é alcançável
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','b0000000-0000-0000-0000-00000000000c', true);
set local role authenticated;

select is(
  (select count(*)::int from public.fetch_law_firm_memberships()),
  0,
  'Pedro, sem vinculo, nao ve escritorio nenhum');

-- 10. Sem vínculo válido: nada de gestor, nada de papel, em lugar nenhum.
select is(
  public.is_active_law_firm_manager('bf000000-0000-0000-0000-000000000001'),
  false,
  'Pedro nao vira gestor por pedir');

select is(
  (select count(*)::int from public.fetch_law_firm_cases('bf000000-0000-0000-0000-000000000001')),
  0,
  'e nao le os casos de escritorio onde nao tem vinculo');

reset role;

-- ---------------------------------------------------------------------------
-- 6. O cargo do colega NÃO é o meu
-- ---------------------------------------------------------------------------
-- O defeito que isto trava: a consulta antiga do webapp era
-- `select ... where status='active' order by joined_at limit 1`, SEM filtro de
-- profile_id, confiando na RLS. Mas a policy entrega as linhas dos colegas
-- (ela existe para montar a equipe), entao a secretaria recebia a linha do
-- socio e a tela lhe dava poderes de socio.
select set_config('request.jwt.claim.sub','b0000000-0000-0000-0000-00000000000b', true);
set local role authenticated;

select is(
  (select primary_role from public.fetch_law_firm_memberships()),
  'secretary',
  'Maria e secretaria, e a RPC nao devolve o cargo do socio');

select is(
  public.is_active_law_firm_manager('bf000000-0000-0000-0000-000000000001'),
  false,
  'secretaria nao e gestora, por mais antigo que seja o socio');

-- A policy REALMENTE entrega a linha do colega: e por isso que a leitura
-- precisa da RPC, e nao de um select solto.
select is(
  (select count(*)::int from public.law_firm_members
    where law_firm_id = 'bf000000-0000-0000-0000-000000000001'),
  2,
  'a policy entrega as linhas da equipe, como sempre entregou');

reset role;

-- ---------------------------------------------------------------------------
-- 8. Sócio em dois escritórios da MESMA Seccional: barrado
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','b0000000-0000-0000-0000-00000000000a', true);

-- Promover Joao a socio no Costa (RS), sendo ja socio no Silva (RS).
select throws_ok(
  $$update public.law_firm_members
       set roles = array['owner'], member_role = 'owner', role = 'owner'
     where law_firm_id = 'bf000000-0000-0000-0000-000000000002'
       and profile_id = 'b0000000-0000-0000-0000-00000000000a'$$,
  '23514',
  'Already an owner in the RS section (Silva Advogados)',
  'nao vira socio de duas bancas na mesma Seccional');

-- Nem por INSERT direto, que e a outra porta.
select throws_ok(
  $$insert into public.law_firm_members (law_firm_id, profile_id, roles, member_role, role, status)
    values ('bf000000-0000-0000-0000-000000000002','b0000000-0000-0000-0000-00000000000a',
            array['owner'],'owner','owner','active')$$,
  '23514',
  'Already an owner in the RS section (Silva Advogados)',
  'nem inserindo um vinculo de socio novo');

-- 7. Mas socio numa e advogado noutra continua valendo, que e o caso legitimo.
select is(
  (select primary_role from public.fetch_law_firm_memberships()
    where law_firm_id = 'bf000000-0000-0000-0000-000000000002'),
  'lawyer',
  'socio numa banca e advogado noutra continua de pe');

-- 13. Seccional DIFERENTE pode: a regra e por seccional, nao por quantidade.
select lives_ok(
  $$update public.law_firm_members
       set roles = array['owner'], member_role = 'owner', role = 'owner'
     where law_firm_id = 'bf000000-0000-0000-0000-000000000003'
       and profile_id = 'b0000000-0000-0000-0000-00000000000a'$$,
  'socio no RS e socio no SP e permitido');

-- Escritorio sem Seccional declarada nao entra na regra: cadastro antigo nao
-- pode travar a operacao por causa de um campo que nao existia.
select lives_ok(
  $$insert into public.law_firm_members (law_firm_id, profile_id, roles, member_role, role, status)
    values ('bf000000-0000-0000-0000-000000000004','b0000000-0000-0000-0000-00000000000a',
            array['owner'],'owner','owner','active')$$,
  'escritorio sem Seccional declarada nao e barrado');

-- ---------------------------------------------------------------------------
-- 9. Vínculo desativado some da lista
-- ---------------------------------------------------------------------------
set local role authenticated;
select is(
  (select count(*)::int from public.fetch_law_firm_memberships()
    where law_firm_id = 'bf000000-0000-0000-0000-000000000002'),
  1,
  'o vinculo com o Costa esta na lista antes de desativar');
reset role;

update public.law_firm_members
set status = 'disabled'
where law_firm_id = 'bf000000-0000-0000-0000-000000000002'
  and profile_id = 'b0000000-0000-0000-0000-00000000000a';

set local role authenticated;
select is(
  (select count(*)::int from public.fetch_law_firm_memberships()
    where law_firm_id = 'bf000000-0000-0000-0000-000000000002'),
  0,
  'desativado SAI da lista, entao o cliente nunca oferece um contexto morto');

select is(
  public.is_active_law_firm_manager('bf000000-0000-0000-0000-000000000002'),
  false,
  'e desativado nao carrega permissao nenhuma');
reset role;

-- ---------------------------------------------------------------------------
-- As métricas do painel são DESTE escritório
-- ---------------------------------------------------------------------------
-- O CTE antigo contava qualquer caso cujo advogado responsavel fosse membro
-- desta banca, sem exigir que o CASO fosse desta banca. Advogado em dois
-- lugares fazia os casos de um contarem no painel do outro.
-- Joao precisa de lawyer_profile para poder ser responsavel por caso, e o
-- caso precisa TER responsavel: o ramo defeituoso so vazava ATRAVES do
-- responsavel compartilhado. Sem isso o teste passa pelo motivo errado.
insert into public.lawyer_profiles (id, oab_number, oab_state, primary_area, is_available, approved_at)
values ('b0000000-0000-0000-0000-00000000000a','880011','RS','Direito Civel',true,now());

insert into public.legal_cases (law_firm_id, client_id, assigned_lawyer_id, title, area, status)
values
  ('bf000000-0000-0000-0000-000000000002','b0000000-0000-0000-0000-00000000000c',
   'b0000000-0000-0000-0000-00000000000a','Caso do Costa','Direito Civel','open');

update public.law_firm_members
set status = 'active'
where law_firm_id = 'bf000000-0000-0000-0000-000000000002'
  and profile_id = 'b0000000-0000-0000-0000-00000000000a';

select set_config('request.jwt.claim.sub','b0000000-0000-0000-0000-00000000000a', true);
set local role authenticated;

select is(
  (select active_cases from public.fetch_law_firm_operation_metrics('bf000000-0000-0000-0000-000000000001')),
  0,
  'o caso do Costa NAO conta no painel do Silva');

select is(
  (select active_cases from public.fetch_law_firm_operation_metrics('bf000000-0000-0000-0000-000000000002')),
  1,
  'e conta no painel do Costa, que e a casa dele');

reset role;

-- ---------------------------------------------------------------------------
-- A UF do CEP alimenta o campo, e nao inventa quando nao sabe
-- ---------------------------------------------------------------------------
select is(public.uf_do_cep('90540-140'), 'RS'::char(2), 'CEP de Porto Alegre e RS');
select is(public.uf_do_cep('nao e cep'), null, 'CEP invalido nao vira chute');

select * from finish();
rollback;
