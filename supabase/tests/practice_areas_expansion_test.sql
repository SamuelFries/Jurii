-- Testes da migration 20260816120000: taxonomia de 39 areas + apelidos.
--
-- O que quebrou antes: a lista tinha 10 areas e o cadastro real de producao
-- usava 31 valores fora dela. Parte era APELIDO ("Direito do Trabalho" e
-- "Direito Trabalhista" sao a mesma area) e parte era area que faltava mesmo
-- ("Direito Bancario", "Direito Ambiental"). O efeito de guardar as duas
-- grafias e o mesmo do de nao ter a area: o profissional nao aparece para quem
-- filtra pela grafia canonica.
--
-- Duas barreiras aqui: (1) o mapa traduz, inclusive um-para-dois; (2) TODA
-- porta de escrita passa pelo mapa — se sobrar uma, o problema volta no
-- proximo cadastro.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(27);

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('ea000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'legado@areas.test', '', now(), '{}'::jsonb,
   '{"full_name":"Advogado Legado"}'::jsonb, now(), now()),
  ('ea000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'dono@areas.test', '', now(), '{}'::jsonb,
   '{"full_name":"Dono Areas"}'::jsonb, now(), now()),
  ('ea000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'cliente@areas.test', '', now(), '{}'::jsonb,
   '{"full_name":"Cliente Areas"}'::jsonb, now(), now());

update public.profiles set lawyer_status = 'approved'
where id = 'ea000000-0000-0000-0000-000000000001';

insert into public.lawyer_profiles
  (id, oab_number, oab_state, primary_area, practice_areas, approved_at)
values
  ('ea000000-0000-0000-0000-000000000001', '515151', 'RS',
   'Direito Trabalhista', array['Direito Trabalhista'], now());

insert into public.law_firms
  (id, name, initials, specialty, practice_areas, is_active)
values
  ('eb000000-0000-0000-0000-000000000001', 'Firma Taxonomia', 'FT',
   'Direito Cível', array['Direito Cível'], true);

insert into public.law_firm_members
  (law_firm_id, profile_id, member_role, roles, status)
values
  ('eb000000-0000-0000-0000-000000000001',
   'ea000000-0000-0000-0000-000000000002', 'owner', array['owner'], 'active');

-- ---------------------------------------------------------------------------
-- A lista canonica
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::int from public.legal_practice_areas),
  39,
  'a taxonomia tem 39 areas');

-- As quatro que o comentario da 20260815120000 registrou como faltando.
select is(
  (select count(*)::int from public.legal_practice_areas
    where name in ('Direito Bancário', 'Direito Ambiental',
                   'Direito Administrativo', 'Direito Agrário')),
  4,
  'as areas que a migration anterior registrou como faltando entraram');

-- Area sem nenhum termo de busca so seria achavel por quem digitasse o nome
-- exato dela — e ninguem procura advogado digitando "Direito Securitario".
select is(
  (select count(*)::int from public.legal_practice_areas lpa
    where not exists (
      select 1 from public.legal_search_intents lsi
      where lsi.practice_area = lpa.name and lsi.is_active
    )),
  0,
  'toda area canonica tem termo de busca livre');

-- ---------------------------------------------------------------------------
-- O mapa de apelidos
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::int from public.legal_practice_area_aliases a
    where exists (
      select 1 from unnest(a.canonical_names) alvo
      where not exists (
        select 1 from public.legal_practice_areas lpa where lpa.name = alvo
      )
    )),
  0,
  'nenhum apelido aponta para area inexistente');

-- Um apelido que mapeia para o nada nao aparece em busca nenhuma, em silencio.
-- Por isso o gatilho recusa em vez de aceitar.
select throws_ok(
  $$insert into public.legal_practice_area_aliases (alias, canonical_names)
    values ('Direito Fantasma', array['Direito Que Nao Existe'])$$,
  null,
  'Alias Direito Fantasma points to unknown area: Direito Que Nao Existe',
  'apelido apontando para area inexistente e recusado');

