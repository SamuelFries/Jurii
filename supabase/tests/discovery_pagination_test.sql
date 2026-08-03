-- Testes da migration 20260803120000: paginação estável da descoberta.
-- Página 1 ∪ página 2 = prefixo da lista completa, sem duplicata e sem pulo;
-- offset negativo clampa; além do fim é vazio; grants preservados no
-- drop+create (a armadilha de sempre).
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(12);

-- ---------------------------------------------------------------------------
-- Fixtures: 7 advogados aprovados e disponíveis, 7 escritórios ativos.
-- created_at IDÊNTICO de propósito em um par de cada lado: é o empate que o
-- desempate por id resolve — sem ele este teste flake-ia entre páginas.
-- ---------------------------------------------------------------------------

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select
  ('a0000000-0000-0000-0000-00000000000' || i)::uuid,
  'authenticated', 'authenticated',
  'advogado' || i || '@paginacao.test', '', now(), '{}'::jsonb,
  ('{"full_name":"Advogado Pag ' || i || '"}')::jsonb, now(), now()
from generate_series(1, 7) as i;

update public.profiles set lawyer_status = 'approved'
where id::text like 'a0000000-0000-0000-0000-00000000000%';

insert into public.lawyer_profiles
  (id, oab_number, oab_state, primary_area, practice_areas, approved_at, created_at)
select
  ('a0000000-0000-0000-0000-00000000000' || i)::uuid,
  '90910' || i, 'RS', 'Direito Cível', array['Direito Cível'],
  -- Dois últimos EMPATAM em approved_at e created_at (o par do desempate).
  case when i >= 6 then timestamptz '2026-08-01 10:00'
       else timestamptz '2026-08-01 10:00' + (i || ' hours')::interval end,
  case when i >= 6 then timestamptz '2026-07-01 10:00'
       else timestamptz '2026-07-01 10:00' + (i || ' hours')::interval end
from generate_series(1, 7) as i;

insert into public.law_firms (id, name, initials, specialty, is_active, created_at)
select
  ('b0000000-0000-0000-0000-00000000000' || i)::uuid,
  'Firma Pag ' || i, 'FP', 'Direito Cível', true,
  case when i >= 6 then timestamptz '2026-07-01 10:00'
       else timestamptz '2026-07-01 10:00' + (i || ' hours')::interval end
from generate_series(1, 7) as i;

-- ---------------------------------------------------------------------------
-- Advogados: páginas emendam sem duplicar nem pular
-- ---------------------------------------------------------------------------

select results_eq(
  $$
    with p1 as (
      select id, row_number() over () as rn
      from fetch_recommended_lawyers(3, null, 0)
    ),
    p2 as (
      select id, row_number() over () + 3 as rn
      from fetch_recommended_lawyers(3, null, 3)
    ),
    paginado as (select id, rn from p1 union all select id, rn from p2),
    direto as (
      select id, row_number() over () as rn
      from fetch_recommended_lawyers(6, null, 0)
    )
    select paginado.id::text, direto.id::text
    from paginado join direto using (rn)
    order by rn
  $$,
  $$
    select id::text, id::text
    from fetch_recommended_lawyers(6, null, 0)
  $$,
  'advogados: duas paginas de 3 = exatamente a lista de 6, na mesma ordem');

select is(
  (select count(distinct id) from (
    select id from fetch_recommended_lawyers(3, null, 0)
    union all
    select id from fetch_recommended_lawyers(3, null, 3)
  ) s)::int,
  6,
  'advogados: nenhuma duplicata entre paginas consecutivas');

select is(
  (select count(*) from fetch_recommended_lawyers(6, null, 100))::int,
  0,
  'advogados: offset alem do fim devolve vazio');

select results_eq(
  $$select id from fetch_recommended_lawyers(3, null, -5)$$,
  $$select id from fetch_recommended_lawyers(3, null, 0)$$,
  'advogados: offset negativo clampa em zero');

-- O par empatado (ids ...6 e ...7) tem que sair em ordem determinística de id
-- nas DUAS consultas — é o que impede pulo/duplicata na borda da página.
select results_eq(
  $$select id from fetch_recommended_lawyers(20, null, 0)
    offset 5$$,
  $$values ('a0000000-0000-0000-0000-000000000006'::uuid),
           ('a0000000-0000-0000-0000-000000000007'::uuid)$$,
  'advogados: empate em approved_at/created_at desempata por id');

-- ---------------------------------------------------------------------------
-- Escritórios: mesmas garantias
-- ---------------------------------------------------------------------------

select results_eq(
  $$
    with p1 as (
      select id, row_number() over () as rn
      from fetch_recommended_law_firms(3, null, 0)
    ),
    p2 as (
      select id, row_number() over () + 3 as rn
      from fetch_recommended_law_firms(3, null, 3)
    ),
    paginado as (select id, rn from p1 union all select id, rn from p2),
    direto as (
      select id, row_number() over () as rn
      from fetch_recommended_law_firms(6, null, 0)
    )
    select paginado.id::text, direto.id::text
    from paginado join direto using (rn)
    order by rn
  $$,
  $$
    select id::text, id::text
    from fetch_recommended_law_firms(6, null, 0)
  $$,
  'escritorios: duas paginas de 3 = exatamente a lista de 6, na mesma ordem');

select is(
  (select count(distinct id) from (
    select id from fetch_recommended_law_firms(3, null, 0)
    union all
    select id from fetch_recommended_law_firms(3, null, 3)
  ) s)::int,
  6,
  'escritorios: nenhuma duplicata entre paginas consecutivas');

select is(
  (select count(*) from fetch_recommended_law_firms(6, null, 100))::int,
  0,
  'escritorios: offset alem do fim devolve vazio');

-- Busca + offset: o filtro vale igual nas duas páginas (nada de página 2
-- ignorar a busca e vazar perfil de outra área).
select is(
  (select count(*) from fetch_recommended_law_firms(3, 'trabalhista', 3))::int,
  0,
  'escritorios: busca sem resultado nao ganha itens na pagina 2');

-- ---------------------------------------------------------------------------
-- Grants: drop+create zera EXECUTE — a recriação tem que devolver ao
-- authenticated e NEGAR ao anon (assinatura nova int,text,int).
-- ---------------------------------------------------------------------------

select ok(
  has_function_privilege('authenticated',
    'public.fetch_recommended_lawyers(int, text, int)', 'execute'),
  'authenticated executa fetch_recommended_lawyers paginada');

select ok(
  not has_function_privilege('anon',
    'public.fetch_recommended_lawyers(int, text, int)', 'execute'),
  'anon NAO executa fetch_recommended_lawyers');

select ok(
  not has_function_privilege('anon',
    'public.fetch_recommended_law_firms(int, text, int)', 'execute'),
  'anon NAO executa fetch_recommended_law_firms');

select * from finish();
rollback;
