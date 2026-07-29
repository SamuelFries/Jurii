-- Andamento processual automatico via DataJud (CNJ) - fundacao
--
-- O advogado/escritorio informa o numero CNJ do processo no caso; um job
-- periodico consulta a API publica do DataJud e grava os movimentos (codigo
-- TPU + data + nome) em case_movements. A timeline do app mostra SO os
-- movimentos com traducao curada em case_movement_translations (o resto e
-- ruido processual); os traduzidos com notify=true geram notificacao ao
-- CLIENTE (tipo 'case_update', ja declarado com escopo client e com icone no
-- sino desde a baseline - reservado e nunca usado ate aqui; push e realtime
-- vem de graca pelos triggers/publication existentes).
--
-- Decisoes de produto (conversa de 29/07):
--   - Numero CNJ e OPCIONAL (muitos casos nunca viram processo judicial) e so
--     advogado/escritorio preenche (predicado can_manage_case_updates).
--   - Timeline vazia e estado NORMAL (processo em segredo de justica nao
--     aparece no indice publico do DataJud - la so ha nivelSigilo=0).
--   - Traducao mora NUM SO LUGAR (esta tabela); ampliar cobertura de codigos
--     = INSERT aqui, sem release do app. Codigos verificados empiricamente
--     contra dados reais do DataJud em 29/07 (TJRS/TRT4/TRF4/STJ/TST).
--
-- Seguranca:
--   - legal_cases tinha INSERT/UPDATE de tabela inteira para authenticated
--     (nunca passou pelo hardening). Convertido para grants POR COLUNA sem
--     cnj_number: o numero so entra pela RPC set_case_cnj_number, que valida
--     digito verificador e papel. Colunas de posse (client_id/law_firm_id/
--     assigned_lawyer_id) tambem ficam fora do UPDATE direto.
--   - case_movements: escrita exclusiva do job (RPCs service_role only);
--     leitura pela regra do caso (can_access_case).

-- ---------------------------------------------------------------------------
-- 1. Validador de numero CNJ (Res. CNJ 65/2008: NNNNNNN-DD.AAAA.J.TR.OOOO)
--
-- Espelha o validador do app (lib/utils/validators.dart, isValidCnj).
-- Verificacao mod 97 estilo ISO 7064: para o numero valido,
-- mod97(NNNNNNN || AAAA || J || TR || OOOO || DD) = 1.
-- ---------------------------------------------------------------------------

create or replace function public.is_valid_cnj(cnj_value text)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  digits text;
  rearranged text;
begin
  digits := regexp_replace(coalesce(cnj_value, ''), '[^0-9]', '', 'g');

  if length(digits) <> 20 then
    return false;
  end if;

  -- Posicoes: NNNNNNN(1-7) DD(8-9) AAAA(10-13) J(14) TR(15-16) OOOO(17-20).
  rearranged := substr(digits, 1, 7) || substr(digits, 10, 11)
    || substr(digits, 8, 2);

  return (rearranged::numeric % 97) = 1;
end;
$$;