select throws_ok(
  $$insert into public.legal_practice_area_aliases (alias, canonical_names)
    values ('Direito Vazio', array[]::text[])$$,
  null,
  'Alias Direito Vazio has no canonical target',
  'apelido sem alvo e recusado');

-- ---------------------------------------------------------------------------
-- canonical_practice_areas
-- ---------------------------------------------------------------------------

select is(
  public.canonical_practice_areas(array['Direito do Trabalho']),
  array['Direito Trabalhista'],
  'o apelido mais comum de producao (83 usos) e traduzido');

select is(
  public.canonical_practice_areas(array['Direito Civil']),
  array['Direito Cível'],
  'o segundo mais comum (52 usos) tambem');

-- Um campo so com duas areas dentro: quebrar em duas e o unico jeito de o
-- profissional aparecer nas DUAS buscas.
select is(
  public.canonical_practice_areas(array['Direito de Família e Sucessões']),
  array['Direito de Família', 'Direito das Sucessões'],
  'apelido de duas areas vira duas areas, na ordem em que foi escrito');

-- A ordem importa: primary_area/specialty ficam com a PRIMEIRA. Sortear qual
-- das duas seria trocar a area principal de quem so corrigiu o telefone.
select is(
  (public.canonical_practice_areas(array['Direito Civil e de Família']))[1],
  'Direito Cível',
  'a area principal sai da primeira do apelido, nao de sorteio');

select is(
  public.canonical_practice_areas(
    array['direito do TRABALHO', 'Direito Trabalhista', 'Direito Civel']),
  array['Direito Trabalhista', 'Direito Cível'],
  'tolera caixa e acento, e nao duplica o que colapsa no mesmo valor');

-- Canonicalizar NAO e validar: quem decide se um valor desconhecido entra e a
-- allowlist da RPC. Aqui o valor so passa reto.
select is(
  public.canonical_practice_areas(array['Direito Que Ninguem Inventou']),
  array['Direito Que Ninguem Inventou'],
  'valor desconhecido passa reto — canonicalizar nao e validar');

select is(
  public.canonical_practice_areas(array['  Direito do Trabalho  ', '', null]),
  array['Direito Trabalhista'],
  'apara espaco e descarta vazio/nulo');

select is(
  public.canonical_practice_areas(null),
  array[]::text[],
  'array nulo devolve array vazio, nao nulo');

-- ---------------------------------------------------------------------------
-- Porta 1: a RPC de areas do advogado
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select is(
  public.update_lawyer_practice_areas('Direito do Trabalho',
    array['Direito do Trabalho', 'Direito Bancário']),
  array['Direito Bancário', 'Direito Trabalhista'],
  'a RPC do advogado traduz o apelido em vez de recusar');

select is(
  (select primary_area from public.lawyer_profiles
    where id = 'ea000000-0000-0000-0000-000000000001'),
  'Direito Trabalhista',
  'a area principal foi gravada canonica');

-- Area nova continua entrando so pelo vocabulario canonico.
select throws_ok(
  $$select public.update_lawyer_practice_areas('Direito Trabalhista',
      array['Direito Trabalhista', 'Direito Que Eu Inventei'])$$,
  'Invalid practice area: Direito Que Eu Inventei',
  'area inventada continua recusada, nomeando o culpado');

reset role;

-- Clausula de avo: area que sobrou fora da lista nao pode travar a correcao
-- das OUTRAS. Seria pedir que a pessoa consertasse algo que a tela nem
-- oferece.
update public.lawyer_profiles
set practice_areas = array['Direito Trabalhista', 'Especialidade Exotica']
where id = 'ea000000-0000-0000-0000-000000000001';

set local role authenticated;

select lives_ok(
  $$select public.update_lawyer_practice_areas('Direito Trabalhista',
      array['Direito Trabalhista', 'Especialidade Exotica',
            'Direito Ambiental'])$$,
  'area herdada nao trava o acrescimo de uma area valida');

