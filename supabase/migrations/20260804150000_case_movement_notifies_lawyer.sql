-- Movimentação do processo avisa OS DOIS LADOS.
--
-- Antes, a sincronização do DataJud criava notificação só para o CLIENTE
-- (tipo 'case_update', escopo client). O advogado — que é quem age sobre a
-- movimentação — não recebia nada e só descobria abrindo o caso.
--
-- ARMADILHA (a mesma de lawyer_recommended): o sino filtra por ESCOPO e o
-- escopo deriva do TIPO em infer_notification_scope. Não dá para reusar
-- 'case_update' para o advogado — cairia no sino do cliente. Por isso tipo
-- novo 'case_movement', declarado com escopo lawyer abaixo.
--
-- O toque abre a PÁGINA DO CASO nos dois lados sem código novo: o metadata
-- leva case_id e nenhum conversation_id, e destinationFor() já resolve isso
-- para legalCase. Push idem — o trigger de push é central em notifications.

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
      'appointment_reminder',
      'case_movement'
    ) then 'lawyer'::public.notification_scope
    when type_value in ('firm_case_started') then 'firm'::public.notification_scope
    when type_value in (
      'case_request',
      'message',
      'case_update',
      'case_closed',
      'lawyer_recommendation'
    ) then 'client'::public.notification_scope
    else coalesce(current_scope, 'client'::public.notification_scope)
  end;
$$;

