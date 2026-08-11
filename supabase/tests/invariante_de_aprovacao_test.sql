-- O PORTAO DE APROVACAO do perfil publico, e a corrente que o sustenta.
--
-- POR QUE ESTE TESTE EXISTE. Varias funcoes SECURITY DEFINER entregam
-- dados de lawyer_profiles a terceiros (a descoberta, os favoritos, o
-- perfil publico, a lista da equipe). Hoje elas nao precisam checar
-- aprovacao porque perfil nao aprovado NAO EXISTE e nao ha como criar um.
-- O dia em que esse elo cair, varias passam a vazar de uma vez, e ninguem
-- vai ligar uma coisa a outra.
--
-- ESTE ARQUIVO JA NASCEU ERRADO UMA VEZ, e o que ele evita agora e o que
-- ele mesmo fez:
--
--   1. contava linhas de lawyer_profiles para provar a invariante. Roda
--      contra o banco LOCAL, que tem zero linhas: era 0 = 0 para sempre,
--      verde acontecesse o que acontecesse. Agora a fixture e CONSTRUIDA
--      aqui dentro e o portao e exercitado contra ela;
--   2. filtrava schema com join em pg_namespace, e o planejador aplicava
--      pg_get_functiondef antes do join: "ERROR 42809: array_agg is an
--      aggregate function". Quatro das seis assercoes nunca executavam.
--      Agora usa pronamespace = 'public'::regnamespace;
--   3. olhava so policy de INSERT, e policy escrita "for all" (o
--      idiomatismo do proprio Supabase) tem cmd = 'ALL' e passaria batido.
--      Agora pergunta ao oraculo de privilegio, que e o efeito.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(7);

-- ---------------------------------------------------------------------------
-- A CORRENTE, testada pelo EFEITO e nao pela implementacao
-- ---------------------------------------------------------------------------

-- Elo 1: authenticated nao cria perfil. Duas trancas independentes (grant e
-- policy); has_table_privilege responde pelo efeito das duas, e pega tanto
-- "grant all on all tables" quanto policy "for all".
select ok(
  not has_table_privilege('authenticated', 'public.lawyer_profiles', 'INSERT'),
  'authenticated nao INSERE em lawyer_profiles');

select ok(
  not has_column_privilege(
    'authenticated', 'public.lawyer_profiles', 'approved_at', 'UPDATE'),
  'authenticated nao ATUALIZA approved_at');

-- Elo 2: so a aprovacao cria perfil. Sem join em pg_namespace (ver nota 2).
select is(
  (select count(*)::int
   from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.prokind = 'f'
     and pg_get_functiondef(p.oid) ilike '%insert into public.lawyer_profiles%'
     and p.proname <> 'approve_lawyer_verification'),
  0,
  'so approve_lawyer_verification cria perfil de advogado');

-- Elo 3: e ela cria APROVADO. A assercao anterior isentava justamente a
-- unica funcao que insere; o jeito mais plausivel de a invariante morrer e
-- uma fila de pendentes nascer DENTRO dela.
select ok(
  (select pg_get_functiondef(p.oid) ilike '%insert into public.lawyer_profiles%approved_at%'
   from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname = 'approve_lawyer_verification'
   limit 1),
  'approve_lawyer_verification grava approved_at ao criar o perfil');

-- Elo 4: SO a revogacao anula approved_at.
--
-- Ate a 20260827120000 nenhuma funcao anulava, e este teste exigia zero.
-- A revogacao passou a anular DE PROPOSITO (revogar tem que tirar o
-- advogado do ar), entao approved_at nulo agora TEM significado: nunca
-- aprovado ou revogado. O que continua proibido e qualquer OUTRA funcao
-- mexer nisso.
select is(
  (select coalesce(string_agg(p.proname, ', ' order by p.proname), '')
   from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.prokind = 'f'
     and pg_get_functiondef(p.oid) ~* 'approved_at\s*=\s*null'),
  'reject_lawyer_verification',
  'so reject_lawyer_verification anula approved_at');

-- ---------------------------------------------------------------------------
-- O PORTAO, exercitado contra fixture construida aqui: e ele que sobrevive
-- a queda da corrente.
-- ---------------------------------------------------------------------------

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('c1000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'pendente@invariante.test', '', now(), '{}'::jsonb,
   '{"full_name":"Paulo Pendente"}'::jsonb, now(), now()),
  ('c1000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'revogado@invariante.test', '', now(), '{}'::jsonb,
   '{"full_name":"Rita Revogada"}'::jsonb, now(), now()),
  ('c1000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'visitante@invariante.test', '', now(), '{}'::jsonb,
   '{"full_name":"Visitante Comum"}'::jsonb, now(), now());

-- Dois perfis que a corrente diz serem impossiveis, criados aqui como
-- postgres exatamente para provar que o portao nao depende dela.
insert into public.lawyer_profiles
  (id, oab_number, oab_state, primary_area, practice_areas, bio,
   is_available, approved_at)
values
  -- Nunca aprovado: o caso que approved_at pega.
  ('c1000000-0000-0000-0000-000000000001', '990098', 'RS',
   'Direito Cível', array['Direito Cível'], 'Bio do Paulo.', true, null),
  -- APROVADO UM DIA E REVOGADO DEPOIS: approved_at continua preenchido
  -- para sempre (nada o limpa), e so lawyer_status desce. E o caso que um
  -- portao so de approved_at deixaria passar.
  ('c1000000-0000-0000-0000-000000000002', '990097', 'RS',
   'Direito Trabalhista', array['Direito Trabalhista'], 'Bio da Rita.',
   true, now());

update public.profiles set lawyer_status = 'client'
where id = 'c1000000-0000-0000-0000-000000000002';

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub',
  'c1000000-0000-0000-0000-000000000003', true);
set local role authenticated;

select is_empty(
  $$select 1 from public.fetch_lawyer_public_profile(
      'c1000000-0000-0000-0000-000000000001')$$,
  'perfil nunca aprovado nao sai por deep link');

select is_empty(
  $$select 1 from public.fetch_lawyer_public_profile(
      'c1000000-0000-0000-0000-000000000002')$$,
  'advogado REVOGADO nao sai, mesmo com approved_at preenchido para sempre');

reset role;

select * from finish();
rollback;
