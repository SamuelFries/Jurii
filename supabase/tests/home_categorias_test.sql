-- As categorias da home e os termos que elas pescam, do lado do SERVIDOR.
--
-- O toque num cartao manda o TITULO para a caixa de busca, e quem filtra em
-- producao e infer_legal_search_areas, nao o matcher Dart. Este teste e o
-- gemeo de test/categorias_populares_test.dart: se um titulo deixar de
-- pescar a propria practice_area AQUI, o cartao promete uma area que o
-- filtro de producao nao inclui. E o defeito original de "Plano de Saude"
-- (tocar mostrava 1 advogado, digitar mostrava 4).
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(7);

-- Todo titulo de categoria, lido como busca, pesca a propria area.
select is(
  (select count(*)::int
   from public.legal_categories lc
   where not exists (
     select 1 from public.infer_legal_search_areas(lc.title) inferida
     where inferida.practice_area = lc.practice_area
   )),
  0,
  'todo titulo de categoria pesca a propria practice_area no servidor');

-- O conjunto e exatamente o das 9, com o cartao de Criminal no lugar do de
-- Plano de Saude (prateleira mais rala do app: 1 advogado, 2 escritorios).
select is(
  (select count(*)::int from public.legal_categories), 9,
  'a grade 3x3 tem exatamente 9 categorias');

select is(
  (select practice_area from public.legal_categories
    where id = 'crime-agressao'),
  'Direito Criminal',
  'a porta de Criminal existe e aponta para a area certa');

select is(
  (select count(*)::int from public.legal_categories
    where id = 'plano-de-saude'),
  0,
  'plano-de-saude saiu da grade');

-- A busca mais sensivel do app: "violencia domestica" e Criminal, sem os 55
-- perfis trabalhistas que o termo solto 'domestica' arrastava para dentro.
select is(
  (select count(*)::int
   from public.infer_legal_search_areas('violência doméstica')
   where practice_area = 'Direito Trabalhista'),
  0,
  'violencia domestica nao pesca mais Trabalhista');

select isnt_empty(
  $$select 1 from public.infer_legal_search_areas('violência doméstica')
     where practice_area = 'Direito Criminal'$$,
  'violencia domestica continua pescando Criminal');

-- E "sou domestica" continua achando o advogado trabalhista.
select isnt_empty(
  $$select 1 from public.infer_legal_search_areas('sou doméstica e não recebi')
     where practice_area = 'Direito Trabalhista'$$,
  'sou domestica continua Trabalhista');

select * from finish();
rollback;
