-- Agenda do advogado: criar, editar e cancelar compromissos
--
-- A tabela public.appointments existia desde a baseline, mas era orfa: o
-- hardening round 2 revogou insert/update direto (e removeu as policies de
-- escrita), e nunca houve RPC para popular a agenda. Resultado: schema + leitura
-- + tela, sem NENHUM caminho para criar compromisso (0 registros em producao).
--
-- Esta migration da o motor, seguindo a direcao do projeto pos-hardening: toda
-- escrita passa por RPC SECURITY DEFINER, nunca por acesso direto a tabela.
--
-- Escopo: agenda PESSOAL do advogado (ele gerencia os proprios compromissos).
-- Agendamento pelo cliente (tipo Calendly) e uma frente separada, maior, que
-- depende desta.

-- ---------------------------------------------------------------------------
-- 1. client_id deixa de ser obrigatorio
--
-- Nem todo compromisso do advogado tem um cliente da plataforma: audiencia,
-- prazo interno, reuniao de equipe. A coluna era NOT NULL herdada de quando a
-- agenda so imaginava atendimentos. Producao tem 0 appointments, entao soltar a
-- restricao e trivial. A policy de SELECT ja cobre o dono por lawyer_id, entao
-- client_id nulo nao esconde nem vaza nada.
-- ---------------------------------------------------------------------------

alter table public.appointments alter column client_id drop not null;

-- ---------------------------------------------------------------------------
-- 2. Deteccao de conflito de horario
--
-- Recusa sobreposicao com outro compromisso ATIVO (nao cancelado) do mesmo
-- advogado. Intervalo semiaberto [inicio, fim): dois compromissos encostados
-- (um termina 10h, outro comeca 10h) NAO conflitam. No update, ignora o proprio
-- compromisso via except_id.
-- ---------------------------------------------------------------------------

create or replace function public.lawyer_has_appointment_conflict(
  lawyer_id_value uuid,
  starts_at_value timestamptz,
  ends_at_value timestamptz,
  except_id uuid default null
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.appointments a
    where a.lawyer_id = lawyer_id_value
      and a.status <> 'cancelled'
      and (except_id is null or a.id <> except_id)
      and starts_at_value < coalesce(a.ends_at, a.starts_at + interval '1 hour')
      and ends_at_value > a.starts_at
  );
$$;

-- ---------------------------------------------------------------------------
-- 3. create_appointment
--
-- Quando vem case_id, o compromisso e amarrado ao caso: valida que o caso e do
-- advogado e deriva client_id + counterpart_name do cliente (nunca confia nesses
-- campos vindos do app). Sem case_id, e um compromisso solto (counterpart_name
-- livre, ex.: "2a Vara do Trabalho").
-- ---------------------------------------------------------------------------

