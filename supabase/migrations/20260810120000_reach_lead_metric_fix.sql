-- Corrige a metrica de LEAD do painel de alcance.
--
-- A 20260809120000 ja subiu para producao com a versao errada, e o proprio uso
-- denunciou: um advogado que nunca recebeu mensagem aparecia com 1 "iniciaram
-- conversa" nos ultimos 30 dias. A funcao contava LINHAS de
-- public.conversations, e start_or_get_*_conversation cria a linha SEMPRE — a
-- mensagem so entra se houver texto. Abrir o chat e desistir virava lead.
--
-- E este e o numero que justifica o preco do patrocinio: inflar aqui e inflar
-- a fatura, que e a direcao errada de estar errado.
--
-- O QUE MUDA:
--   1. lead = primeira mensagem DO CLIENTE, e nao a existencia da conversa
--   2. mensagem do proprio profissional nao cria lead (escritorio sugere
--      advogado, ele escreve primeiro: ainda nao ha interesse manifestado)
--   3. o dia do lead e o da PRIMEIRA MENSAGEM, nao o da criacao da linha
--   4. canal interno de equipe sai da conta — tem law_firm_id preenchido e
--      estava entrando como lead do escritorio
--   5. o dia do painel passa a ser o de SAO PAULO. Em UTC, quem olhava as 22h
--      via a atividade da noite dele cair no dia seguinte: deslocamento
--      sistematico de 3 horas no grafico
--
-- As linhas ja gravadas em discovery_events com dia em UTC ficam como estao:
-- sao de um unico dia de teste, e reprocessar historico de tres horas nao paga
-- o risco.

alter table public.discovery_events
  alter column day set default (now() at time zone 'America/Sao_Paulo')::date;

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
  with hoje as (
    select (now() at time zone 'America/Sao_Paulo')::date as dia
  ),
  dias as (
    select generate_series(
      (select dia from hoje) - (janela - 1),
      (select dia from hoje),
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
      and e.day >= (select dia from hoje) - (janela - 1)
    group by e.day
  ),
  -- Conversa iniciada = o CLIENTE mandou a primeira mensagem.
  --
  -- Contar linhas de public.conversations, que era o que estava aqui, contava
  -- quem apenas ABRIU o chat: start_or_get_*_conversation cria a linha sempre,
  -- e so grava mensagem se houver texto. Abrir e fechar virava lead — e este e
  -- o numero que justifica o preco do patrocinio, entao inflar aqui e inflar a
  -- fatura.
  --
  -- Tambem so conta mensagem do CLIENTE: quando o escritorio sugere um
  -- advogado e ele escreve primeiro, ainda nao ha interesse manifestado.
  -- E o dia e o da PRIMEIRA MENSAGEM, nao o da criacao da linha: quem abre o
  -- chat num dia e escreve no outro vira lead no dia em que escreveu.
  conversas as (
    select
      (primeira.enviada_em at time zone 'America/Sao_Paulo')::date as day,
      count(*)::integer as total
    from public.conversations c
    cross join lateral (
      select min(m.created_at) as enviada_em
      from public.messages m
      where m.conversation_id = c.id
        and m.sender_type = 'client'
    ) primeira
    where primeira.enviada_em is not null
      -- Canal interno de equipe tem law_firm_id preenchido e nunca foi lead.
      and c.type <> 'firm_internal'
      and (primeira.enviada_em at time zone 'America/Sao_Paulo')::date
        >= (select dia from hoje) - (janela - 1)
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
