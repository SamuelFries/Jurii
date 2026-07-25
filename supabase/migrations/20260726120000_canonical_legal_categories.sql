-- Categorias populares: conjunto canonico + area juridica explicita
--
-- Producao e repositorio divergiram nesta tabela: prod carrega um seed
-- antigo (ids em ingles: divorce/labor/consumer/real_estate/traffic, 5 linhas,
-- 1 com is_highlighted) anterior ao seed do baseline (ids em portugues,
-- 6 linhas). Nenhum dos dois e o que o app precisa hoje. Esta migration fixa
-- o conjunto canonico e elimina o drift de uma vez.
--
-- Mudancas:
--   1. Coluna practice_area: a area juridica CANONICA da taxonomia do app.
--      O tap na categoria filtra a descoberta por esta area — antes o app
--      inferia por heuristica de id/titulo (fragil: os ids de prod em ingles
--      so funcionavam pelo acaso de o titulo casar).
--   2. Upsert das 6 categorias canonicas — as areas de maior demanda B2C
--      (Familia, Trabalhista, Consumidor, Imobiliario, Previdenciario,
--      Acidente de Transito), grid 3x2 completo.
--   3. Remove as linhas fora do conjunto (o drift). Seguro: a unica FK e
--      law_firm_categories (on delete restrict), vazia em prod e sem uso no
--      app — por precaucao, limpamos vinculos orfaos antes.
--
-- is_highlighted deixa de ser lido pelo app (o dourado "aleatorio" na home
-- nao comunicava nada; o dourado agora e o estado SELECIONADO do filtro).
-- A coluna permanece no banco por compatibilidade, sem efeito.

alter table public.legal_categories
  add column if not exists practice_area text;

insert into public.legal_categories
  (id, title, icon_name, practice_area, is_highlighted, sort_order)
values
  ('divorcio-familia', 'Divórcio e Família', 'family_restroom',
   'Direito de Família', false, 10),
  ('trabalhista', 'Trabalhista', 'work_outline',
   'Direito Trabalhista', false, 20),
  ('consumidor', 'Consumidor', 'shopping_bag_outlined',
   'Direito do Consumidor', false, 30),
  ('imobiliario', 'Imobiliário', 'home_outlined',
   'Direito Imobiliário', false, 40),
  ('previdenciario', 'Previdenciário', 'elderly_outlined',
   'Direito Previdenciário', false, 50),
  ('acidente-transito', 'Acidente de Trânsito', 'directions_car_outlined',
   'Acidente de Trânsito', false, 60)
on conflict (id) do update set
  title = excluded.title,
  icon_name = excluded.icon_name,
  practice_area = excluded.practice_area,
  is_highlighted = excluded.is_highlighted,
  sort_order = excluded.sort_order;

delete from public.law_firm_categories
where category_id not in (
  'divorcio-familia', 'trabalhista', 'consumidor',
  'imobiliario', 'previdenciario', 'acidente-transito'
);

delete from public.legal_categories
where id not in (
  'divorcio-familia', 'trabalhista', 'consumidor',
  'imobiliario', 'previdenciario', 'acidente-transito'
);

notify pgrst, 'reload schema';
