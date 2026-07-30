-- Hardening contra SQL injection: correcao do unico achado + invariantes
--
-- AUDITORIA (30/07/2026, 2 levantamentos + verificacao propria em producao).
-- Resultado: NAO existe SQL injection no projeto, e a razao e estrutural —
-- nenhuma funcao monta comando SQL dinamicamente. O unico `execute` do banco
-- e o event trigger `rls_auto_enable` (gerenciado pela plataforma), que usa
-- `object_identity` vindo do catalogo do proprio Postgres, ja com aspas.
--
-- Verificado em PRODUCAO, nao so no codigo:
--   - 88 funcoes SECURITY DEFINER, ZERO sem `set search_path` fixo;
--   - `authenticated` e `anon` NAO tem CREATE em `public` (PG17 ja nao concede
--     por padrao), entao `search_path = public` nao e sequestravel;
--   - `authenticated` PODE criar tabela temporaria, e `pg_temp` e consultado
--     antes de `public` para RELACOES — mas ZERO funcoes definer referenciam
--     tabela sem qualificar com `public.`, entao o sombreamento nao pega;
--   - todas as tabelas de `public` estao com RLS ligada.
--
-- O UNICO achado real (baixo, e NAO e SQLi): `normalize_law_firm_member_roles`
-- ecoava o texto do cliente cru na mensagem de excecao. Como a mensagem vai
-- para o log do Postgres e para a resposta do PostgREST, uma quebra de linha
-- no payload FORJAVA UMA LINHA DE LOG (reproduzido: um array com
-- E'owner\nFALSA LINHA...' produziu a linha falsa isolada no log). Corrigido
-- abaixo. A funcao e alcancavel por qualquer `authenticated` via
-- `update_law_firm_member_roles`.
--
-- O resto desta migration nao muda comportamento: fixa por TESTE (ver
-- supabase/tests/injection_guards_test.sql) invariantes que hoje se sustentam
-- por disciplina — em especial a allowlist do normalizador de busca, que e a
-- peca que impede injecao de curinga de LIKE em tres funcoes de descoberta.

-- ---------------------------------------------------------------------------
-- 1. Eco sanitizado (corpo VERBATIM da definicao vigente, baseline :7837,
--    extraido programaticamente; muda so o `raise exception`)
-- ---------------------------------------------------------------------------

create or replace function public.normalize_law_firm_member_roles(
  roles_value text[]
)
returns text[]
language plpgsql
immutable
set search_path = public
as $$
declare
  normalized_roles text[];
  invalid_roles text[];
begin
  with raw_roles as (
    select lower(trim(role_value)) as role_value
    from unnest(coalesce(roles_value, '{}'::text[])) as role_value
    where nullif(trim(role_value), '') is not null
  ),
  distinct_roles as (
    select distinct role_value
    from raw_roles
  )
  select coalesce(
    array_agg(
      role_value
      order by case role_value
        when 'owner' then 1
        when 'admin' then 2
        when 'lawyer' then 3
        when 'secretary' then 4
        when 'intern' then 5
        else 99
      end
    ),
    '{}'::text[]
  )
  into normalized_roles
  from distinct_roles
  where role_value in ('owner', 'admin', 'lawyer', 'secretary', 'intern');

  with raw_roles as (
    select lower(trim(role_value)) as role_value
    from unnest(coalesce(roles_value, '{}'::text[])) as role_value
    where nullif(trim(role_value), '') is not null
  ),
  invalid as (
    select distinct role_value
    from raw_roles
    where role_value not in ('owner', 'admin', 'lawyer', 'secretary', 'intern')
  )
  select coalesce(array_agg(role_value), '{}'::text[])
  into invalid_roles
  from invalid;

  if coalesce(array_length(invalid_roles, 1), 0) > 0 then
    -- Eco sanitizado: o conteudo vem do cliente e ia cru para a mensagem de
    -- erro, que aterrissa no log do Postgres e na resposta do PostgREST. Uma
    -- quebra de linha no payload forjava uma LINHA DE LOG inteira (verificado
    -- em 30/07). Remove caracteres de controle e limita o tamanho.
    raise exception 'Invalid firm roles: %',
      left(regexp_replace(array_to_string(invalid_roles, ', '),
                          '[[:cntrl:]]', ' ', 'g'), 120);
  end if;

  if coalesce(array_length(normalized_roles, 1), 0) = 0 then
    return array['lawyer']::text[];
  end if;

  return normalized_roles;
end;
$$;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Verificacao pos-push (SQL Editor):
--   do $v$ begin
--     perform public.normalize_law_firm_member_roles(array[E'owner\nFALSA']);
--   exception when others then raise notice '%', sqlerrm; end $v$;
--   -- a mensagem deve vir em UMA linha so
-- ---------------------------------------------------------------------------
