-- Testes da migration 20260817120000: ordenacao da descoberta no servidor.
--
-- O defeito que isto fecha: a ordenacao era client-side sobre a pagina JA
-- carregada. Com 10 por pagina e 40 escritorios, "Distancia" respondia "qual o
-- mais perto DOS DEZ PRIMEIROS". Aqui o teste prova o que o paliativo anterior
-- nao conseguia provar: o mais perto vem primeiro MESMO estando no fim da
-- ordem de relevancia, e vem na PRIMEIRA pagina.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(14);

-- ---------------------------------------------------------------------------
-- Fixtures: 3 escritorios em Porto Alegre + 1 sem coordenada.
-- O usuario esta no centro (-30.0277, -51.2287).
-- ---------------------------------------------------------------------------

-- O banco local ja tem escritorios de seed. Este teste afirma ORDEM, entao
-- precisa do palco vazio; o rollback no fim devolve tudo.
update public.law_firms set is_active = false;

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('ec000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'cliente@ordem.test', '', now(), '{}'::jsonb,
   '{"full_name":"Cliente Ordem"}'::jsonb, now(), now());

-- created_at decrescente é desempate da relevancia: o PERTO foi criado por
-- ULTIMO de proposito, entao na relevancia ele vem na frente... e por isso o
-- teste de relevancia usa a nota para separar. Ver abaixo.
insert into public.law_firms
  (id, name, initials, specialty, practice_areas, rating, reviews_count,
   is_active, latitude, longitude, created_at)
values
  -- ~0,5 km do usuario, nota BAIXA, criado primeiro.
  ('ed000000-0000-0000-0000-000000000001', 'Perto e Fraco', 'PF',
   'Direito Cível', array['Direito Cível'], 3.0, 2, true,
   -30.0320, -51.2287, now() - interval '3 days'),
  -- ~11 km do usuario, nota ALTA, criado depois.
  ('ed000000-0000-0000-0000-000000000002', 'Longe e Forte', 'LF',
   'Direito Cível', array['Direito Cível'], 5.0, 50, true,
   -30.1277, -51.2287, now() - interval '2 days'),
  -- ~5,5 km, nota media.
  ('ed000000-0000-0000-0000-000000000003', 'Meio Termo', 'MT',
   'Direito Cível', array['Direito Cível'], 4.0, 10, true,
   -30.0777, -51.2287, now() - interval '1 day'),
  -- Sem coordenada: hoje 39 dos 40 escritorios de producao estao assim.
  ('ed000000-0000-0000-0000-000000000004', 'Sem Coordenada', 'SC',
   'Direito Cível', array['Direito Cível'], 4.9, 30, true,
   null, null, now());

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'ec000000-0000-0000-0000-000000000001', true);
set local role authenticated;

-- ---------------------------------------------------------------------------
-- Distancia
-- ---------------------------------------------------------------------------

select results_eq(
  $$select id from public.fetch_recommended_law_firms(
      10, null, 0, 'distance', -30.0277, -51.2287)$$,
  $$values ('ed000000-0000-0000-0000-000000000001'::uuid),
           ('ed000000-0000-0000-0000-000000000003'::uuid),
           ('ed000000-0000-0000-0000-000000000002'::uuid),
           ('ed000000-0000-0000-0000-000000000004'::uuid)$$,
  'mais perto primeiro; sem coordenada vai para o FIM, nao some');

-- A prova do bug original: com pagina de UM, o mais perto tem que vir na
-- primeira pagina. Client-side, ele so apareceria depois do "Ver mais".
select is(
  (select id from public.fetch_recommended_law_firms(
     1, null, 0, 'distance', -30.0277, -51.2287)),
  'ed000000-0000-0000-0000-000000000001'::uuid,
  'o mais perto vem na PRIMEIRA pagina, e nao atras do "Ver mais"');

-- Paginacao coerente: a pagina 2 continua de onde a 1 parou, sem repetir.
select is(
  (select id from public.fetch_recommended_law_firms(
     1, null, 1, 'distance', -30.0277, -51.2287)),
  'ed000000-0000-0000-0000-000000000003'::uuid,
  'a segunda pagina segue a ordem por distancia');

-- Sem posicao, distancia nao ordena nada: volta para a relevancia, igual ao
-- que o app faz quando o GPS e negado.
select results_eq(
  $$select id from public.fetch_recommended_law_firms(10, null, 0, 'distance')$$,
  $$select id from public.fetch_recommended_law_firms(10, null, 0, 'relevance')$$,
  'distancia SEM posicao cai na relevancia em vez de estourar');

