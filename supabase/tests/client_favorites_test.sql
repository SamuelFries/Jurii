-- Testes da migration 20260803180000: favoritos do cliente.
-- Toggle liga/desliga com estado devolvido; alvo fantasma recusado;
-- isolamento entre usuários; excluído/desativado somem do fetch; tabela
-- trancada e grants nas 4 RPCs.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(18);

-- ---------------------------------------------------------------------------
-- Fixtures: 2 clientes, 1 advogada, 2 escritórios (1 será desativado)
-- ---------------------------------------------------------------------------

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('c1000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'clientea@fav.test', '', now(), '{}'::jsonb,
   '{"full_name":"Cliente A"}'::jsonb, now(), now()),
  ('c1000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'clienteb@fav.test', '', now(), '{}'::jsonb,
   '{"full_name":"Cliente B"}'::jsonb, now(), now()),
  ('c1000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'advogada@fav.test', '', now(), '{}'::jsonb,
   '{"full_name":"Advogada Fav"}'::jsonb, now(), now());

update public.profiles set lawyer_status = 'approved'
where id = 'c1000000-0000-0000-0000-000000000003';

insert into public.lawyer_profiles (id, oab_number, oab_state, primary_area, practice_areas)
values ('c1000000-0000-0000-0000-000000000003', '80801', 'RS',
        'Direito Cível', array['Direito Cível']);

insert into public.law_firms (id, name, initials, specialty, is_active)
values
  ('d1000000-0000-0000-0000-000000000001', 'Firma Fav', 'FF', 'Civil', true),
  ('d1000000-0000-0000-0000-000000000002', 'Firma Some', 'FS', 'Civil', true);

-- ---------------------------------------------------------------------------
-- Toggle: liga, desliga, religa
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select is(
  public.toggle_favorite('lawyer', 'c1000000-0000-0000-0000-000000000003'),
  true,
  'primeiro toggle favorita (true)');

select is(
  public.toggle_favorite('lawyer', 'c1000000-0000-0000-0000-000000000003'),
  false,
  'segundo toggle desfavorita (false)');

select is(
  public.toggle_favorite('lawyer', 'c1000000-0000-0000-0000-000000000003'),
  true,
  'terceiro toggle refavorita (true)');

select is(
  public.toggle_favorite('law_firm', 'd1000000-0000-0000-0000-000000000001'),
  true,
  'escritorio favoritado');

select is(
  public.toggle_favorite('law_firm', 'd1000000-0000-0000-0000-000000000002'),
  true,
  'segundo escritorio favoritado (vai ser desativado depois)');

select throws_ok(
  $$select public.toggle_favorite('court', 'd1000000-0000-0000-0000-000000000001')$$,
  'Invalid favorite target type',
  'tipo de alvo invalido recusado');

select throws_ok(
  $$select public.toggle_favorite('lawyer', 'ffffffff-0000-0000-0000-000000000000')$$,
  'Favorite target not found',
  'advogado inexistente nao e favoritavel');

-- ---------------------------------------------------------------------------
-- Fetch: forma, ordem e visibilidade
-- ---------------------------------------------------------------------------

select results_eq(
  $$select target_type, target_id from public.fetch_favorite_ids()
    order by target_type, target_id$$,
  $$values ('law_firm', 'd1000000-0000-0000-0000-000000000001'::uuid),
           ('law_firm', 'd1000000-0000-0000-0000-000000000002'::uuid),
           ('lawyer',   'c1000000-0000-0000-0000-000000000003'::uuid)$$,
  'fetch_favorite_ids devolve os tres pares');

select results_eq(
  $$select id, full_name from public.fetch_favorite_lawyers()$$,
  $$values ('c1000000-0000-0000-0000-000000000003'::uuid, 'Advogada Fav')$$,
  'fetch_favorite_lawyers devolve a advogada com o nome do perfil');

reset role;

-- Desativa a segunda firma e exclui (soft) a advogada: os dois somem.
update public.law_firms set is_active = false
where id = 'd1000000-0000-0000-0000-000000000002';

select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select results_eq(
  $$select id from public.fetch_favorite_law_firms()$$,
  $$values ('d1000000-0000-0000-0000-000000000001'::uuid)$$,
  'escritorio desativado some do fetch (favorito segue no banco)');

-- Toggle em desativado: a 1ª chamada ainda REMOVE o favorito existente
-- (desligar é sempre permitido); só a 2ª, que tentaria ligar, é recusada.
select is(
  public.toggle_favorite('law_firm', 'd1000000-0000-0000-0000-000000000002'),
  false,
  'desfavoritar escritorio desativado continua permitido');

select throws_ok(
  $$select public.toggle_favorite('law_firm', 'd1000000-0000-0000-0000-000000000002')$$,
  'Favorite target not found',
  'favoritar escritorio desativado e recusado');

reset role;
update public.profiles set deleted_at = now()
where id = 'c1000000-0000-0000-0000-000000000003';

select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select is(
  (select count(*) from public.fetch_favorite_lawyers())::int,
  0,
  'advogada de conta excluida some do fetch');

-- ---------------------------------------------------------------------------
-- Isolamento: B não vê nada de A
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000002', true);
set local role authenticated;

select is(
  (select count(*) from public.fetch_favorite_ids())::int,
  0,
  'outro usuario nao ve os favoritos de A');

reset role;

-- ---------------------------------------------------------------------------
-- Lockdown e grants
-- ---------------------------------------------------------------------------

select ok(
  not has_table_privilege('authenticated', 'public.client_favorites', 'select'),
  'authenticated NAO le a tabela direto (tudo por RPC)');

select ok(
  has_function_privilege('authenticated', 'public.toggle_favorite(text, uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.fetch_favorite_ids()', 'execute')
  and has_function_privilege('authenticated', 'public.fetch_favorite_lawyers()', 'execute')
  and has_function_privilege('authenticated', 'public.fetch_favorite_law_firms()', 'execute'),
  'authenticated executa as 4 RPCs');

select ok(
  not has_function_privilege('anon', 'public.toggle_favorite(text, uuid)', 'execute')
  and not has_function_privilege('anon', 'public.fetch_favorite_ids()', 'execute')
  and not has_function_privilege('anon', 'public.fetch_favorite_lawyers()', 'execute')
  and not has_function_privilege('anon', 'public.fetch_favorite_law_firms()', 'execute'),
  'anon nao executa nenhuma das 4');

-- XOR do alvo vale mesmo para superuser (defesa em profundidade).
select throws_ok(
  $$insert into public.client_favorites (client_id, target_type, lawyer_id, law_firm_id)
    values ('c1000000-0000-0000-0000-000000000001', 'lawyer',
            'c1000000-0000-0000-0000-000000000003',
            'd1000000-0000-0000-0000-000000000001')$$,
  '23514');

select * from finish();
rollback;