create or replace function public.ingest_case_movements(case_id_value uuid, cnj_value text, movements_value jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  case_row public.legal_cases%rowtype;
  expected_cnj text;
  is_first_sync boolean;
  inserted_count integer := 0;
  notable_count integer := 0;
begin
  select * into case_row from public.legal_cases where id = case_id_value;
  if not found then
    raise exception 'Case not found';
  end if;

  expected_cnj := nullif(
    regexp_replace(coalesce(cnj_value, ''), '[^0-9]', '', 'g'), '');

  if case_row.cnj_number is distinct from expected_cnj then
    return jsonb_build_object('skipped', 'cnj_changed');
  end if;

  is_first_sync := not exists (
    select 1 from public.case_movement_sync_state
    where case_id = case_id_value
  );

  -- Backfill: movimento gravado antes de existir a coluna situation continua
  -- com ''. Statement PROPRIO de proposito — se isso virasse `do update` no
  -- insert abaixo, o `returning` trataria movimento antigo como novo e
  -- dispararia notificacao de historico.
  update public.case_movements cm
  set situation = incoming.situation
  from (
    select
      (item->>'code')::integer as movement_code,
      (item->>'occurred_at')::timestamptz as occurred_at,
      coalesce(item->>'situation', '') as situation
    from jsonb_array_elements(coalesce(movements_value, '[]'::jsonb)) as item
    where item->>'code' ~ '^[0-9]{1,9}$'
      and pg_input_is_valid(item->>'occurred_at', 'timestamptz')
      and nullif(item->>'situation', '') is not null
  ) as incoming
  where cm.case_id = case_id_value
    and cm.movement_code = incoming.movement_code
    and cm.occurred_at = incoming.occurred_at
    and cm.situation = '';

  with incoming as (
    select
      (item->>'code')::integer as movement_code,
      left(coalesce(item->>'name', ''), 300) as movement_name,
      (item->>'occurred_at')::timestamptz as occurred_at,
      nullif(left(coalesce(item->>'orgao', ''), 200), '') as orgao,
      nullif(left(coalesce(item->>'tribunal', ''), 40), '') as tribunal,
      nullif(left(coalesce(item->>'grau', ''), 20), '') as grau,
      left(coalesce(item->>'situation', ''), 40) as situation
    from jsonb_array_elements(coalesce(movements_value, '[]'::jsonb)) as item
    where item->>'code' ~ '^[0-9]{1,9}$'
      -- dataHora podre no dado cru nao pode abortar o lote inteiro (o cast
      -- lancaria excecao, sync_state nunca gravaria e o caso viraria poison
      -- pill no topo da fila): item invalido e descartado como o code.
      and pg_input_is_valid(item->>'occurred_at', 'timestamptz')
  ),
  deduped as (
    select distinct on (movement_code, occurred_at)
      movement_code, movement_name, occurred_at, orgao, tribunal, grau,
      situation
    from incoming
    where movement_name <> ''
  ),
  ins as (
    insert into public.case_movements
      (case_id, movement_code, movement_name, occurred_at,
       orgao, tribunal, grau, situation)
    select
      case_id_value, movement_code, movement_name, occurred_at,
      orgao, tribunal, grau, situation
    from deduped
    on conflict (case_id, movement_code, occurred_at) do nothing
    returning movement_code, occurred_at, situation
  ),
  notable as (
    select i.occurred_at, t.title, t.body
    from ins i
    join lateral (
      select cmt.title, cmt.body, cmt.notify
      from public.case_movement_translations cmt
      where cmt.movement_code = i.movement_code
        and (cmt.situation = i.situation or cmt.situation = '')
      order by (cmt.situation = '')
      limit 1
    ) t on true
    where t.notify
  ),
  notif as (
    insert into public.notifications
      (recipient_profile_id, type, title, body, metadata, scope)
    select
      case_row.client_id,
      'case_update',
      'Seu processo andou',
      (select n.body from notable n order by n.occurred_at desc limit 1)
        || case
             when (select count(*) from notable) = 2
               then ' Há mais 1 movimentação nova no processo.'
             when (select count(*) from notable) > 2
               then ' Há mais ' || ((select count(*) from notable) - 1)
                 || ' movimentações novas no processo.'
             else ''
           end,
      jsonb_build_object(
        'case_id', case_id_value,
        'movement_count', (select count(*) from notable)
      ),
      'client'
    where exists (select 1 from notable)
      and not is_first_sync
    returning id
  ),
  -- O ADVOGADO responsável também é avisado. Tipo PRÓPRIO ('case_movement',
  -- escopo lawyer) porque o sino filtra por escopo e o escopo deriva do TIPO:
  -- reusar 'case_update' aqui jogaria o aviso do advogado no sino do cliente e
  -- ele nunca o veria. Mesma armadilha do lawyer_recommended.
  --
  -- Leva o TÍTULO do caso no corpo: o cliente tem um processo, o advogado tem
  -- dezenas — sem o título ele não sabe qual andou.
  --
  -- Só o responsável, não a firma inteira: movimentação é rotina (48 em 2
  -- processos no primeiro mês) e avisar todo mundo a cada andamento vira ruído
  -- que faz desligar o sino. O painel do escritório já mostra o caso.
  notif_lawyer as (
    insert into public.notifications
      (recipient_profile_id, type, title, body, metadata, scope)
    select
      case_row.assigned_lawyer_id,
      'case_movement',
      'Movimentação no processo',
      case_row.title || ': '
      || (select n.body from notable n order by n.occurred_at desc limit 1)
        || case
             when (select count(*) from notable) = 2
               then ' Há mais 1 movimentação nova no processo.'
             when (select count(*) from notable) > 2
               then ' Há mais ' || ((select count(*) from notable) - 1)
                 || ' movimentações novas no processo.'
             else ''
           end,
      jsonb_build_object(
        'case_id', case_id_value,
        'movement_count', (select count(*) from notable)
      ),
      'lawyer'
    where exists (select 1 from notable)
      and not is_first_sync
      and case_row.assigned_lawyer_id is not null
      -- Conta dupla (mesma pessoa é cliente e advogada do caso) receberia
      -- dois avisos do mesmo fato, um em cada sino.
      and case_row.assigned_lawyer_id is distinct from case_row.client_id
    returning id
  )
  select
    (select count(*) from ins),
    (select count(*) from notable)
  into inserted_count, notable_count;

  if notable_count > 0 and not is_first_sync then
    update public.legal_cases
    set last_update_label = (
      select t.title
      from public.case_movements cm
      join lateral (
        select cmt.title, cmt.notify
        from public.case_movement_translations cmt
        where cmt.movement_code = cm.movement_code
          and (cmt.situation = cm.situation or cmt.situation = '')
        order by (cmt.situation = '')
        limit 1
      ) t on true
      where cm.case_id = case_id_value and t.notify
      order by cm.occurred_at desc
      limit 1
    )
    where id = case_id_value;
  end if;

  insert into public.case_movement_sync_state (case_id, synced_at)
  values (case_id_value, now())
  on conflict (case_id) do update set synced_at = now();

  return jsonb_build_object(
    'inserted', inserted_count,
    'first_sync', is_first_sync,
    'notified', notable_count > 0 and not is_first_sync
  );
end;
$function$
;

notify pgrst, 'reload schema';
