-- Alcance na descoberta: o numero que sustenta a cobranca do patrocinio.
--
-- O destaque pago existe desde a 20260721120000, e ate hoje ninguem sabe se
-- ele funciona — nao ha uma tabela de evento no banco inteiro. Sem isso nao da
-- para precificar (quanto vale?), nao da para vender (quantas pessoas eu
-- alcanco?) e nao da para renovar (o que eu ganhei no mes?). Esta migration
-- cria a medicao; a cobranca vem depois, e so depois de existir numero.
--
-- TRES EVENTOS, E CADA UM VEM DE ONDE E MAIS BARATO E MAIS CONFIAVEL:
--
--   impressao      registrada pelo app apos a lista renderizar, via
--                  log_discovery_events. Poderia ser gravada dentro do RPC de
--                  descoberta, mas aquela funcao ja foi reescrita tres vezes e
--                  cada reescrita e risco; alem disso "apareceu na tela" e
--                  mais honesto que "foi devolvido pela consulta".
--
--   visita         mesmo caminho da impressao.
--
--   conversa       NAO e registrada. Ja existe em public.conversations, com
--                  lawyer_id/law_firm_id e created_at — contar de la e
--                  impossivel de falsear e nao custa escrita nenhuma. Evento
--                  que da para derivar nao se grava.
--
-- POR QUE O APP PODER ESCREVER NAO VIRA NUMERO INFLADO: a chave primaria e
-- (dia, tipo de evento, alvo, quem viu). Chamar mil vezes no mesmo dia grava
-- UMA linha. O que a tabela mede, portanto, nao e "quantas vezes apareci" e
-- sim "quantas PESSOAS DIFERENTES me alcancaram por dia" — que por acaso e a
-- metrica que se vende melhor, porque impressao repetida do mesmo usuario
-- nunca foi cliente novo.

create table if not exists public.discovery_events (
  day date not null default (now() at time zone 'utc')::date,
  event_type text not null check (event_type in ('impression', 'profile_view')),
  target_type text not null check (target_type in ('lawyer', 'law_firm')),
  target_id uuid not null,
  viewer_id uuid not null references public.profiles(id) on delete cascade,
  -- Ocupou uma VAGA PAGA naquele dia. Diferente de "tem destaque ativo": quem
  -- paga tambem aparece organicamente quando as duas vagas ja estao tomadas, e
  -- separar os dois e o que responde se a VAGA entrega alguma coisa.
  sponsored boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (day, event_type, target_type, target_id, viewer_id)
);

create index if not exists discovery_events_target_day_idx
  on public.discovery_events (target_type, target_id, day desc);

-- A chave primaria comeca por (dia, tipo) e nao serve a exclusao em cascata
-- por viewer_id: sem este indice, apagar uma conta varre a tabela inteira de
-- eventos — que e justamente a tabela que mais cresce do banco.
create index if not exists discovery_events_viewer_idx
  on public.discovery_events (viewer_id);

alter table public.discovery_events enable row level security;

-- Esta tabela diz QUEM olhou QUEM. Nenhuma leitura direta, por ninguem: o
-- painel do profissional recebe contagem agregada por RPC, e em nenhum lugar
-- a identidade de quem viu sai daqui. Duas camadas, como nas outras tabelas
-- sensiveis do projeto.
revoke all on table public.discovery_events from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 1. Registro (chamado pelo app)
-- ---------------------------------------------------------------------------