select results_eq(
  $$select id from public.fetch_recommended_law_firms(
      10, null, 0, 'distance', 999, 999)$$,
  $$select id from public.fetch_recommended_law_firms(10, null, 0, 'relevance')$$,
  'coordenada fora de faixa e ignorada, nao vira ordem maluca');

-- ---------------------------------------------------------------------------
-- Avaliacao
-- ---------------------------------------------------------------------------

select is(
  (select id from public.fetch_recommended_law_firms(1, null, 0, 'rating')),
  'ed000000-0000-0000-0000-000000000002'::uuid,
  'avaliacao: a melhor nota vem primeiro, mesmo estando longe');

-- 5,0 com 50 avaliacoes vale mais que 5,0 com uma.
reset role;
insert into public.law_firms
  (id, name, initials, specialty, practice_areas, rating, reviews_count,
   is_active, created_at)
values
  ('ed000000-0000-0000-0000-000000000005', 'Cinco de Uma', 'CU',
   'Direito Cível', array['Direito Cível'], 5.0, 1, true, now());
set local role authenticated;

select results_eq(
  $$select id from public.fetch_recommended_law_firms(2, null, 0, 'rating')$$,
  $$values ('ed000000-0000-0000-0000-000000000002'::uuid),
           ('ed000000-0000-0000-0000-000000000005'::uuid)$$,
  'nota empatada desempata por VOLUME de avaliacoes');

reset role;
delete from public.law_firms where id = 'ed000000-0000-0000-0000-000000000005';

-- ---------------------------------------------------------------------------
-- Patrocinio: vale na relevancia, NAO fura criterio que o cliente pediu
-- ---------------------------------------------------------------------------

insert into public.featured_placements
  (target_type, law_firm_id, starts_at, ends_at)
values
  ('law_firm', 'ed000000-0000-0000-0000-000000000002',
   now() - interval '1 day', now() + interval '30 days');

set local role authenticated;

select is(
  (select id from public.fetch_recommended_law_firms(1, null, 0, 'relevance')),
  'ed000000-0000-0000-0000-000000000002'::uuid,
  'na relevancia, a vaga paga sobe para o topo');

select is(
  (select is_sponsored_slot from public.fetch_recommended_law_firms(
     1, null, 0, 'relevance')),
  true,
  'e a impressao e atribuida a vaga');

-- O cliente pediu "mais perto". Patrocinado nao fura criterio pedido.
select is(
  (select id from public.fetch_recommended_law_firms(
     1, null, 0, 'distance', -30.0277, -51.2287)),
  'ed000000-0000-0000-0000-000000000001'::uuid,
  'na distancia, a vaga paga NAO fura a ordem que o cliente pediu');

-- Atribuir ao slot uma entrega que ele nao fez infla justamente o numero que
-- justifica a renovacao do patrocinio.
select is(
  (select bool_or(is_sponsored_slot) from public.fetch_recommended_law_firms(
     10, null, 0, 'distance', -30.0277, -51.2287)),
  false,
  'fora da relevancia nenhuma impressao e atribuida a vaga paga');

-- O SELO continua: pagou, e identificado, mesmo sem o slot reordenar.
select is(
  (select is_featured from public.fetch_recommended_law_firms(
     10, null, 0, 'distance', -30.0277, -51.2287)
   where id = 'ed000000-0000-0000-0000-000000000002'),
  true,
  'o selo de destaque continua visivel na ordenacao por distancia');

-- ---------------------------------------------------------------------------
-- Compatibilidade e portao
-- ---------------------------------------------------------------------------

-- App publicado chama com TRES argumentos; os novos tem default.
select lives_ok(
  $$select * from public.fetch_recommended_law_firms(10, null, 0)$$,
  'a chamada de 3 argumentos do app antigo continua funcionando');

select ok(
  has_function_privilege('authenticated',
    'public.fetch_recommended_law_firms(int, text, int, text, double precision, double precision)',
    'execute')
  and not has_function_privilege('anon',
    'public.fetch_recommended_law_firms(int, text, int, text, double precision, double precision)',
    'execute'),
  'drop+create nao deixou a funcao aberta para anon');

reset role;

select * from finish();
rollback;
