-- A operação do escritório não é vitrine.
--
-- fetch_law_firm_operation_metrics devolvia volume de leads, casos ativos e
-- tamanho da equipe para qualquer conta autenticada que soubesse o id da
-- banca, e o id aparece na busca. Este arquivo trava quem lê: membro ativo
-- sim, estranho não, ex-membro desativado não.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(6);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('ea000000-0000-4000-8000-00000000000a','authenticated','authenticated','socio@met.test','',now(),'{}','{"full_name":"Socio"}',now(),now()),
  ('ea000000-0000-4000-8000-00000000000b','authenticated','authenticated','secretaria@met.test','',now(),'{}','{"full_name":"Secretaria"}',now(),now()),
  ('ea000000-0000-4000-8000-00000000000c','authenticated','authenticated','curioso@fora.test','',now(),'{}','{"full_name":"Concorrente"}',now(),now()),
  ('ea000000-0000-4000-8000-00000000000d','authenticated','authenticated','exmembro@met.test','',now(),'{}','{"full_name":"Ex Membro"}',now(),now()),
  ('ea000000-0000-4000-8000-00000000000e','authenticated','authenticated','cliente@met.test','',now(),'{}','{"full_name":"Cliente"}',now(),now());

insert into public.law_firms (id, name, initials, specialty, is_active, cep, oab_state)
values ('ef000000-0000-4000-8000-000000000001','Banca Medida','BM','Direito Cível',true,'90540140','RS');

insert into public.law_firm_members (law_firm_id, profile_id, roles, member_role, role, status)
values
  ('ef000000-0000-4000-8000-000000000001','ea000000-0000-4000-8000-00000000000a',
   array['owner'],'owner','owner','active'),
  ('ef000000-0000-4000-8000-000000000001','ea000000-0000-4000-8000-00000000000b',
   array['secretary'],'secretary','secretary','active'),
  ('ef000000-0000-4000-8000-000000000001','ea000000-0000-4000-8000-00000000000d',
   array['secretary'],'secretary','secretary','disabled');

insert into public.conversations (id, type, law_firm_id, client_id, title)
values
  ('ec000000-0000-4000-8000-000000000001','client_firm','ef000000-0000-4000-8000-000000000001',
   'ea000000-0000-4000-8000-00000000000e','Atendimento 1'),
  ('ec000000-0000-4000-8000-000000000002','client_firm','ef000000-0000-4000-8000-000000000001',
   'ea000000-0000-4000-8000-00000000000e','Atendimento 2');

-- ---------------------------------------------------------------------------
-- 1. Quem é da casa lê
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','ea000000-0000-4000-8000-00000000000a', true);
set local role authenticated;

select results_eq(
  $$select client_messages, team_members
    from public.fetch_law_firm_operation_metrics('ef000000-0000-4000-8000-000000000001')$$,
  $$values (2, 2)$$,
  'o socio ve o retrato da propria operacao'
);

-- Secretária e estagiário abrem a mesma Visão Geral: a régua é membro ativo,
-- não gestor.
select set_config('request.jwt.claim.sub','ea000000-0000-4000-8000-00000000000b', true);
select is(
  (select client_messages
   from public.fetch_law_firm_operation_metrics('ef000000-0000-4000-8000-000000000001')),
  2,
  'a secretaria tambem, porque a Visao Geral e a tela de quem trabalha ali'
);

-- ---------------------------------------------------------------------------
-- 2. Quem não é, não lê
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','ea000000-0000-4000-8000-00000000000c', true);

select is(
  (select count(*)::int
   from public.fetch_law_firm_operation_metrics('ef000000-0000-4000-8000-000000000001')),
  0,
  'quem nao tem vinculo nao recebe LINHA nenhuma'
);

-- Zero linhas, e não uma linha de zeros: zero seria uma resposta, e diria
-- "essa banca nao tem movimento".
select is(
  (select client_messages
   from public.fetch_law_firm_operation_metrics('ef000000-0000-4000-8000-000000000001')),
  null,
  'e nao recebe uma linha de zeros, que seria uma resposta falsa'
);

select set_config('request.jwt.claim.sub','ea000000-0000-4000-8000-00000000000d', true);
select is(
  (select count(*)::int
   from public.fetch_law_firm_operation_metrics('ef000000-0000-4000-8000-000000000001')),
  0,
  'ex-membro desativado tambem nao le mais'
);

reset role;

-- E anon nem chega perto.
select is(
  (select count(*)::int from information_schema.role_routine_grants
   where routine_schema='public'
     and routine_name='fetch_law_firm_operation_metrics'
     and grantee='anon'),
  0,
  'anon nao tem execute na funcao'
);

select * from finish();
rollback;
