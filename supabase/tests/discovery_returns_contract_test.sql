-- O CONTRATO das RPCs que alimentam LawFirmRepository.firmFromRow.
--
-- POR QUE ESTE TESTE EXISTE. Coluna que o parser le e a RPC nao devolve NAO
-- levanta erro: a chave nao vem, o parser le null, e o campo some da tela em
-- silencio. Aconteceu duas vezes em uma semana:
--
--   1. license_repository pedia lista explicita de colunas e esqueceu
--      annual_price_cents: a chave Mensal/Anual parou de mudar preco.
--   2. A 20260819120000 criou address_number/address_complement e atualizou
--      quem GRAVA, mas nao as RPCs da descoberta: o perfil publico do
--      escritorio ficaria sem o numero da rua.
--
-- Teste de widget nao pega nenhum dos dois, porque os fakes devolvem objeto
-- pronto e pulam a query. Aqui a fonte da verdade e o proprio banco.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(6);

-- ---------------------------------------------------------------------------
-- Toda coluna que o parser le tem que sair das DUAS RPCs de escritorio.
--
-- A lista abaixo espelha LawFirmRepository.firmFromRow
-- (lib/repositories/law_firm_repository.dart). Coluna nova no model entra
-- aqui, e o teste diz qual RPC esqueceu.
-- ---------------------------------------------------------------------------

create or replace function pg_temp.colunas_que_faltam(fn text)
returns text[]
language sql
as $$
  select coalesce(array_agg(esperada order by esperada), '{}'::text[])
  from unnest(array[
    'id', 'name', 'initials', 'rating', 'specialty', 'practice_areas',
    'reviews_count', 'avatar_type', 'avatar_url', 'description',
    'phone', 'email', 'website_url',
    'address', 'address_number', 'address_complement',
    'latitude', 'longitude'
  ]) as esperada
  where not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    cross join lateral unnest(coalesce(p.proargnames, '{}'::text[])) as arg(nome)
    where n.nspname = 'public'
      and p.proname = fn
      and arg.nome = esperada
  );
$$;

select is(
  pg_temp.colunas_que_faltam('fetch_recommended_law_firms'),
  '{}'::text[],
  'fetch_recommended_law_firms devolve tudo que o parser le');

select is(
  pg_temp.colunas_que_faltam('fetch_favorite_law_firms'),
  '{}'::text[],
  'fetch_favorite_law_firms devolve tudo que o parser le');

-- A RPC de edicao tambem alimenta o mesmo parser (o retorno vira o LawFirm
-- que a tela reexibe depois de salvar).
select is(
  pg_temp.colunas_que_faltam('update_law_firm_profile'),
  '{}'::text[],
  'update_law_firm_profile devolve tudo que o parser le');

-- ---------------------------------------------------------------------------
-- E o dado passa de ponta a ponta, nao so o nome da coluna
-- ---------------------------------------------------------------------------

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('f6000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'cliente@contrato.test', '', now(), '{}'::jsonb,
   '{"full_name":"Cliente Contrato"}'::jsonb, now(), now());

update public.law_firms set is_active = false;

insert into public.law_firms
  (id, name, initials, specialty, practice_areas, address, address_number,
   address_complement, cep, is_active)
values
  ('f7000000-0000-0000-0000-000000000001', 'Firma Contrato', 'FC',
   'Direito Cível', array['Direito Cível'],
   'Rua Germano Petersen Júnior, Auxiliadora, Porto Alegre - RS',
   '70', 'sala 1102', '90540140', true);

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'f6000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select results_eq(
  $$select address_number, address_complement
    from public.fetch_recommended_law_firms(10, null, 0)$$,
  $$values ('70', 'sala 1102')$$,
  'o numero chega pela descoberta, e nao so o nome da coluna');

reset role;

insert into public.client_favorites (client_id, target_type, law_firm_id)
values ('f6000000-0000-0000-0000-000000000001', 'law_firm',
        'f7000000-0000-0000-0000-000000000001');

set local role authenticated;

select results_eq(
  $$select address_number, address_complement
    from public.fetch_favorite_law_firms()$$,
  $$values ('70', 'sala 1102')$$,
  'e pelos favoritos tambem');

-- Sem numero, o campo vem nulo e a tela cai no endereco puro: e o caso dos 40
-- escritorios de producao, que ainda tem o numero dentro de `address`.
reset role;
update public.law_firms
set address_number = null, address_complement = null
where id = 'f7000000-0000-0000-0000-000000000001';
set local role authenticated;

select results_eq(
  $$select address_number, address_complement
    from public.fetch_recommended_law_firms(10, null, 0)$$,
  $$values (null::text, null::text)$$,
  'cadastro sem numero devolve nulo, sem inventar valor');

reset role;

select * from finish();
rollback;
