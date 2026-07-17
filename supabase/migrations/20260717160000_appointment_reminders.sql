-- Lembretes de compromisso (Fase 3 da agenda)
--
-- Avisa o advogado ~1h antes de um compromisso, no sino do app. Sem push ainda
-- (frente separada), entao o disparo e SERVER-SIDE: um job pg_cron roda de
-- tempos em tempos, acha os compromissos proximos que ainda nao foram lembrados
-- e insere uma notificacao (scope lawyer). Quando a frente de push existir, o
-- mesmo job dispara o push tambem.
--
-- Por que server-side e nao no app: lembrete calculado no cliente so aparece se
-- o app estiver aberto — inutil como lembrete. O job roda mesmo com o app
-- fechado, e a notificacao ja espera no sino quando o advogado abre.

-- ---------------------------------------------------------------------------
-- 1. Marca de "ja lembrado" (evita repetir a cada passada do cron)
-- ---------------------------------------------------------------------------

alter table public.appointments
  add column if not exists reminder_sent_at timestamptz;

-- ---------------------------------------------------------------------------
-- 2. Escopo do novo tipo de notificacao
--
-- MESMA armadilha das rodadas anteriores: o sino filtra por escopo, e o escopo
-- vem do TIPO. Sem declarar 'appointment_reminder' como 'lawyer', o lembrete
-- cairia no sino do cliente e o advogado nunca o veria.
-- ---------------------------------------------------------------------------

create or replace function public.infer_notification_scope(
  type_value text,
  current_scope public.notification_scope default null
)
returns public.notification_scope
language sql
immutable
set search_path = public
as $$
  select case
    when type_value in (
      'team_invite',
      'case_request_response',
      'lawyer_recommended',
      'appointment_reminder'
    ) then 'lawyer'::public.notification_scope
    when type_value in ('firm_case_started') then 'firm'::public.notification_scope
    when type_value in (
      'case_request',
      'message',
      'case_update',
      'lawyer_recommendation'
    ) then 'client'::public.notification_scope
    else coalesce(current_scope, 'client'::public.notification_scope)
  end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Disparo dos lembretes
--
-- Compromissos confirmados que comecam na proxima 1h e ainda nao foram
-- lembrados. Uma passada: marca reminder_sent_at E cria a notificacao, no mesmo
-- statement (data-modifying CTEs veem o mesmo snapshot), entao nao ha janela
-- para lembrar duas vezes nem para marcar sem notificar. Retorna quantos saiu.
-- ---------------------------------------------------------------------------

create or replace function public.dispatch_appointment_reminders()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  sent_count integer;
begin
  with due as (
    select a.id, a.lawyer_id, a.title, a.starts_at, a.location
    from public.appointments a
    where a.status = 'confirmed'
      and a.lawyer_id is not null
      and a.reminder_sent_at is null
      and a.starts_at >= now()
      and a.starts_at <= now() + interval '1 hour'
  ),
  marked as (
    update public.appointments
    set reminder_sent_at = now()
    where id in (select id from due)
    returning id
  )
  insert into public.notifications (
    recipient_profile_id,
    type,
    title,
    body,
    metadata,
    scope
  )
  select
    due.lawyer_id,
    'appointment_reminder',
    'Compromisso em breve',
    due.title
      || ' começa às '
      || to_char(due.starts_at at time zone 'America/Sao_Paulo', 'HH24:MI')
      || case
           when nullif(trim(coalesce(due.location, '')), '') is not null
             and due.location <> 'A definir'
           then ' · ' || due.location
           else ''
         end,
    jsonb_build_object(
      'appointment_id', due.id,
      'starts_at', due.starts_at
    ),
    'lawyer'
  from due;

  get diagnostics sent_count = row_count;
  return sent_count;
end;
$$;

revoke all on function public.dispatch_appointment_reminders() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Agendamento: a cada 10 minutos
--
-- pg_cron roda o job como superuser; a funcao e SECURITY DEFINER. cron.schedule
-- faz upsert por nome, entao reaplicar a migration nao duplica o job.
-- ---------------------------------------------------------------------------

create extension if not exists pg_cron;

select cron.schedule(
  'appointment-reminders',
  '*/10 * * * *',
  $cron$select public.dispatch_appointment_reminders();$cron$
);

notify pgrst, 'reload schema';