revoke all on function public.is_valid_cnj(text) from public, anon;
grant execute on function public.is_valid_cnj(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Coluna do numero no caso + CHECK de formato
-- ---------------------------------------------------------------------------

alter table public.legal_cases
  add column if not exists cnj_number text;

alter table public.legal_cases
  drop constraint if exists legal_cases_cnj_number_valid;

alter table public.legal_cases
  add constraint legal_cases_cnj_number_valid
  check (
    cnj_number is null
    or (cnj_number ~ '^[0-9]{20}$' and public.is_valid_cnj(cnj_number))
  );

-- Grants por coluna: o app nao usa escrita direta em legal_cases (tudo por
-- RPC), mas o grant de tabela inteira existia desde a baseline. A partir de
-- agora, escrita direta nao alcanca cnj_number (so via RPC) nem as colunas de
-- posse no UPDATE. As RPCs SECURITY DEFINER (respond_to_case_request,
-- assign_law_firm_case, add_case_update) nao dependem destes grants.
revoke insert, update on public.legal_cases from authenticated;

grant insert (
  title, area, status, client_id, law_firm_id, assigned_lawyer_id,
  description, last_update_label, deadline_at
) on public.legal_cases to authenticated;

grant update (
  title, area, status, description, last_update_label, deadline_at
) on public.legal_cases to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Movimentos do processo (dados crus do DataJud)
--
-- Guardamos TODOS os movimentos retornados (baratos, e permitem ampliar a
-- curadoria depois sem re-consultar); a UI le so os traduzidos.
-- Dedup: o DataJud devolve duplicatas exatas e um documento por instancia do
-- mesmo processo (o indice do STJ inclui o historico de origem) - a unique
-- (case_id, movement_code, occurred_at) absorve os dois casos.
-- ---------------------------------------------------------------------------

create table if not exists public.case_movements (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references public.legal_cases(id) on delete cascade,
  movement_code integer not null,
  movement_name text not null,
  occurred_at timestamptz not null,
  orgao text,
  tribunal text,
  grau text,
  created_at timestamptz not null default now()
);

create unique index if not exists case_movements_dedup_idx
  on public.case_movements(case_id, movement_code, occurred_at);

create index if not exists case_movements_case_occurred_idx
  on public.case_movements(case_id, occurred_at desc);

alter table public.case_movements enable row level security;

drop policy if exists case_movements_select_related on public.case_movements;
create policy case_movements_select_related
on public.case_movements for select
to authenticated
using (public.can_access_case(case_movements.case_id));

-- Sem policy nem grant de escrita: so o job grava, via RPC definer.
grant select on public.case_movements to authenticated;

-- Estado de sincronizacao em tabela propria (nao em legal_cases) de proposito:
-- o trigger legal_cases_set_updated_at bumparia updated_at a cada passada do
-- job, reordenando as listas de casos diariamente sem mudanca real.
create table if not exists public.case_movement_sync_state (
  case_id uuid primary key references public.legal_cases(id) on delete cascade,
  synced_at timestamptz not null default now()
);

alter table public.case_movement_sync_state enable row level security;
-- Sem policies e sem grants: tabela interna do job (RPCs definer/service_role).

-- ---------------------------------------------------------------------------
-- 4. Traducao curada: codigo TPU -> frase para o cliente leigo
--
-- FONTE UNICA da curadoria (timeline e notificacao decidem por aqui).
-- notify=false = aparece na timeline mas nao gera notificacao (ex.: conclusao,
-- que e frequente demais para avisar).
-- Codigos confirmados em dados reais do DataJud em 29/07/2026; 221 e 237
-- entram por serem os pares diretos de familia dos confirmados 219/220/239.
-- ---------------------------------------------------------------------------

create table if not exists public.case_movement_translations (
  movement_code integer primary key,
  title text not null,
  body text not null,
  notify boolean not null default false
);

alter table public.case_movement_translations enable row level security;

drop policy if exists case_movement_translations_read
  on public.case_movement_translations;
create policy case_movement_translations_read
on public.case_movement_translations for select
to authenticated
using (true);

grant select on public.case_movement_translations to authenticated;

insert into public.case_movement_translations
  (movement_code, title, body, notify)
values
  (26, 'Processo distribuído',
   'O processo foi registrado na Justiça e encaminhado a um juízo.', true),
  (970, 'Audiência',
   'O processo registrou uma movimentação de audiência.', true),
  (123, 'Processo enviado a outra instância',
   'O processo foi remetido a outro órgão da Justiça.', true),
  (982, 'Processo enviado a outra instância',
   'O processo foi remetido a outro órgão da Justiça.', true),
  (219, 'Saiu uma decisão',
   'O pedido foi julgado procedente. Fale com seu advogado para entender os efeitos.', true),
  (220, 'Saiu uma decisão',
   'O pedido foi julgado improcedente. Fale com seu advogado para entender os próximos passos.', true),
  (221, 'Saiu uma decisão',
   'O pedido foi julgado parcialmente procedente. Fale com seu advogado para entender os efeitos.', true),
  (466, 'Acordo homologado',
   'Um acordo foi homologado no processo.', true),
  (237, 'Recurso julgado',
   'O recurso foi provido. Fale com seu advogado para entender os efeitos.', true),
  (239, 'Recurso julgado',
   'O recurso não foi provido. Fale com seu advogado para entender os próximos passos.', true),
  (848, 'Decisão definitiva',
   'A decisão se tornou definitiva: não cabe mais recurso.', true),
  (196, 'Execução encerrada',
   'A fase de execução do processo foi encerrada.', true),
  (22, 'Processo baixado',
   'O processo foi baixado definitivamente.', true),
  (246, 'Processo arquivado',
   'O processo foi arquivado definitivamente.', true),
  (51, 'Com o juiz para análise',
   'O processo está concluso, aguardando análise do juiz.', false)
on conflict (movement_code) do update set
  title = excluded.title,
  body = excluded.body,
  notify = excluded.notify;

-- ---------------------------------------------------------------------------
-- 5. RPCs do app
-- ---------------------------------------------------------------------------

-- Quem preenche o numero: o advogado do caso (can_manage_case_updates, o
-- mesmo predicado do "Atualizar": advogado atribuido ou participante com role
-- lawyer) OU um gestor ativo do escritorio do caso (dono/admin/secretaria,
-- via is_active_law_firm_case_manager, o mesmo gate de assign_law_firm_case).
-- Na pratica quem cadastra numero de processo num escritorio e a secretaria.
-- Cliente NAO passa.
create or replace function public.set_case_cnj_number(
  case_id_value uuid,
  cnj_value text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_cnj text;
  case_row public.legal_cases%rowtype;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  if not (
    public.can_manage_case_updates(case_id_value)
    or exists (
      select 1
      from public.legal_cases lc
      where lc.id = case_id_value
        and lc.law_firm_id is not null
        and public.is_active_law_firm_case_manager(lc.law_firm_id)
    )
  ) then
    raise exception 'Only professionals assigned to this case can set the case number';
  end if;

  clean_cnj := nullif(
    regexp_replace(coalesce(cnj_value, ''), '[^0-9]', '', 'g'), '');

  -- Limpar o numero e intencional SO via null/em branco. Texto sem nenhum
  -- digito ("abc", payload corrompido) e erro, nao limpeza: senao uma chamada
  -- malformada apagaria a timeline acumulada em silencio.
  if cnj_value is not null and btrim(cnj_value) <> '' and clean_cnj is null then
    raise exception 'Invalid CNJ case number';
  end if;

  if clean_cnj is not null and not public.is_valid_cnj(clean_cnj) then
    raise exception 'Invalid CNJ case number';
  end if;

  select * into case_row
  from public.legal_cases
  where id = case_id_value
  for update;

  if not found then
    raise exception 'Case not found';
  end if;

  if case_row.cnj_number is distinct from clean_cnj then
    -- Numero mudou (ou foi limpo): os movimentos gravados pertencem ao numero
    -- antigo; zera para o job repovoar do zero.
    delete from public.case_movements where case_id = case_id_value;
    delete from public.case_movement_sync_state where case_id = case_id_value;

    update public.legal_cases
    set cnj_number = clean_cnj
    where id = case_id_value;
  end if;
end;
$$;

revoke all on function public.set_case_cnj_number(uuid, text)
  from public, anon;
grant execute on function public.set_case_cnj_number(uuid, text)
  to authenticated;

-- Timeline traduzida (so movimentos curados; ruido processual fica fora).
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
    cm.id,
    cm.movement_code,
    cmt.title,
    cmt.body,
    cm.occurred_at
  from public.case_movements cm
  join public.case_movement_translations cmt
    on cmt.movement_code = cm.movement_code
  where cm.case_id = case_id_value
    and public.can_access_case(case_id_value)
  order by cm.occurred_at desc;
$$;

revoke all on function public.fetch_case_movements(uuid) from public, anon;
grant execute on function public.fetch_case_movements(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. RPCs de leitura de casos ganham cnj_number (+ needs_cnj_number nos
--    paineis profissionais: tem prazo e ainda nao tem numero).
--    Corpos VERBATIM das definicoes vigentes (fetch_client_cases baseline
--    :2534, fetch_lawyer_cases baseline :9682, fetch_law_firm_cases baseline
--    :11298), so com as colunas novas. Assinatura muda -> drop + create +
--    re-emissao dos grants.
-- ---------------------------------------------------------------------------

drop function if exists public.fetch_client_cases();

create function public.fetch_client_cases()
returns table (
  id uuid,
  title text,
  area text,
  status text,
  status_label text,
  last_update_label text,
  cnj_number text,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    lc.id,
    lc.title,
    lc.area,
    lc.status::text as status,
    public.case_status_label(lc.status) as status_label,
    coalesce(lc.last_update_label, 'Atualizado hoje') as last_update_label,
    lc.cnj_number,
    lc.updated_at
  from public.legal_cases lc
  where lc.client_id = auth.uid()
  order by lc.updated_at desc;
$$;

revoke all on function public.fetch_client_cases()
  from public, anon, authenticated;
grant execute on function public.fetch_client_cases() to authenticated;

drop function if exists public.fetch_lawyer_cases();

create function public.fetch_lawyer_cases()
returns table (
  id uuid,
  title text,
  client_name text,
  client_initials text,
  area text,
  last_update_label text,
  status text,
  cnj_number text,
  needs_cnj_number boolean,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select distinct
    lc.id,
    lc.title,
    public.profile_display_name(
      client_profile.full_name,
      client_profile.deleted_display_name,
      client_profile.deleted_at
    ) as client_name,
    coalesce(client_profile.initials, 'CL') as client_initials,
    lc.area,
    coalesce(lc.last_update_label, 'Atualizado hoje') as last_update_label,
    lc.status::text as status,
    lc.cnj_number,
    (lc.deadline_at is not null and lc.cnj_number is null) as needs_cnj_number,
    lc.updated_at
  from public.legal_cases lc
  left join public.profiles client_profile
    on client_profile.id = lc.client_id
  where lc.assigned_lawyer_id = auth.uid()
     or exists (
      select 1
      from public.case_participants cp
      where cp.case_id = lc.id
        and cp.profile_id = auth.uid()
        and cp.role in ('lawyer', 'firm_member')
     )
  order by lc.updated_at desc;
$$;

revoke all on function public.fetch_lawyer_cases()
  from public, anon, authenticated;
grant execute on function public.fetch_lawyer_cases() to authenticated;

drop function if exists public.fetch_law_firm_cases(uuid);

create function public.fetch_law_firm_cases(
  law_firm_id_value uuid
)
returns table (
  id uuid,
  title text,
  client_name text,
  client_initials text,
  assigned_lawyer_id uuid,
  assigned_lawyer text,
  area text,
  status_label text,
  next_step text,
  urgent boolean,
  cnj_number text,
  needs_cnj_number boolean,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  with viewer as (
    select lfm.profile_id, lfm.roles
    from public.law_firm_members lfm
    where lfm.law_firm_id = law_firm_id_value
      and lfm.profile_id = auth.uid()
      and lfm.status = 'active'
    limit 1
  ),
  scoped_cases as (
    select lc.*
    from public.legal_cases lc
    where lc.law_firm_id = law_firm_id_value
      and exists (select 1 from viewer)
      and (
        exists (
          select 1
          from viewer
          where roles && array['owner', 'admin', 'secretary']::text[]
        )
        or lc.assigned_lawyer_id = auth.uid()
        or exists (
          select 1
          from public.case_participants cp
          where cp.case_id = lc.id
            and cp.profile_id = auth.uid()
        )
      )
  )
  select
    sc.id,
    sc.title,
    public.profile_display_name(
      client_profile.full_name,
      client_profile.deleted_at,
      client_profile.deleted_display_name
    ) as client_name,
    coalesce(client_profile.initials, 'CL') as client_initials,
    sc.assigned_lawyer_id,
    case
      when lawyer_profile.id is null then 'Sem advogado definido'
      else public.profile_display_name(
        lawyer_profile.full_name,
        lawyer_profile.deleted_at,
        lawyer_profile.deleted_display_name
      )
    end as assigned_lawyer,
    sc.area,
    public.case_status_label(sc.status) as status_label,
    coalesce(sc.last_update_label, 'Atualizado hoje') as next_step,
    sc.status = 'deadline' as urgent,
    sc.cnj_number,
    (sc.deadline_at is not null and sc.cnj_number is null) as needs_cnj_number,
    sc.updated_at
  from scoped_cases sc
  left join public.profiles client_profile
    on client_profile.id = sc.client_id
  left join public.profiles lawyer_profile
    on lawyer_profile.id = sc.assigned_lawyer_id
  order by sc.updated_at desc;
$$;

revoke all on function public.fetch_law_firm_cases(uuid)
  from public, anon, authenticated;
grant execute on function public.fetch_law_firm_cases(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. RPCs do job (service_role only - a Edge Function nao tem SELECT direto
--    nas tabelas pos-hardening; leitura/escrita sempre por RPC definer)
-- ---------------------------------------------------------------------------

create or replace function public.fetch_cases_for_movement_sync(
  batch_size integer default 4
)
returns table (case_id uuid, cnj_number text)
language sql
stable
security definer
set search_path = public
as $$
  select lc.id, lc.cnj_number
  from public.legal_cases lc
  left join public.case_movement_sync_state s on s.case_id = lc.id
  where lc.cnj_number is not null
    and (s.synced_at is null or s.synced_at < now() - interval '20 hours')
  order by s.synced_at asc nulls first
  limit greatest(1, least(coalesce(batch_size, 4), 20));
$$;

revoke all on function public.fetch_cases_for_movement_sync(integer)
  from public, anon, authenticated;
grant execute on function public.fetch_cases_for_movement_sync(integer)
  to service_role;

-- Ingestao idempotente: insere so o que e novo (unique absorve duplicata),
-- notifica o cliente UMA vez por passada (agregando os movimentos relevantes
-- novos) e atualiza o last_update_label do caso. Tudo que decide notificacao
-- vem da tabela de traducao (notify=true).
--
-- cnj_value = o numero que o job DE FATO consultou no DataJud: se o advogado
-- trocou o numero do caso durante a janela da consulta (minutos, latencia
-- alta), o ingest tardio vira NO-OP sem tocar sync_state — senao gravaria
-- movimentos do processo antigo sob o numero novo e notificaria o cliente
-- sobre processo que nao e mais o dele.
--
-- Primeira passada de um numero = BACKFILL de historico: grava tudo mas NAO
-- notifica nem mexe no label ("Seu processo andou" sobre sentenca de 2 anos
-- atras seria mentira). So passadas incrementais notificam.
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

  with incoming as (
    select
      (item->>'code')::integer as movement_code,
      left(coalesce(item->>'name', ''), 300) as movement_name,
      (item->>'occurred_at')::timestamptz as occurred_at,
      nullif(left(coalesce(item->>'orgao', ''), 200), '') as orgao,
      nullif(left(coalesce(item->>'tribunal', ''), 40), '') as tribunal,
      nullif(left(coalesce(item->>'grau', ''), 20), '') as grau
    from jsonb_array_elements(coalesce(movements_value, '[]'::jsonb)) as item
    where item->>'code' ~ '^[0-9]{1,9}$'
      -- dataHora podre no dado cru nao pode abortar o lote inteiro (o cast
      -- lancaria excecao, sync_state nunca gravaria e o caso viraria poison
      -- pill no topo da fila): item invalido e descartado como o code.
      and pg_input_is_valid(item->>'occurred_at', 'timestamptz')
  ),
  deduped as (
    select distinct on (movement_code, occurred_at)
      movement_code, movement_name, occurred_at, orgao, tribunal, grau
    from incoming
    where movement_name <> ''
  ),
  ins as (
    insert into public.case_movements
      (case_id, movement_code, movement_name, occurred_at,
       orgao, tribunal, grau)
    select
      case_id_value, movement_code, movement_name, occurred_at,
      orgao, tribunal, grau
    from deduped
    on conflict (case_id, movement_code, occurred_at) do nothing
    returning movement_code, occurred_at
  ),
  notable as (
    select i.occurred_at, t.title, t.body
    from ins i
    join public.case_movement_translations t
      on t.movement_code = i.movement_code
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
      join public.case_movement_translations t
        on t.movement_code = cm.movement_code
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

-- ---------------------------------------------------------------------------
-- 8. Disparo periodico: pg_cron -> Edge Function sync-case-movements (pg_net)
--
-- Mesmo padrao do push: URL e segredo dedicado vem do Vault
-- (case_sync_hook_url / case_sync_hook_secret, populados so em producao).
-- Sem os secrets o dispatch e NO-OP - a migration pode ir a prod antes do
-- deploy da Edge Function sem quebrar nada.
-- ---------------------------------------------------------------------------

create extension if not exists pg_net;

create or replace function public.dispatch_case_movement_sync()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  fn_url text;
  hook_secret text;
begin
  select decrypted_secret into fn_url
  from vault.decrypted_secrets where name = 'case_sync_hook_url';

  select decrypted_secret into hook_secret
  from vault.decrypted_secrets where name = 'case_sync_hook_secret';

  if fn_url is null or hook_secret is null then
    return;
  end if;

  perform net.http_post(
    url := fn_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || hook_secret
    ),
    body := '{}'::jsonb
  );
end;
$$;

revoke all on function public.dispatch_case_movement_sync()
  from public, anon, authenticated;

-- O indice publico do DataJud atualiza a cada poucos dias; 1x/hora com lote
-- pequeno cobre a fila com folga (cada caso re-sincroniza no maximo 1x/20h).
-- cron.schedule faz upsert por nome: reaplicar nao duplica o job.
create extension if not exists pg_cron;

select cron.schedule(
  'case-movement-sync',
  '7 * * * *',
  $cron$select public.dispatch_case_movement_sync();$cron$
);

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Verificacao pos-push (SQL Editor):
--   select public.is_valid_cnj('0000842-67.2023.8.21.7000');       -- true
--   select public.is_valid_cnj('00008426720238217001');            -- false
--   select count(*) from public.case_movement_translations;        -- 15
--   select jobname, schedule from cron.job
--     where jobname = 'case-movement-sync';
--   \df+ public.fetch_case_movements
--   select column_name, privilege_type
--   from information_schema.column_privileges
--   where table_name = 'legal_cases' and grantee = 'authenticated'
--   order by column_name, privilege_type;  -- sem cnj_number
-- ---------------------------------------------------------------------------
