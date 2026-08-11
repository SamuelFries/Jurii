-- fetch_lawyer_public_profile: o perfil por id que o webapp usa.
--
-- O QUE ESTE TESTE TRAVA: a funcao e SECURITY DEFINER (passa por cima da
-- RLS para buscar o nome em profiles), entao o portao mora DENTRO dela.
-- Se alguem afrouxar o where, advogado nao aprovado ou perfil apagado
-- vazam para qualquer autenticado com um uuid na mao.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(6);

-- anon nao executa; authenticated sim.
select is(
  has_function_privilege('anon',
    'public.fetch_lawyer_public_profile(uuid)', 'execute'),
  false,
  'anon nao executa a funcao');
select is(
  has_function_privilege('authenticated',
    'public.fetch_lawyer_public_profile(uuid)', 'execute'),
  true,
  'authenticated executa a funcao');

-- Fixtures: o trigger on_auth_user_created cria profiles a partir de
-- auth.users, entao basta inserir la e complementar lawyer_profiles.
insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('a1000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'aprovado@perfil.test', '', now(), '{}'::jsonb,
   '{"full_name":"Marina Reis Aprovada"}'::jsonb, now(), now()),
  ('a1000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'pendente@perfil.test', '', now(), '{}'::jsonb,
   '{"full_name":"Paulo Pendente"}'::jsonb, now(), now()),
  ('a1000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'visitante@perfil.test', '', now(), '{}'::jsonb,
   '{"full_name":"Visitante Comum"}'::jsonb, now(), now());

insert into public.lawyer_profiles
  (id, oab_number, oab_state, primary_area, practice_areas, bio,
   is_available, approved_at)
values
  ('a1000000-0000-0000-0000-000000000001', '990001', 'RS',
   'Direito Trabalhista', array['Direito Trabalhista'], 'Bio da Marina.',
   true, now()),
  ('a1000000-0000-0000-0000-000000000002', '990002', 'RS',
   'Direito Cível', array['Direito Cível'], 'Bio do Paulo.',
   true, null);

-- Um visitante autenticado qualquer, sem relacao nenhuma com os advogados.
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub',
  'a1000000-0000-0000-0000-000000000003', true);
set local role authenticated;

select results_eq(
  $$select full_name, bio
    from public.fetch_lawyer_public_profile(
      'a1000000-0000-0000-0000-000000000001')$$,
  $$values ('Marina Reis Aprovada', 'Bio da Marina.')$$,
  'aprovado e disponivel aparece com o NOME, que so sai por security definer');

select is_empty(
  $$select 1 from public.fetch_lawyer_public_profile(
      'a1000000-0000-0000-0000-000000000002')$$,
  'advogado NAO aprovado nao vaza, nem com o uuid na mao');

reset role;
update public.lawyer_profiles set is_available = false
where id = 'a1000000-0000-0000-0000-000000000001';
set local role authenticated;

select is_empty(
  $$select 1 from public.fetch_lawyer_public_profile(
      'a1000000-0000-0000-0000-000000000001')$$,
  'indisponivel some do perfil publico, o mesmo portao da descoberta');

reset role;
update public.lawyer_profiles set is_available = true
where id = 'a1000000-0000-0000-0000-000000000001';
update public.profiles set deleted_at = now()
where id = 'a1000000-0000-0000-0000-000000000001';
set local role authenticated;

select is_empty(
  $$select 1 from public.fetch_lawyer_public_profile(
      'a1000000-0000-0000-0000-000000000001')$$,
  'perfil apagado nao volta a existir pelo deep link');

reset role;

select * from finish();
rollback;