create or replace function public.create_appointment(
  title_value text,
  starts_at_value timestamptz,
  ends_at_value timestamptz,
  location_value text default null,
  area_value text default null,
  counterpart_name_value text default null,
  case_id_value uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  appointment_id uuid;
  clean_title text;
  clean_location text;
  clean_area text;
  clean_counterpart text;
  resolved_client_id uuid;
  case_row public.legal_cases%rowtype;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  if not exists (
    select 1 from public.lawyer_profiles lp where lp.id = auth.uid()
  ) then
    raise exception 'Only lawyers can create appointments';
  end if;

  clean_title := nullif(trim(coalesce(title_value, '')), '');
  if clean_title is null then
    raise exception 'Title is required';
  end if;

  if starts_at_value is null or ends_at_value is null then
    raise exception 'Start and end are required';
  end if;

  if ends_at_value <= starts_at_value then
    raise exception 'End time must be after start time';
  end if;

  clean_location := coalesce(nullif(trim(coalesce(location_value, '')), ''), 'A definir');
  clean_area := coalesce(nullif(trim(coalesce(area_value, '')), ''), '');
  clean_counterpart := nullif(trim(coalesce(counterpart_name_value, '')), '');

  -- Caso vinculado: a fonte da verdade do cliente e o caso, nao o app.
  if case_id_value is not null then
    select * into case_row
    from public.legal_cases
    where id = case_id_value;

    if not found or case_row.assigned_lawyer_id <> auth.uid() then
      raise exception 'Case not found or not assigned to you';
    end if;

    resolved_client_id := case_row.client_id;

    if clean_counterpart is null then
      select coalesce(full_name, 'Cliente') into clean_counterpart
      from public.profiles where id = case_row.client_id;
    end if;
  end if;

  if public.lawyer_has_appointment_conflict(
    auth.uid(), starts_at_value, ends_at_value, null
  ) then
    raise exception 'Appointment overlaps an existing one';
  end if;

  insert into public.appointments (
    role,
    client_id,
    lawyer_id,
    law_firm_id,
    case_id,
    title,
    area,
    counterpart_name,
    starts_at,
    ends_at,
    location,
    status
  )
  values (
    'lawyer',
    resolved_client_id,
    auth.uid(),
    null,
    case_id_value,
    clean_title,
    clean_area,
    coalesce(clean_counterpart, ''),
    starts_at_value,
    ends_at_value,
    clean_location,
    'confirmed'
  )
  returning id into appointment_id;

  return appointment_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. update_appointment (so o dono; revalida horario e conflito)
-- ---------------------------------------------------------------------------

create or replace function public.update_appointment(
  appointment_id_value uuid,
  title_value text,
  starts_at_value timestamptz,
  ends_at_value timestamptz,
  location_value text default null,
  area_value text default null,
  counterpart_name_value text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  appointment_row public.appointments%rowtype;
  clean_title text;
  clean_location text;
  clean_area text;
  clean_counterpart text;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  select * into appointment_row
  from public.appointments
  where id = appointment_id_value
  for update;

  if not found then
    raise exception 'Appointment not found';
  end if;

  if appointment_row.lawyer_id is distinct from auth.uid() then
    raise exception 'Only the owner can change this appointment';
  end if;

  clean_title := nullif(trim(coalesce(title_value, '')), '');
  if clean_title is null then
    raise exception 'Title is required';
  end if;

  if starts_at_value is null or ends_at_value is null then
    raise exception 'Start and end are required';
  end if;

  if ends_at_value <= starts_at_value then
    raise exception 'End time must be after start time';
  end if;

  if public.lawyer_has_appointment_conflict(
    auth.uid(), starts_at_value, ends_at_value, appointment_id_value
  ) then
    raise exception 'Appointment overlaps an existing one';
  end if;

  clean_location := coalesce(nullif(trim(coalesce(location_value, '')), ''), 'A definir');
  clean_area := coalesce(nullif(trim(coalesce(area_value, '')), ''), '');
  -- Compromisso amarrado a um caso mantem o nome do cliente do caso; so os
  -- soltos aceitam counterpart livre.
  clean_counterpart := case
    when appointment_row.case_id is not null then appointment_row.counterpart_name
    else coalesce(nullif(trim(coalesce(counterpart_name_value, '')), ''), '')
  end;

  update public.appointments
  set
    title = clean_title,
    starts_at = starts_at_value,
    ends_at = ends_at_value,
    location = clean_location,
    area = clean_area,
    counterpart_name = clean_counterpart,
    updated_at = now()
  where id = appointment_id_value;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. cancel_appointment (soft: preserva historico e serve ao feed .ics futuro)
-- ---------------------------------------------------------------------------

create or replace function public.cancel_appointment(
  appointment_id_value uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  appointment_row public.appointments%rowtype;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  select * into appointment_row
  from public.appointments
  where id = appointment_id_value
  for update;

  if not found then
    raise exception 'Appointment not found';
  end if;

  if appointment_row.lawyer_id is distinct from auth.uid() then
    raise exception 'Only the owner can change this appointment';
  end if;

  update public.appointments
  set status = 'cancelled', updated_at = now()
  where id = appointment_id_value;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Grants
-- ---------------------------------------------------------------------------

revoke all on function public.lawyer_has_appointment_conflict(uuid, timestamptz, timestamptz, uuid) from public, anon;
revoke all on function public.create_appointment(text, timestamptz, timestamptz, text, text, text, uuid) from public, anon;
revoke all on function public.update_appointment(uuid, text, timestamptz, timestamptz, text, text, text) from public, anon;
revoke all on function public.cancel_appointment(uuid) from public, anon;

grant execute on function public.create_appointment(text, timestamptz, timestamptz, text, text, text, uuid) to authenticated;
grant execute on function public.update_appointment(uuid, text, timestamptz, timestamptz, text, text, text) to authenticated;
grant execute on function public.cancel_appointment(uuid) to authenticated;

notify pgrst, 'reload schema';
