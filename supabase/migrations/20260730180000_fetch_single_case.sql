-- Abrir UM caso a partir do id (destino do toque na notificacao)
--
-- Faltava a peca para fechar o ciclo da notificacao: o cliente recebe "Seu
-- processo andou", toca, e nao ha para onde ir. A notificacao carrega o
-- `case_id` no metadata, mas o app so sabia buscar LISTAS de casos
-- (fetch_client_cases / fetch_lawyer_cases / fetch_law_firm_cases), e a tela
-- de detalhe precisa de titulo, subtitulo e permissao.
--
-- Duas decisoes que valem registro:
--
--   1. Quem decide se o usuario pode EDITAR e o SERVIDOR
--      (`can_manage_case_updates`), nao o app. Hoje lawyer_cases_screen passa
--      `canAddUpdates: true` fixo e o painel do escritorio faz a conta com o
--      uid; abrindo por notificacao nao existe esse contexto. Devolver a
--      permissao junto do caso e mais simples e mais correto.
--
--   2. `viewer_is_client` deixa o app montar o mesmo subtitulo que as listas ja
--      montam ("area · status" para o cliente, "cliente · area" para o
--      profissional), sem o servidor decidir texto de UI.
--
-- Acesso: `can_access_case` OU gestor ativo do escritorio do caso.
--
-- O segundo ramo nao e generosidade: `can_access_case` so reconhece cliente,
-- advogado atribuido e quem esta em `case_participants`, e
-- `respond_to_case_request` so cria participante para o cliente, o advogado e
-- quem pediu o caso. Mas a notificacao `firm_case_started` vai para TODOS os
-- gestores ativos do escritorio (dono/admin/secretaria). Sem este ramo, o
-- socio que nao pediu o caso recebe "Novo caso no escritorio", toca, e nada
-- abre — e o escopo do escritorio nao tem outro destino, entao o toque dele
-- seria morto por definicao.
--
-- Nao abre visibilidade nova: e o MESMO escopo que `fetch_law_firm_cases` ja
-- concede (o caso ja aparece no painel) e o mesmo par que
-- `set_case_cnj_number` usa. `can_manage` continua vindo de
-- `can_manage_case_updates`, entao o gestor nao-designado ve o caso sem ganhar
-- permissao de editar — igual ao que o painel ja faz hoje.
--
-- Quem nao participa nem gerencia recebe zero linhas (nao um erro, para nao
-- confirmar a existencia do caso).

create or replace function public.fetch_case_for_current_user(
  case_id_value uuid
)
returns table (
  id uuid,
  title text,
  area text,
  status_label text,
  client_name text,
  cnj_number text,
  viewer_is_client boolean,
  can_manage boolean
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
    public.case_status_label(lc.status) as status_label,
    public.profile_display_name(
      client_profile.full_name,
      client_profile.deleted_at,
      client_profile.deleted_display_name
    ) as client_name,
    lc.cnj_number,
    lc.client_id = auth.uid() as viewer_is_client,
    public.can_manage_case_updates(lc.id) as can_manage
  from public.legal_cases lc
  left join public.profiles client_profile
    on client_profile.id = lc.client_id
  where lc.id = case_id_value
    and (
      public.can_access_case(case_id_value)
      or (
        lc.law_firm_id is not null
        and public.is_active_law_firm_case_manager(lc.law_firm_id)
      )
    );
$$;

revoke all on function public.fetch_case_for_current_user(uuid)
  from public, anon;
grant execute on function public.fetch_case_for_current_user(uuid)
  to authenticated;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Verificacao pos-push (SQL Editor):
--   select * from public.fetch_case_for_current_user('<id de um caso seu>');
--   -- can_manage deve ser false para o cliente e true para o advogado do caso
-- ---------------------------------------------------------------------------
