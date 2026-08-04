-- Timeline do processo ao vivo: publica case_movements no Realtime.
--
-- Desde a 20260804150000 a movimentação notifica os dois lados. Faltava o
-- caso contrário do mesmo problema: com o detalhe do caso ABERTO, a sync
-- horária inseria movimentos e a tela na frente da pessoa não mexia — ela
-- recebia a notificação de algo que a tela não mostrava.
--
-- Realtime respeita RLS (case_movements tem RLS ligada com policy de
-- leitura por participante do caso), então cada assinante só recebe os
-- movimentos dos casos que já pode ler. O app ainda filtra por case_id na
-- assinatura, para o socket não carregar o que a tela não usa.
--
-- Idempotente: `add table` em tabela já publicada é erro, não no-op.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'case_movements'
  ) then
    alter publication supabase_realtime add table public.case_movements;
  end if;
end;
$$;
