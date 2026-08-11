-- Portao de aprovacao VIGENTE no perfil publico do advogado.
--
-- HONESTIDADE SOBRE A GRAVIDADE: isto NAO conserta vazamento ativo. A
-- funcao e SECURITY DEFINER (precisa ser: o nome mora em profiles, que nao
-- e publico) e nao checava aprovacao nenhuma. Parecia buraco. Medido em
-- 11/08/2026 contra producao, e verificado por revisao adversarial: nao e,
-- porque hoje nao existe perfil nao aprovado e nao ha como criar um.
-- authenticated nao tem INSERT em lawyer_profiles (nem tabela nem coluna),
-- nao tem UPDATE em approved_at, nao existe policy de INSERT, e a unica
-- funcao que insere e approve_lawyer_verification, executavel so por
-- service_role. Nem service_role cria linha nao aprovada. Producao: 41
-- perfis, 41 aprovados.
--
-- POR QUE ENTAO SAO DUAS LINHAS, E NAO UMA:
--
-- approved_at e uma TRAVA DE MAO UNICA. Nada no banco jamais a limpa:
-- reject_lawyer_verification (medido: o corpo nao cita lawyer_profiles nem
-- approved_at) poe profiles.lawyer_status = 'client' e deixa a linha de
-- lawyer_profiles intacta, com approved_at preenchido e is_available true.
-- Entao um advogado REVOGADO passaria por um portao que so olhasse
-- approved_at: seria defesa no sinal morto.
--
-- O sinal VIVO e profiles.lawyer_status, que e o que
-- start_or_get_lawyer_conversation ja exige para abrir conversa. Sem esta
-- linha, o app recusaria abrir conversa com o revogado e ao mesmo tempo
-- mostraria o perfil dele: duas respostas para a mesma pergunta.
--
-- Custo hoje: ZERO linhas removidas. Medido: 41 perfis, 41 com approved_at
-- e 41 com lawyer_status 'approved', 0 de divergencia, 0 indisponiveis.
-- Nunca houve rejeicao (41 verificacoes, 41 aprovadas), entao este e
-- codigo nunca exercitado, e nao codigo provado seguro.
--
-- FICA REGISTRADO, fora do escopo desta migration: fetch_recommended_lawyers
-- (a lista da descoberta) e fetch_favorite_lawyers nao filtram aprovacao
-- nenhuma, e a policy de SELECT da tabela filtra pelo sinal morto. Na
-- primeira revogacao, o revogado continua na busca. Fechar isso mexe na
-- funcao central da descoberta e e decisao propria, nao efeito colateral.
--
-- create or replace, NAO drop+create: assinatura, nome de argumento
-- (lawyer_profile_id_value, o que o app e o webapp passam) e as 12 colunas
-- ficam intactos, entao os grants nao sao resetados.

create or replace function public.fetch_lawyer_public_profile(
  lawyer_profile_id_value uuid
)
returns table (
  id uuid,
  full_name text,
  initials text,
  oab_number text,
  oab_state text,
  primary_area text,
  practice_areas text[],
  bio text,
  rating numeric,
  reviews_count int,
  avatar_type text,
  avatar_url text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    lp.id,
    coalesce(p.full_name, 'Advogado Jurii') as full_name,
    coalesce(p.initials, 'AJ') as initials,
    lp.oab_number,
    lp.oab_state::text as oab_state,
    lp.primary_area,
    case
      when cardinality(lp.practice_areas) > 0 then lp.practice_areas
      else array[lp.primary_area]
    end as practice_areas,
    coalesce(lp.bio, 'Perfil profissional verificado pela Jurii.') as bio,
    lp.rating,
    lp.reviews_count,
    'navy'::text as avatar_type,
    public.safe_profile_avatar_url(p.id, p.avatar_url) as avatar_url
  from public.lawyer_profiles lp
  join public.profiles p on p.id = lp.id
  where lp.id = lawyer_profile_id_value
    and lp.is_available = true
    -- As duas linhas novas. approved_at alinha com a RLS da tabela;
    -- lawyer_status e o sinal VIVO, o unico que a revogacao mexe.
    and lp.approved_at is not null
    and p.lawyer_status = 'approved'
    and p.deleted_at is null
  limit 1;
$$;

notify pgrst, 'reload schema';
