-- Notificacoes push - fundacao server-side (parte 2: disparo)
--
-- Trigger central: toda linha nova em `notifications` chama a Edge Function
-- send-push (via pg_net). Assim TODO tipo de notificacao (lembrete da agenda,
-- recomendacao, mensagem) ganha push sem codigo extra em cada lugar.
--
-- Configuracao vem do Vault (nao do git): a URL da funcao e a service_role key
-- ficam em vault.secrets, populados pelo Samuel em producao. Enquanto nao
-- estiverem la, o trigger e NO-OP — as notificacoes continuam sendo criadas
-- normalmente, so nao sai push. Isso deixa a fundacao segura para ir a prod
-- antes do Firebase existir.

create extension if not exists pg_net;

create or replace function public.notify_push_on_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  fn_url text;
  service_key text;
begin
  select decrypted_secret into fn_url
  from vault.decrypted_secrets where name = 'push_hook_url';

  select decrypted_secret into service_key
  from vault.decrypted_secrets where name = 'push_hook_service_key';

  -- Push ainda nao configurado (sem os secrets): nao faz nada e, sobretudo, nao
  -- impede a criacao da notificacao.
  if fn_url is null or service_key is null then
    return new;
  end if;

  perform net.http_post(
    url := fn_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || service_key
    ),
    body := jsonb_build_object(
      'recipient_profile_id', new.recipient_profile_id,
      'title', new.title,
      'body', new.body,
      'type', new.type,
      'notification_id', new.id
    )
  );

  return new;
end;
$$;

drop trigger if exists notifications_push_dispatch on public.notifications;
create trigger notifications_push_dispatch
after insert on public.notifications
for each row execute function public.notify_push_on_notification();

notify pgrst, 'reload schema';
