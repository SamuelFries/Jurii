-- Feed .ics assinavel da agenda do advogado
--
-- Fase 2 da agenda. Deixa o advogado assinar a propria agenda da Jurii no
-- Google/Apple/Outlook, uma vez, e ver todo compromisso aparecer la
-- automaticamente. Unidirecional (Jurii -> calendario), sem OAuth de calendario:
-- cobre os tres com uma implementacao so.
--
-- Como funciona: cada advogado tem um TOKEN secreto. A Edge Function
-- `calendar-feed` recebe o token na URL, resolve o advogado e serializa os
-- compromissos em iCalendar. O token e uma "capability URL" — quem tem o link
-- ve a agenda. Por isso e um uuid aleatorio, revogavel (reset gera outro e
-- derruba o antigo; disable desliga o feed).
--
-- Esta migration cuida so do token e das RPCs de gestao. A serializacao .ics
-- vive na Edge Function (le por service_role, filtrando pelo advogado do token).

-- ---------------------------------------------------------------------------
-- 1. Token do feed, por advogado
-- ---------------------------------------------------------------------------

alter table public.lawyer_profiles
  add column if not exists calendar_feed_token uuid unique;

-- ---------------------------------------------------------------------------
-- 2. Ativar o feed (idempotente: se ja existe, devolve o token atual)
-- ---------------------------------------------------------------------------

create or replace function public.enable_calendar_feed()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  token_value uuid;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  if not exists (
    select 1 from public.lawyer_profiles lp where lp.id = auth.uid()
  ) then
    raise exception 'Only lawyers have a calendar feed';
  end if;

  select calendar_feed_token into token_value
  from public.lawyer_profiles
  where id = auth.uid();

  if token_value is null then
    token_value := gen_random_uuid();
    update public.lawyer_profiles
    set calendar_feed_token = token_value
    where id = auth.uid();
  end if;

  return token_value;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Rotacionar o token (invalida o link antigo)
-- ---------------------------------------------------------------------------

create or replace function public.reset_calendar_feed()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  token_value uuid;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  if not exists (
    select 1 from public.lawyer_profiles lp where lp.id = auth.uid()
  ) then
    raise exception 'Only lawyers have a calendar feed';
  end if;

  token_value := gen_random_uuid();
  update public.lawyer_profiles
  set calendar_feed_token = token_value
  where id = auth.uid();

  return token_value;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Desligar o feed
-- ---------------------------------------------------------------------------

create or replace function public.disable_calendar_feed()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  update public.lawyer_profiles
  set calendar_feed_token = null
  where id = auth.uid();
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Ler o token atual (o app monta a URL; null = feed desligado)
-- ---------------------------------------------------------------------------

create or replace function public.get_calendar_feed_token()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select calendar_feed_token
  from public.lawyer_profiles
  where id = auth.uid();
$$;

-- ---------------------------------------------------------------------------
-- 6. Resolver advogado pelo token — usada SO pela Edge Function (service_role).
--
-- Fica fora do alcance de authenticated/anon: um cliente nao deve poder
-- descobrir de quem e um token, so a funcao de servidor que serve o feed.
-- ---------------------------------------------------------------------------

create or replace function public.lawyer_id_for_calendar_feed(token_value uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id
  from public.lawyer_profiles
  where calendar_feed_token = token_value
    and token_value is not null;
$$;

-- ---------------------------------------------------------------------------
-- 7. Compromissos do feed — usada SO pela Edge Function (service_role).
--
-- Leitura por RPC SECURITY DEFINER, nao SELECT direto: o hardening trancou a
-- tabela appointments e service_role nao tem SELECT nela (nem deve — menos
-- superficie). Janela de 60 dias para tras + futuro mantem o feed enxuto.
-- Cancelados entram (a Edge Function emite STATUS:CANCELLED) para sumirem do
-- calendario de quem ja tinha o evento.
-- ---------------------------------------------------------------------------

create or replace function public.fetch_appointments_for_feed(lawyer_id_value uuid)
returns table (
  id uuid,
  title text,
  counterpart_name text,
  area text,
  location text,
  starts_at timestamptz,
  ends_at timestamptz,
  status text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    a.id,
    a.title,
    a.counterpart_name,
    a.area,
    a.location,
    a.starts_at,
    a.ends_at,
    a.status::text
  from public.appointments a
  where a.lawyer_id = lawyer_id_value
    and a.starts_at >= now() - interval '60 days'
  order by a.starts_at;
$$;

-- ---------------------------------------------------------------------------
-- 8. Grants
-- ---------------------------------------------------------------------------

revoke all on function public.enable_calendar_feed() from public, anon;
revoke all on function public.reset_calendar_feed() from public, anon;
revoke all on function public.disable_calendar_feed() from public, anon;
revoke all on function public.get_calendar_feed_token() from public, anon;
revoke all on function public.lawyer_id_for_calendar_feed(uuid) from public, anon, authenticated;
revoke all on function public.fetch_appointments_for_feed(uuid) from public, anon, authenticated;

grant execute on function public.enable_calendar_feed() to authenticated;
grant execute on function public.reset_calendar_feed() to authenticated;
grant execute on function public.disable_calendar_feed() to authenticated;
grant execute on function public.get_calendar_feed_token() to authenticated;
grant execute on function public.lawyer_id_for_calendar_feed(uuid) to service_role;
grant execute on function public.fetch_appointments_for_feed(uuid) to service_role;

notify pgrst, 'reload schema';