create or replace function public.log_discovery_events(
  event_type_value text,
  target_type_value text,
  target_ids_value uuid[],
  sponsored_ids_value uuid[] default null
)
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  clean_ids uuid[];
  sponsored_ids uuid[];
  gravados integer;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if event_type_value not in ('impression', 'profile_view') then
    raise exception 'Invalid event type';
  end if;

  if target_type_value not in ('lawyer', 'law_firm') then
    raise exception 'Invalid target type';
  end if;

  select array_agg(distinct target_id)
  into clean_ids
  from unnest(coalesce(target_ids_value, array[]::uuid[])) as ids(target_id)
  where target_id is not null;

  clean_ids := coalesce(clean_ids, array[]::uuid[]);
  if cardinality(clean_ids) = 0 then
    return 0;
  end if;

  -- Uma pagina de descoberta tem 6 a 20 cartoes. O teto e folgado e existe so
  -- para a chamada nao virar insercao em massa vinda de fora do app.
  if cardinality(clean_ids) > 100 then
    raise exception 'Too many targets';
  end if;

  sponsored_ids := coalesce(sponsored_ids_value, array[]::uuid[]);

  insert into public.discovery_events (
    event_type, target_type, target_id, viewer_id, sponsored
  )
  select
    event_type_value,
    target_type_value,
    target_id,
    auth.uid(),
    target_id = any(sponsored_ids)
  from unnest(clean_ids) as ids(target_id)
  -- O proprio profissional navegando no app nao conta como alcance: ele veria
  -- o proprio numero subir so de olhar o proprio cartao.
  where target_id is distinct from auth.uid()
  on conflict (day, event_type, target_type, target_id, viewer_id)
  -- Se em algum momento do dia a pessoa apareceu numa vaga paga, o dia conta
  -- como pago: e a leitura otimista, e a unica que nao apaga a informacao.
  do update set sponsored = public.discovery_events.sponsored or excluded.sponsored;

  get diagnostics gravados = row_count;
  return gravados;
end;
$$;

revoke all on function public.log_discovery_events(text, text, uuid[], uuid[])
from public, anon;
grant execute on function public.log_discovery_events(text, text, uuid[], uuid[])
to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Painel: o profissional ve o proprio alcance
--
--    So contagem. A identidade de quem viu nao sai desta funcao.
-- ---------------------------------------------------------------------------

create or replace function public.fetch_professional_reach(
  target_type_value text,
  target_id_value uuid,
  days_value integer default 30
)
returns table (
  day date,
  reach integer,
  sponsored_reach integer,
  profile_views integer,
  conversations integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  janela integer := least(greatest(coalesce(days_value, 30), 1), 180);
  autorizado boolean;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  -- Cada um ve o proprio numero. Escritorio: quem fala pelo escritorio
  -- (dono/admin), o mesmo portao da edicao da descricao.
  autorizado := case
    when target_type_value = 'lawyer' then target_id_value = auth.uid()
    when target_type_value = 'law_firm' then
      public.is_active_law_firm_manager(target_id_value)
    else false
  end;

  if not autorizado then
    raise exception 'Not allowed';
  end if;

  return query
  with dias as (
    select generate_series(
      (now() at time zone 'utc')::date - (janela - 1),
      (now() at time zone 'utc')::date,
      interval '1 day'
    )::date as day
  ),
  eventos as (
    select
      e.day,
      count(*) filter (where e.event_type = 'impression')::integer as reach,
      count(*) filter (
        where e.event_type = 'impression' and e.sponsored
      )::integer as sponsored_reach,
      count(*) filter (where e.event_type = 'profile_view')::integer as views
    from public.discovery_events e
    where e.target_type = target_type_value
      and e.target_id = target_id_value
      and e.day >= (now() at time zone 'utc')::date - (janela - 1)
    group by e.day
  ),
  conversas as (
    select
      (c.created_at at time zone 'utc')::date as day,
      count(*)::integer as total
    from public.conversations c
    where c.created_at >= (now() at time zone 'utc')::date - (janela - 1)
      and (
        (target_type_value = 'lawyer' and c.lawyer_id = target_id_value)
        or (target_type_value = 'law_firm' and c.law_firm_id = target_id_value)
      )
    group by 1
  )
  select
    dias.day,
    coalesce(eventos.reach, 0),
    coalesce(eventos.sponsored_reach, 0),
    coalesce(eventos.views, 0),
    coalesce(conversas.total, 0)
  from dias
  left join eventos on eventos.day = dias.day
  left join conversas on conversas.day = dias.day
  order by dias.day;
end;
$$;

revoke all on function public.fetch_professional_reach(text, uuid, integer)
from public, anon;
grant execute on function public.fetch_professional_reach(text, uuid, integer)
to authenticated;

notify pgrst, 'reload schema';
