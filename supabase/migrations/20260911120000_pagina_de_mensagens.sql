-- Uma página de mensagens, com o cursor no lugar certo.
--
-- O chat tinha um teto fixo de 100 mensagens com um TODO: conversa jurídica
-- passa disso numa semana, e a mensagem 101 sumia em silêncio, como se o
-- histórico começasse no meio.
--
-- POR QUE UMA FUNÇÃO, e não um filtro montado no app: o cursor composto
-- ((created_at, id) < (X, Y), estável sob timestamps empatados) só se
-- escreve no PostgREST pela sintaxe de string do `or=`, e a barreira
-- anti-injeção do app (test/query_safety_test.dart, auditoria de 30/07)
-- proíbe exatamente essa família de filtros. A barreira está certa: aqui os
-- argumentos entram PARAMETRIZADOS, a comparação de linha é nativa do
-- Postgres, e não existe string interpretada em nenhum ponto do caminho.
--
-- SECURITY INVOKER de propósito: a função roda como quem chama, e a RLS de
-- `messages` (participante da conversa) continua sendo quem corta. Uma
-- definer aqui teria que reimplementar o predicado de acesso, e duas cópias
-- da mesma regra é como esse tipo de regra diverge.

create or replace function public.fetch_conversation_messages_page(
  conversation_id_value uuid,
  before_created_at timestamptz default null,
  before_id uuid default null,
  page_size int default 50
)
returns setof public.messages
language sql
stable
security invoker
set search_path = public
as $$
  select m.*
  from public.messages m
  where m.conversation_id = conversation_id_value
    and (
      -- Primeira página: sem cursor.
      before_created_at is null
      or before_id is null
      -- Páginas seguintes: tudo estritamente ANTES do cursor, com o id como
      -- desempate. Duas mensagens no mesmo timestamp não fazem o cursor
      -- pular nenhuma nem repetir nenhuma.
      or (m.created_at, m.id) < (before_created_at, before_id)
    )
  order by m.created_at desc, m.id desc
  -- Teto duro por chamada: o app pede pageSize+1 (sentinela do hasMore), e
  -- ninguém pede a conversa inteira de uma vez por engano.
  limit least(greatest(coalesce(page_size, 50), 1), 200);
$$;

revoke all on function public.fetch_conversation_messages_page(uuid, timestamptz, uuid, int)
  from public, anon;
grant execute on function public.fetch_conversation_messages_page(uuid, timestamptz, uuid, int)
  to authenticated;

notify pgrst, 'reload schema';
