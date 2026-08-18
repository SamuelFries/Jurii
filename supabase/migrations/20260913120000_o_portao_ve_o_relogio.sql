-- O portão de abrir escritório passa a enxergar o relógio.
--
-- O FURO: has_law_firm_license comparava `status in ('trialing', 'active')`
-- ao pé da letra, e NADA no produto escreve por cima do 'trialing' quando o
-- teste vence. A coluna fica 'trialing' para sempre, então teste vencido
-- continuava abrindo escritório de graça.
--
-- É o mesmo engano que a 20260906120000 corrigiu no teto de advogados, e que
-- eu deixei passar justamente na porta que mais importa: a que CRIA a banca.
-- Lá a expiração passou a ser derivada por assinatura_esta_viva; aqui não.
--
-- A CORREÇÃO É REUSAR A REGRA, não repeti-la. assinatura_esta_viva já diz
-- exatamente isto: 'active' libera; 'trialing' só enquanto trial_ends_at for
-- futuro; teste sem data vale como vencido (entre errar para o lado de
-- cobrar e errar para o lado de liberar para sempre, este é o lado seguro).
-- Escrever a comparação de novo aqui seria a segunda cópia da mesma decisão,
-- e cópia é como esse tipo de regra diverge.
--
-- SEM MEXER NO STATUS. Nenhum job, nenhum cron, nenhuma coluna reescrita: a
-- expiração é derivada na hora da pergunta. O histórico da linha continua
-- contando o que aconteceu de verdade, e não o que um agendador conseguiu
-- alcançar.
--
-- O QUE ESTA MIGRATION NÃO MUDA, de propósito:
--
--   Quem PEDIU a abertura com o teste vivo e é aprovado depois do
--   vencimento continua ganhando a banca. A aprovação amarra a licença por
--   `status <> 'canceled'`, e assim segue: a demora é da nossa revisão, e
--   punir a pessoa por ela seria cobrar do lado errado. A banca nasce
--   congelada de qualquer forma (teto_de_advogados devolve 0), então ela
--   existe e não cresce até o pagamento entrar.
--
--   choose_law_firm_plan continua lendo 'trialing' ao pé da letra no ramo da
--   troca de plano, também de propósito: quem deixou o teste vencer não
--   pagou nada, então não há valor no provedor para divergir, e trocar de
--   plano antes de pagar é o caminho normal de quem voltou para contratar.

create or replace function public.has_law_firm_license(profile_id_value uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.law_firm_license_subscriptions sub
    where sub.owner_profile_id = profile_id_value
      and profile_id_value = (select auth.uid())
      -- A EXPIRAÇÃO É DERIVADA, e a regra mora num lugar só.
      and public.assinatura_esta_viva(sub.status, sub.trial_ends_at)
      -- A LICENÇA NÃO GASTA. Sem isto, a assinatura do escritório A abre o
      -- escritório B de graça, e uma banca paga por duas.
      and sub.law_firm_id is null
  );
$$;

revoke all on function public.has_law_firm_license(uuid) from public;
grant execute on function public.has_law_firm_license(uuid) to authenticated;

notify pgrst, 'reload schema';
