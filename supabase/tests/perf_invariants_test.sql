-- Invariantes de performance do schema.
--
-- Os dois problemas que a revisão de 31/07 achou não são de correção pontual:
-- são padrões que voltam sozinhos toda vez que alguém escreve uma policy nova
-- ou uma tabela nova. Estes testes travam os dois.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(4);

-- ---------------------------------------------------------------------------
-- 1. Nenhuma policy reavalia auth.uid() por linha
--
-- Sem `(select ...)` em volta, o Postgres trata a chamada como volátil e a
-- executa uma vez POR LINHA avaliada. Envolvida, vira InitPlan: uma vez por
-- consulta. É o lint 0003 da Supabase e o achado mais repetido da revisão.
-- ---------------------------------------------------------------------------

select is(
  (select coalesce(string_agg(tablename || '.' || policyname, ', ' order by policyname), '')
   from pg_policies
   where schemaname = 'public'
     and (
       (qual like '%auth.uid()%' and qual not like '%( SELECT auth.uid()%')
       or (with_check like '%auth.uid()%'
           and with_check not like '%( SELECT auth.uid()%')
     )),
  '',
  'nenhuma policy chama auth.uid() sem envolver em (select ...)');

-- Mesmo cuidado para as outras funções de auth e para current_setting.
select is(
  (select coalesce(string_agg(tablename || '.' || policyname, ', ' order by policyname), '')
   from pg_policies
   where schemaname = 'public'
     and (
       (qual ~ '(?<!SELECT )auth\.(jwt|role)\(\)' )
       or (with_check ~ '(?<!SELECT )auth\.(jwt|role)\(\)')
     )),
  '',
  'idem para auth.jwt() e auth.role()');

-- ---------------------------------------------------------------------------
-- 2. Toda chave estrangeira tem indice de apoio
--
-- Sem ele, DELETE no pai varre o filho inteiro — e o caminho de exclusao de
-- conta (LGPD) cascateia por quase todas as tabelas.
--
-- Excecao consciente: law_firm_categories.category_id (tabela de vinculo
-- minuscula, sem cascade e sem uso em consulta).
-- ---------------------------------------------------------------------------

select is(
  (select coalesce(string_agg(tabela || '(' || coluna || ')', ', ' order by tabela, coluna), '')
   from (
     select c.conrelid::regclass::text as tabela, a.attname as coluna
     from pg_constraint c
     join pg_namespace n on n.oid = c.connamespace
     join unnest(c.conkey) with ordinality as k(attnum, ord) on true
     join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
     where c.contype = 'f'
       and n.nspname = 'public'
       and c.conrelid::regclass::text <> 'law_firm_categories'
       and not exists (
         select 1 from pg_index i
         where i.indrelid = c.conrelid
           and (i.indkey::int2[])[0:array_length(c.conkey, 1) - 1] = c.conkey
       )
     group by c.oid, c.conrelid, a.attname
   ) faltando),
  '',
  'toda chave estrangeira tem indice (exceto a excecao documentada)');

-- ---------------------------------------------------------------------------
-- 3. Os indices criados existem mesmo (guarda contra a migration ser revertida
--    pela metade)
-- ---------------------------------------------------------------------------

select ok(
  (select count(*) from pg_indexes
   where schemaname = 'public'
     and indexname in (
       'legal_cases_law_firm_id_idx',
       'case_participants_profile_id_idx',
       'notifications_law_firm_id_idx',
       'messages_sender_id_idx'
     )) = 4,
  'os indices dos caminhos quentes estao no lugar');

select * from finish();
rollback;
