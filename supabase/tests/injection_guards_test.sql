-- Invariantes anti-injecao do banco.
--
-- A auditoria de 30/07/2026 nao encontrou SQL injection: o projeto e imune
-- por CONSTRUCAO (nenhuma funcao monta SQL dinamicamente) e por DISCIPLINA
-- (tudo qualificado com public., tudo com search_path fixo, busca normalizada
-- por allowlist). O problema da disciplina e que ela some no primeiro dia
-- distraido. Este arquivo transforma cada uma dessas propriedades num teste
-- que quebra alto se alguem reabrir a porta.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(9);

-- ---------------------------------------------------------------------------
-- 1. Nenhuma funcao SECURITY DEFINER sem search_path fixo
--    (vetor classico: o atacante aponta o search_path para um schema seu e a
--    funcao passa a chamar o codigo dele com privilegio de dono)
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::int
   from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.prosecdef
     and not exists (
       select 1 from unnest(coalesce(p.proconfig, '{}')) c
       where c like 'search_path=%'
     )),
  0,
  'toda funcao SECURITY DEFINER fixa o search_path');

-- ---------------------------------------------------------------------------
-- 2. Nenhuma funcao definer referencia tabela do app sem qualificar
--    `pg_temp` e consultado ANTES de `public` para RELACOES, e authenticated
--    pode criar tabela temporaria: uma referencia nao qualificada permitiria
--    sombrear a tabela real por uma temporaria do atacante.
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::int
   from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.prosecdef
     and p.prosrc ~* ('(from|join|into|update|delete[[:space:]]+from)[[:space:]]+('
       || 'legal_cases|profiles|conversations|messages|notifications|law_firms'
       || '|lawyer_profiles|case_requests|law_firm_members|push_tokens'
       || '|professional_reviews|appointments|case_movements|case_updates'
       || '|verification_documents|legal_search_intents)\M')),
  0,
  'nenhuma funcao definer referencia tabela do app sem prefixo public.');

-- ---------------------------------------------------------------------------
-- 3. O cliente nao pode criar objeto em public (precondicao do sequestro
--    de search_path). PG15+ ja nao concede por padrao; isto trava a regressao.
-- ---------------------------------------------------------------------------

select ok(
  not has_schema_privilege('authenticated', 'public', 'CREATE')
  and not has_schema_privilege('anon', 'public', 'CREATE'),
  'authenticated e anon nao criam objetos em public');

-- ---------------------------------------------------------------------------
-- 4. Nenhuma tabela sem RLS: e a rede que segura qualquer filtro que vaze
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::int
   from pg_class c
   join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
  0,
  'toda tabela de public esta com RLS ligada');

-- ---------------------------------------------------------------------------
-- 5. Nenhum SQL dinamico em funcao do app
--    (o event trigger rls_auto_enable, da plataforma, usa object_identity do
--    catalogo, ja com aspas — fica de fora por nome)
-- ---------------------------------------------------------------------------

select is(
  (select coalesce(string_agg(p.proname, ', ' order by p.proname), '')
   from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname <> 'rls_auto_enable'
     and p.prosrc ~* '(\mexecute\M|quote_ident|quote_literal|\mformat\()'),
  '',
  'nenhuma funcao do app monta SQL dinamicamente');

-- ---------------------------------------------------------------------------
-- 6-7. A allowlist do normalizador de busca
--
--   ESTA E A PECA QUE SUSTENTA A BUSCA INTEIRA. O texto do usuario chega ao
--   LADO DO PADRAO de tres LIKEs (fetch_recommended_lawyers,
--   fetch_recommended_law_firms, legal_search_term_matches). O que impede
--   injecao de curinga e o passo `[^a-z0-9]+ -> espaco`. Se alguem "melhorar"
--   esse regex (preservar acento, hifen...), a injecao reabre em silencio.
-- ---------------------------------------------------------------------------

select is(
  public.normalize_practice_area_search('100% _tudo_ %'),
  '100 tudo',
  'curinga de LIKE (% e _) nao sobrevive a normalizacao');

select matches(
  public.normalize_practice_area_search(E'a\\b(c)+*?[d]|e\nf\tg'),
  '^[a-z0-9 ]*$',
  'saida do normalizador vive estritamente em [a-z0-9 ]');

-- ---------------------------------------------------------------------------
-- 8. As primitivas de casamento nao sao alcancaveis pelo cliente
--    (elas confiam que o chamador ja normalizou; expor seria contornar a
--    allowlist do item 6)
-- ---------------------------------------------------------------------------

select ok(
  not has_function_privilege('authenticated',
    'public.legal_search_term_matches(text, text)', 'EXECUTE'),
  'primitiva de casamento nao e executavel pelo cliente');

-- ---------------------------------------------------------------------------
-- 9. Mensagem de erro nao carrega caractere de controle do cliente
--    (uma quebra de linha no payload forjava uma linha de log inteira)
-- ---------------------------------------------------------------------------

select throws_matching(
  $$select public.normalize_law_firm_member_roles(
      array[E'owner\nFALSA LINHA DE LOG', 'x'])$$,
  '^Invalid firm roles: [^' || chr(10) || chr(13) || ']*$',
  'eco do erro nao repassa quebra de linha do cliente');

select * from finish();
rollback;
