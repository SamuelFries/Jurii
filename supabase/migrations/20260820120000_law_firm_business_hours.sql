-- Horarios de atendimento do escritorio.
--
-- POR QUE. "Horarios de atendimento" era um item de menu que abria "em breve".
-- Nao e enfeite de cadastro: e o que responde a pergunta que o cliente faz
-- antes de mandar a primeira mensagem — "adianta escrever agora?". Sem isso o
-- cliente escreve as 22h de domingo, nao recebe resposta ate segunda, e conclui
-- que o escritorio ignora cliente. O escritorio perde o caso sem nunca saber
-- que ele existiu.
--
-- MODELO. Uma LINHA por intervalo, nao uma coluna por dia. A tela de hoje
-- escreve um intervalo por dia (9h-18h), mas escritorio que fecha para almoco
-- e realidade — e com linhas isso vira dois registros no mesmo dia, sem mexer
-- no esquema. Coluna abre_as/fecha_as por dia teria travado essa porta.
--
-- DIA DA SEMANA: 1 = segunda ... 7 = domingo, a mesma convencao de
-- DateTime.weekday do Dart. Postgres usa 0 = domingo em extract(dow), entao
-- quem escrever SQL sobre esta tabela precisa saber que ela NAO segue o
-- Postgres — segue o app, que e quem le e escreve.

create table if not exists public.law_firm_business_hours (
  id uuid primary key default gen_random_uuid(),
  law_firm_id uuid not null
    references public.law_firms(id) on delete cascade,
  weekday smallint not null check (weekday between 1 and 7),
  opens_at time not null,
  closes_at time not null,
  created_at timestamptz not null default now(),
  -- Intervalo invertido nao e "fecha no dia seguinte", e digitacao errada: a
  -- tela nao oferece virada de meia-noite, e aceitar aqui deixaria um horario
  -- que nunca esta aberto.
  constraint law_firm_business_hours_interval_chk check (closes_at > opens_at),
  -- Mesmo dia, mesma abertura, duas linhas seria o mesmo intervalo duplicado.
  constraint law_firm_business_hours_unique unique (law_firm_id, weekday, opens_at)
);

create index if not exists law_firm_business_hours_firm_idx
on public.law_firm_business_hours (law_firm_id, weekday);

alter table public.law_firm_business_hours enable row level security;

-- LEITURA PUBLICA (para autenticado): e informacao que existe para o CLIENTE
-- ver antes de escrever. Esconde-la de quem procura advogado seria guardar a
-- unica coisa que o horario serve para responder.
drop policy if exists law_firm_business_hours_read
on public.law_firm_business_hours;
create policy law_firm_business_hours_read
on public.law_firm_business_hours for select
to authenticated
using (true);

-- Escrita so pela RPC (mesmo movimento das areas e da apresentacao): sem
-- UPDATE/INSERT direto, a validacao nao tem como ser contornada.
revoke all on table public.law_firm_business_hours from public, anon;
grant select on table public.law_firm_business_hours to authenticated;

-- ---------------------------------------------------------------------------
-- Gravacao: substitui o conjunto INTEIRO numa transacao.
--
-- Por que substituir tudo em vez de CRUD linha a linha: o horario e lido como
-- um conjunto ("de seg a sex, 9h as 18h"). Editar linha a linha deixaria
-- estados intermediarios visiveis ao cliente — sexta-feira sumida por um
-- instante porque a tela ainda estava gravando. Aqui, ou entra tudo, ou nada
-- muda.
-- ---------------------------------------------------------------------------
create or replace function public.set_law_firm_business_hours(
  law_firm_id_value uuid,
  hours_value jsonb
)
returns table(weekday smallint, opens_at time, closes_at time)
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  total int;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  -- Mesmo portao do cadastro, da apresentacao e do painel: quem fala pelo
  -- escritorio.
  if not public.is_active_law_firm_manager(law_firm_id_value) then
    raise exception 'Not allowed';
  end if;

  if hours_value is not null and jsonb_typeof(hours_value) <> 'array' then
    raise exception 'Hours must be an array';
  end if;

  -- Teto de sanidade: 7 dias x 3 intervalos ja cobre manha/tarde/noite. Sem
  -- teto, uma chamada malformada encheria a tabela.
  select count(*) into total
  from jsonb_array_elements(coalesce(hours_value, '[]'::jsonb));
  if total > 21 then
    raise exception 'Too many intervals';
  end if;

  delete from public.law_firm_business_hours
  where law_firm_id = law_firm_id_value;

  insert into public.law_firm_business_hours
    (law_firm_id, weekday, opens_at, closes_at)
  select
    law_firm_id_value,
    (item ->> 'weekday')::smallint,
    (item ->> 'opens_at')::time,
    (item ->> 'closes_at')::time
  from jsonb_array_elements(coalesce(hours_value, '[]'::jsonb)) as item
  -- Dia fechado simplesmente NAO tem linha; mandar um item sem horario e o
  -- jeito natural de a tela dizer isso, e descartar aqui evita a tela ter que
  -- filtrar antes.
  where nullif(item ->> 'opens_at', '') is not null
    and nullif(item ->> 'closes_at', '') is not null;

  return query
  select h.weekday, h.opens_at, h.closes_at
  from public.law_firm_business_hours h
  where h.law_firm_id = law_firm_id_value
  order by h.weekday, h.opens_at;
end;
$$;

revoke all on function public.set_law_firm_business_hours(uuid, jsonb)
from public, anon;
grant execute on function public.set_law_firm_business_hours(uuid, jsonb)
to authenticated;

notify pgrst, 'reload schema';
