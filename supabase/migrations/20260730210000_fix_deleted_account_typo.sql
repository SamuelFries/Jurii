-- Typo visivel ao usuario: "(delleted account)" -> "(conta excluida)"
--
-- `profile_display_name` tem DUAS sobrecargas, que so diferem na ordem dos
-- dois ultimos argumentos:
--
--   (full_name, deleted_display_name, deleted_at)  -> dizia "(delleted account)"
--   (full_name, deleted_at, deleted_display_name)  -> diz  "(conta excluida)"
--
-- A correcao do typo (patch_044) pegou so a segunda. A primeira sobreviveu e e
-- justamente a que tres funcoes vivas chamam:
--   - fetch_lawyer_cases                  (nome do cliente na lista de casos)
--   - fetch_conversations_for_current_user (titulo na LISTA DE CONVERSAS)
--   - fetch_conversation_for_current_user  (titulo dentro do chat)
--
-- Ou seja: quando um cliente exclui a conta, o advogado ve "Maria (delleted
-- account)" na lista de casos E na lista de conversas. Texto em ingles, com
-- erro de grafia, num app em portugues.
--
-- Corpo VERBATIM da definicao vigente (extraida do banco com
-- pg_get_functiondef); muda so a string. As tres chamadas ficam corretas sem
-- tocar em nenhuma delas. A outra sobrecarga nao e alterada — ja esta certa.

create or replace function public.profile_display_name(
  full_name_value text,
  deleted_display_name_value text,
  deleted_at_value timestamp with time zone
)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when deleted_at_value is not null then
      coalesce(
        nullif(trim(deleted_display_name_value), ''),
        nullif(trim(full_name_value), ''),
        'Usuário'
      ) || ' (conta excluída)'
    else
      coalesce(nullif(trim(full_name_value), ''), 'Usuário Jurii')
  end;
$$;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Verificacao pos-push (SQL Editor): as duas sobrecargas devem concordar.
--   select public.profile_display_name('Maria'::text, null::text, now());
--   select public.profile_display_name('Maria'::text, now(), null::text);
--   -- ambas: "Maria (conta excluída)"
-- ---------------------------------------------------------------------------
