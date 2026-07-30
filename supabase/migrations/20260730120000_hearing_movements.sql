-- Audiencias na timeline, com o status real (marcada / remarcada / cancelada)
--
-- Achado no processo real do Samuel (TRT4, 29/07): 14 movimentos de audiencia
-- invisiveis na timeline, porque a curadoria so tinha o codigo generico 970.
-- Na arvore TPU cada TIPO de audiencia e um codigo proprio (12740 conciliacao,
-- 12749 instrucao, 12750 instrucao e julgamento, ...) e o `nome` que o DataJud
-- devolve e so a FOLHA ("de Instrucao"), sem a palavra "Audiencia".
--
-- E o dado cru traz algo melhor: o complemento `situacao_da_audiencia` diz se
-- a audiencia foi designada, redesignada, cancelada, realizada ou nao
-- realizada. "Audiencia cancelada" e "Audiencia marcada" sao noticias
-- opostas para o cliente — mostrar so "Audiencia" seria pior que util.
--
-- ARMADILHA verificada nos dados (TJRS): o mesmo complemento as vezes carrega
-- o TIPO da audiencia em vez do status (valores 17=conciliacao, 22=instrucao,
-- 23=instrucao e julgamento, 25=preliminar, 92=mediacao). Por isso a Edge
-- Function so aceita os `valor` que sao status de verdade (9, 10, 11, 13, 14);
-- qualquer outra coisa cai na linha generica do codigo.
--
-- Estrutura: a traducao passa a ser chaveada por (codigo, situacao), com
-- situacao '' = linha generica do codigo. Continua sendo a FONTE UNICA: ampliar
-- cobertura segue sendo INSERT, sem release do app.

-- ---------------------------------------------------------------------------
-- 1. Situacao no movimento e na traducao ('' = sem situacao / generico)
-- ---------------------------------------------------------------------------

alter table public.case_movements
  add column if not exists situation text not null default '';

alter table public.case_movement_translations
  add column if not exists situation text not null default '';

alter table public.case_movement_translations
  drop constraint if exists case_movement_translations_pkey;

alter table public.case_movement_translations
  add primary key (movement_code, situation);

-- ---------------------------------------------------------------------------
-- 2. Curadoria da familia de audiencia
--
-- Codigos e situacoes levantados empiricamente na API publica do DataJud em
-- 30/07/2026 (TRT4 e TJRS). O cross join gera as combinacoes a partir de duas
-- listas curtas — manter as listas, nao as 60 linhas.
-- ---------------------------------------------------------------------------

with hearing_codes as (
  select * from (values
    (970,   'Audiência', null::text),
    (12740, 'Audiência', 'de conciliação'),
    (12743, 'Audiência', 'de interrogatório'),
    (12747, 'Audiência', 'inicial'),
    (12749, 'Audiência', 'de instrução'),
    (12750, 'Audiência', 'de instrução e julgamento'),
    (12751, 'Audiência', 'de julgamento'),
    (12752, 'Audiência', 'de mediação'),
    (12753, 'Audiência', 'preliminar'),
    (313,   'Sessão',    'do tribunal do júri')
  ) as t(code, noun, label)
),
hearing_situations as (
  select * from (values
    -- A data da audiencia NAO vem no dado (o complemento so traz o status),
    -- entao o texto manda confirmar com o advogado em vez de fingir saber.
    ('designada',     'marcada',       'foi marcada',      ' Confirme a data com o seu advogado.', true),
    ('redesignada',   'remarcada',     'foi remarcada',    ' Confirme a nova data com o seu advogado.', true),
    ('cancelada',     'cancelada',     'foi cancelada',    '', true),
    ('nao_realizada', 'não realizada', 'não foi realizada', '', true),
    -- Realizada: o cliente estava la; entra na timeline como registro, sem push.
    ('realizada',     'realizada',     'foi realizada',    '', false)
  ) as t(situation, title_word, body_verb, suffix, notify)
)
insert into public.case_movement_translations
  (movement_code, situation, title, body, notify)
select
  c.code,
  s.situation,
  concat_ws(' ', c.noun, s.title_word),
  'A ' || lower(concat_ws(' ', c.noun, c.label)) || ' ' || s.body_verb || '.'
    || s.suffix,
  s.notify
