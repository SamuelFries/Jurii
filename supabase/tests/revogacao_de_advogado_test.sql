-- Revogar advogado tira ele do ar, e re-aprovar devolve.
--
-- O DEFEITO QUE ISTO TRAVA: reject_lawyer_verification cuidava dos papeis
-- de escritorio e esquecia lawyer_profiles, entao o advogado revogado
-- continuava na descoberta e no perfil publico, embora nao desse mais para
-- abrir conversa com ele. Anunciado e inalcancavel.
--
-- O teste percorre o CICLO INTEIRO com as funcoes de verdade (aprovar,
-- revogar, re-aprovar) em vez de montar estado a mao: e a unica forma de
-- pegar as duas pontas discordando.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(9);

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('d1000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'advogada@revogacao.test', '', now(), '{}'::jsonb,
   '{"full_name":"Rita Advogada"}'::jsonb, now(), now()),
  ('d1000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'pausada@revogacao.test', '', now(), '{}'::jsonb,
   '{"full_name":"Paula Pausada"}'::jsonb, now(), now()),
  ('d1000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'cliente@revogacao.test', '', now(), '{}'::jsonb,
   '{"full_name":"Cliente Comum"}'::jsonb, now(), now());

insert into public.lawyer_verifications
  (id, user_id, oab_number, oab_state, practice_area, practice_areas, status)
values
  ('d2000000-0000-0000-0000-000000000001',
   'd1000000-0000-0000-0000-000000000001',
   '880001', 'RS', 'Direito Trabalhista', array['Direito Trabalhista'],
   'pending'),
  ('d2000000-0000-0000-0000-000000000002',
   'd1000000-0000-0000-0000-000000000002',
   '880002', 'RS', 'Direito Cível', array['Direito Cível'], 'pending');

-- ---------------------------------------------------------------------------
-- 1. Aprovar poe no ar
-- ---------------------------------------------------------------------------
select public.approve_lawyer_verification(
  'd2000000-0000-0000-0000-000000000001');

select results_eq(
  $$select approved_at is not null, is_available
    from public.lawyer_profiles
    where id = 'd1000000-0000-0000-0000-000000000001'$$,
  $$values (true, true)$$,
  'aprovar cria o perfil aprovado e disponivel');

select is(
  (select lawyer_status::text from public.profiles
    where id = 'd1000000-0000-0000-0000-000000000001'),
  'approved',
  'aprovar poe lawyer_status em approved');

-- Visivel para um cliente qualquer, pelo perfil publico.
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub',
  'd1000000-0000-0000-0000-000000000003', true);
set local role authenticated;

select isnt_empty(
  $$select 1 from public.fetch_lawyer_public_profile(
      'd1000000-0000-0000-0000-000000000001')$$,
  'aprovada aparece no perfil publico');

select isnt_empty(
  $$select 1 from public.fetch_recommended_lawyers(50, null, 0)
     where id = 'd1000000-0000-0000-0000-000000000001'$$,
  'aprovada aparece na descoberta');

reset role;

-- ---------------------------------------------------------------------------
-- 2. Revogar tira do ar, nas DUAS superficies
-- ---------------------------------------------------------------------------
select public.reject_lawyer_verification(
  'd2000000-0000-0000-0000-000000000001', 'documento invalido');

select results_eq(
  $$select approved_at is null, is_available
    from public.lawyer_profiles
    where id = 'd1000000-0000-0000-0000-000000000001'$$,
  $$values (true, false)$$,
  'revogar anula approved_at e derruba is_available, sem apagar a linha');

set local role authenticated;

select is_empty(
  $$select 1 from public.fetch_lawyer_public_profile(
      'd1000000-0000-0000-0000-000000000001')$$,
  'revogada some do perfil publico');

select is_empty(
  $$select 1 from public.fetch_recommended_lawyers(50, null, 0)
     where id = 'd1000000-0000-0000-0000-000000000001'$$,
  'revogada some da DESCOBERTA, que e o que o defeito deixava aberto');

reset role;

-- ---------------------------------------------------------------------------
-- 3. Re-aprovar devolve, e nao atropela quem se pausou sozinho
-- ---------------------------------------------------------------------------
select public.approve_lawyer_verification(
  'd2000000-0000-0000-0000-000000000001');

select results_eq(
  $$select approved_at is not null, is_available
    from public.lawyer_profiles
    where id = 'd1000000-0000-0000-0000-000000000001'$$,
  $$values (true, true)$$,
  're-aprovar devolve a advogada ao ar');

-- Paula aprova, se pausa por conta propria, e tem uma verificacao NOVA
-- aprovada: a pausa dela tem que sobreviver.
select public.approve_lawyer_verification(
  'd2000000-0000-0000-0000-000000000002');

update public.lawyer_profiles set is_available = false
where id = 'd1000000-0000-0000-0000-000000000002';

select public.approve_lawyer_verification(
  'd2000000-0000-0000-0000-000000000002');

select is(
  (select is_available from public.lawyer_profiles
    where id = 'd1000000-0000-0000-0000-000000000002'),
  false,
  'aprovar de novo NAO desfaz a pausa voluntaria do advogado');

select * from finish();
rollback;