reset role;

-- ---------------------------------------------------------------------------
-- Porta 2: a verificacao do advogado
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000003', true);
set local role authenticated;

select is(
  (select practice_areas from public.submit_lawyer_verification(
     '777777', 'RS', 'Direito do Trabalho',
     array['Direito do Trabalho', 'Direito Médico'])),
  array['Direito Trabalhista', 'Direito Médico e da Saúde'],
  'a verificacao do advogado traduz apelido');

select is(
  (select practice_area from public.lawyer_verifications
    where user_id = 'ea000000-0000-0000-0000-000000000003'),
  'Direito Trabalhista',
  'a area principal da verificacao foi gravada canonica');

reset role;

-- ---------------------------------------------------------------------------
-- Porta 3: o cadastro do escritorio
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000002', true);
set local role authenticated;

select is(
  (select practice_areas from public.update_law_firm_profile(
     'eb000000-0000-0000-0000-000000000001', 'Firma Taxonomia', null, null,
     null, null, null, null, null, 'Direito do Trabalho',
     array['Direito do Trabalho', 'Direito Civil'])),
  array['Direito Cível', 'Direito Trabalhista'],
  'o cadastro do escritorio traduz apelido');

select is(
  (select specialty from public.law_firms
    where id = 'eb000000-0000-0000-0000-000000000001'),
  'Direito Trabalhista',
  'a especialidade do escritorio foi gravada canonica');

reset role;

-- ---------------------------------------------------------------------------
-- Porta 4: a verificacao do escritorio — a UNICA que nao passa por RPC.
-- Deixar so ela sem traducao seria manter aberta a porta pela qual o problema
-- entrou.
-- ---------------------------------------------------------------------------

set local role authenticated;

insert into public.law_firm_verifications
  (owner_profile_id, firm_name, cnpj, practice_areas)
values
  ('ea000000-0000-0000-0000-000000000002', 'Firma Nova', '11222333000181',
   array['Direito do Trabalho', 'Direito de Família e Sucessões']);

reset role;

select is(
  (select practice_areas from public.law_firm_verifications
    where firm_name = 'Firma Nova'),
  array['Direito Trabalhista', 'Direito de Família', 'Direito das Sucessões'],
  'o INSERT direto na verificacao do escritorio tambem passa pelo mapa');

-- ---------------------------------------------------------------------------
-- O efeito que interessa: quem procura, acha
-- ---------------------------------------------------------------------------

update public.lawyer_profiles
set primary_area = 'Direito das Sucessões',
    practice_areas = array['Direito das Sucessões'],
    is_available = true
where id = 'ea000000-0000-0000-0000-000000000001';

select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000003', true);
set local role authenticated;

-- Ninguem digita "Direito Sucessorio" na busca; digita o que aconteceu.
select is(
  (select count(*)::int from public.fetch_recommended_lawyers(10, 'meu pai morreu', 0)
    where id = 'ea000000-0000-0000-0000-000000000001'),
  1,
  'advogado de Sucessoes aparece para quem escreve "meu pai morreu"');

select is(
  (select count(*)::int from public.fetch_recommended_lawyers(10, 'seguradora negou', 0)
    where id = 'ea000000-0000-0000-0000-000000000001'),
  0,
  'e nao aparece para a busca de outra area');

reset role;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

select ok(
  has_table_privilege('authenticated', 'public.legal_practice_area_aliases',
    'select')
  and not has_table_privilege('anon', 'public.legal_practice_area_aliases',
    'select')
  and not has_table_privilege('authenticated',
    'public.legal_practice_area_aliases', 'insert'),
  'authenticated so LE o mapa de apelidos; anon nem isso');

select ok(
  has_function_privilege('authenticated',
    'public.canonical_practice_areas(text[])', 'execute')
  and not has_function_privilege('anon',
    'public.canonical_practice_areas(text[])', 'execute'),
  'so authenticated executa canonical_practice_areas');

select * from finish();
rollback;