from hearing_codes c
cross join hearing_situations s
on conflict (movement_code, situation) do update set
  title = excluded.title,
  body = excluded.body,
  notify = excluded.notify;

-- Linha generica de cada codigo: usada quando o complemento nao veio, veio
-- ilegivel ou trazia o tipo em vez do status.
insert into public.case_movement_translations
  (movement_code, situation, title, body, notify)
select
  c.code,
  '',
  c.noun,
  'O processo registrou uma ' || lower(concat_ws(' ', c.noun, c.label)) || '.',
  true
from (values
  (970,   'Audiência', null::text),
  (12740, 'Audiência', 'de conciliação'),
  (12743, 'Audiência', 'de interrogatório'),
  (12747, 'Audiência', 'inicial'),
  (12749, 'Audiência', 'de instrução'),
  (12750, 'Audiência', 'de instrução e julgamento'),
  (12751, 'Audiência', 'de julgamento'),
  (12752, 'Audiência', 'de mediação'),
  (12753, 'Audiência', 'preliminar'),
  (313,   'Sessão',    'do tribunal do júri')
) as c(code, noun, label)
on conflict (movement_code, situation) do update set
  title = excluded.title,
  body = excluded.body,
  notify = excluded.notify;

-- ---------------------------------------------------------------------------
-- 3. Leitura da timeline: traducao mais especifica primeiro, colapsando
--    repeticao do mesmo titulo no mesmo dia.
--
--    O colapso nasceu do dado real: no processo do TRT4 o cartorio registrou
--    QUATRO "Audiencia cancelada" em cinco minutos, mais marcada e realizada
--    no mesmo dia. Isso e escrituracao interna do cartorio; para o cliente,
--    seis linhas quase iguais sao ruido. Os movimentos crus continuam todos
--    gravados — o colapso e so da leitura.
-- ---------------------------------------------------------------------------

create or replace function public.fetch_case_movements(case_id_value uuid)
returns table (
  id uuid,
  movement_code integer,
  title text,
  body text,
  occurred_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    collapsed.id,
    collapsed.movement_code,
    collapsed.title,
    collapsed.body,
    collapsed.occurred_at
  from (
    select distinct on (t.title, cm.occurred_at::date)
      cm.id,
      cm.movement_code,
      t.title,
      t.body,
      cm.occurred_at
    from public.case_movements cm
    join lateral (
      select cmt.title, cmt.body
      from public.case_movement_translations cmt
      where cmt.movement_code = cm.movement_code
        and (cmt.situation = cm.situation or cmt.situation = '')
      order by (cmt.situation = '')
      limit 1
    ) t on true
    where cm.case_id = case_id_value
      and public.can_access_case(case_id_value)
    -- Dentro do dia, sobrevive o registro mais recente daquele titulo.
    order by t.title, cm.occurred_at::date, cm.occurred_at desc
  ) collapsed
  order by collapsed.occurred_at desc;
$$;

revoke all on function public.fetch_case_movements(uuid) from public, anon;
grant execute on function public.fetch_case_movements(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Ingestao ciente da situacao
--    Corpo verbatim da 20260729150000 com tres mudancas cirurgicas:
--    (a) le `situation` do payload, (b) backfill da situacao em movimento ja
--    gravado (statement separado, para nao entrar no `ins` e disparar
--    notificacao de historico), (c) joins de traducao por especificidade.
-- ---------------------------------------------------------------------------

create or replace function public.ingest_case_movements(
  case_id_value uuid,
  cnj_value text,
  movements_value jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all on function public.ingest_case_movements(uuid, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.ingest_case_movements(uuid, text, jsonb)
  to service_role;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Verificacao pos-push (SQL Editor):
--   select count(*) from case_movement_translations;              -- 15 + 60
--   select title, body from case_movement_translations
--   where movement_code = 12749 order by situation;
--   -- apos a proxima sincronizacao, as audiencias aparecem com status:
--   select movement_code, situation, count(*) from case_movements
--   group by 1,2 order by 1;
-- ---------------------------------------------------------------------------
