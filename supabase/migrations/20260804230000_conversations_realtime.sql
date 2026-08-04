-- Publica `conversations` no Realtime, para as listas de conversa assinarem
-- POR PARTICIPANTE em vez de assinarem `messages` sem filtro.
--
-- Por que trocar: a primeira versao (PR #103) assinava `messages` sem filtro
-- de coluna, apostando que a RLS cortaria por assinante. Mesmo estando certa,
-- a aposta e ruim: o corte da privacidade fica dependendo de um comportamento
-- do servico de Realtime, e um evento indevido carregaria o CORPO da mensagem
-- no payload. Aqui o corte e por coluna, no servidor, sem depender de RLS —
-- e a RLS continua valendo como segunda camada.
--
-- Alem de mais seguro e mais barato: `conversations` recebe UMA linha por
-- conversa (o trigger messages_set_conversation_last_message ja atualiza
-- last_message/last_message_at a cada mensagem), em vez de um evento por
-- mensagem.
--
-- Idempotente: `add table` em tabela ja publicada e erro, nao no-op.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'conversations'
  ) then
    alter publication supabase_realtime add table public.conversations;
  end if;
end;
$$;
