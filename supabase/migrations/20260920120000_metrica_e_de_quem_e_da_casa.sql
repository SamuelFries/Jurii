-- A métrica é de quem é da casa.
--
-- fetch_law_firm_operation_metrics é SECURITY DEFINER, tem execute para
-- authenticated, recebe o id do escritório e não perguntava QUEM está
-- chamando: nem auth.uid(), nem vínculo, nada. Qualquer conta autenticada
-- passava o id de qualquer banca e recebia de volta o retrato da operação
-- dela: quantas conversas com clientes (o volume de leads), quantas conversas
-- internas, quantos casos ativos e o tamanho da equipe.
--
-- Reproduzido no banco local: um usuário sem nenhum vínculo com a banca lê
-- client_messages=2, team_members=1. Os ids de escritório não são segredo
-- (aparecem na busca), então isto era inteligência competitiva servida por
-- RPC: dá para acompanhar o crescimento de um concorrente semana a semana.
--
-- A recusa é VAZIA e não exceção porque é assim que os dois clientes já
-- tratam a resposta: o app devolve FirmOperationMetrics.empty() quando a
-- lista volta sem linhas, e a Visão Geral do webapp lê o primeiro elemento.
-- Levantar erro aqui derrubaria a tela inteira por um painel.
--
-- A varredura das outras definer que recebem law_firm_id não achou irmã:
-- fetch_law_firm_cnpj já exige is_active_law_firm_manager, e
-- fetch_law_firm_lawyers e safe_law_firm_logo_url servem dado que é público
-- por desenho (a busca de escritórios mostra os advogados e o logo).

create or replace function public.fetch_law_firm_operation_metrics(
  law_firm_id_value uuid
)
returns table (
  client_messages integer,
  team_messages integer,
  active_cases integer,
  team_members integer
)
language sql
stable
security definer
set search_path to 'public'
as $function$
  with quem_pergunta as (
    -- MEMBRO ATIVO, e não gestor: a Visão Geral é a primeira tela de quem
    -- trabalha na banca, e secretária e estagiário também a abrem.
    select 1
    from public.law_firm_members lfm
    where lfm.law_firm_id = law_firm_id_value
      and lfm.profile_id = auth.uid()
      and lfm.status = 'active'
  ),
  active_members as (
    select lfm.profile_id
    from public.law_firm_members lfm
    where lfm.law_firm_id = law_firm_id_value
      and lfm.profile_id is not null
      and lfm.status = 'active'
  ),
  scoped_cases as (
    select distinct lc.id
    from public.legal_cases lc
    where lc.status <> 'closed'
      and lc.law_firm_id = law_firm_id_value
  )
  select
    (
      select count(distinct c.id)::int
      from public.conversations c
      where c.law_firm_id = law_firm_id_value
        and c.type <> 'firm_internal'
    ),
    (
      select count(distinct c.id)::int
      from public.conversations c
      where c.law_firm_id = law_firm_id_value
        and c.type = 'firm_internal'
    ),
    (select count(*)::int from scoped_cases),
    (select count(*)::int from active_members)
  -- Sem vínculo, nenhuma linha. As agregações sempre devolveriam uma linha
  -- (com zeros), e zero é uma resposta: diria "essa banca não tem nada".
  where exists (select 1 from quem_pergunta);
$function$;

revoke all on function public.fetch_law_firm_operation_metrics(uuid) from public, anon;
grant execute on function public.fetch_law_firm_operation_metrics(uuid) to authenticated;
