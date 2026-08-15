-- ANTES DE RODAR A 20260906120000 EM PRODUÇÃO.
--
-- A migration dá consequência a status de assinatura. Consequência é o que
-- não existia, então há linhas em produção que hoje passam por vivas e no
-- minuto seguinte ao deploy deixam de passar. Nenhuma delas é bug da
-- migration: são exatamente os casos que ela existe para fechar. Mas quem
-- decide se elas fecham HOJE é você, e não a migration.
--
-- Rode isto no banco de produção ANTES do push. Se vier tudo zero, o deploy
-- não muda nada para ninguém.
select
  'teste vencido, banca CONGELA ao rodar' as situacao,
  count(*) as quantas
from public.law_firm_license_subscriptions s
where s.law_firm_id is not null
  and s.status = 'trialing'
  and (s.trial_ends_at is null or s.trial_ends_at <= now())

union all
select
  'inadimplente, banca CONGELA ao rodar (antes tinha teto cheio)',
  count(*)
from public.law_firm_license_subscriptions s
where s.law_firm_id is not null and s.status = 'past_due'

union all
select
  'cancelada, banca perde o teto INFINITO que tinha por engano',
  count(*)
from public.law_firm_license_subscriptions s
where s.law_firm_id is not null and s.status = 'canceled'
  and not exists (
    select 1 from public.law_firm_license_subscriptions viva
    where viva.law_firm_id = s.law_firm_id and viva.status <> 'canceled'
  )

union all
select
  'verificacao PENDENTE cujo dono nao tem licenca: aprovacao vai falhar',
  count(*)
from public.law_firm_verifications v
where v.status = 'pending'
  and v.law_firm_id is null
  and not exists (
    select 1 from public.law_firm_license_subscriptions s
    where s.owner_profile_id = v.owner_profile_id
      and s.law_firm_id is null
      and s.status <> 'canceled'
  )

union all
select
  'banca ja cobrada: troca de plano passa a ser recusada',
  count(*)
from public.law_firm_license_subscriptions s
where s.law_firm_id is not null and s.status = 'active'

union all
select
  'banca SEM assinatura nenhuma: segue sem teto (sem trava retroativa)',
  count(*)
from public.law_firms f
where f.is_active
  and not exists (
    select 1 from public.law_firm_license_subscriptions s
    where s.law_firm_id = f.id
  );
