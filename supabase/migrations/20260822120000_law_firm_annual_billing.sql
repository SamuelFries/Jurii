-- Cobranca anual com desconto, ao lado da mensal.
--
-- PRECIFICACAO (decisao de produto, 08/08/2026): o anual sai por 20% menos,
-- com o equivalente mensal REDONDO, porque e ele que a tela mostra (padrao
-- das assinaturas de software: "R$ 279/mes, cobrado anualmente"):
--
--     essencial   R$ 149/mes  ou  R$ 119/mes no anual (R$ 1.428/ano)
--     escritorio  R$ 349/mes  ou  R$ 279/mes no anual (R$ 3.348/ano)
--     banca       R$ 699/mes  ou  R$ 559/mes no anual (R$ 6.708/ano)
--
-- 20% e desconto de compromisso: paga 12 meses de uma vez, leva ~2,4 meses.
-- Continua sendo LINHA de tabela: mudar o desconto e UPDATE, nao release.
--
-- A assinatura passa a registrar o CICLO escolhido. Sem isso a escolha da
-- pessoa morreria na tela, e na hora de cobrar (fora do app, quando o gateway
-- existir) ninguem saberia o que foi combinado.

alter table public.law_firm_license_plans
  add column if not exists annual_price_cents int
    check (annual_price_cents is null or annual_price_cents >= 0);

update public.law_firm_license_plans
set annual_price_cents = case code
  when 'essencial'  then 142800
  when 'escritorio' then 334800
  when 'banca'      then 670800
end
where code in ('essencial', 'escritorio', 'banca');

alter table public.law_firm_license_subscriptions
  add column if not exists billing_cycle text not null default 'monthly'
    check (billing_cycle in ('monthly', 'annual'));

-- ---------------------------------------------------------------------------
-- choose_law_firm_plan ganha o ciclo. A assinatura de argumentos muda, entao
-- e drop + create — e drop ZERA os grants, restaurados no fim.
-- ---------------------------------------------------------------------------
drop function public.choose_law_firm_plan(text);

create function public.choose_law_firm_plan(
  plan_code_value text,
  billing_cycle_value text default 'monthly'
)
returns table (
  id uuid,
  plan_code text,
  billing_cycle text,
  status text,
  trial_ends_at timestamptz,
  law_firm_id uuid
)
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  plan public.law_firm_license_plans%rowtype;
  sub public.law_firm_license_subscriptions%rowtype;
  cycle text;
begin
  if caller is null then
    raise exception 'Not authenticated';
  end if;

  cycle := lower(btrim(coalesce(billing_cycle_value, 'monthly')));
  if cycle not in ('monthly', 'annual') then
    raise exception 'Unknown billing cycle: %', billing_cycle_value;
  end if;

  select * into plan
  from public.law_firm_license_plans p
  where p.code = plan_code_value and p.is_active;
  if not found then
    raise exception 'Unknown plan: %', coalesce(plan_code_value, '(null)');
  end if;

  -- Plano sem preco anual nao pode ser contratado no anual: cobrar um valor
  -- que a tabela nao tem seria inventar preco na hora.
  if cycle = 'annual' and plan.annual_price_cents is null then
    raise exception 'Plan has no annual price: %', plan.code;
  end if;

  select * into sub
  from public.law_firm_license_subscriptions s
  where s.owner_profile_id = caller and s.status <> 'canceled'
  limit 1;

  if found then
    -- Troca de plano ou de ciclo NAO renova o teste: pular de opcao em opcao
    -- nao pode virar teste infinito.
    update public.law_firm_license_subscriptions s
    set plan_code = plan.code, billing_cycle = cycle, updated_at = now()
    where s.id = sub.id;

    return query
    select s.id, s.plan_code, s.billing_cycle, s.status, s.trial_ends_at,
           s.law_firm_id
    from public.law_firm_license_subscriptions s
    where s.id = sub.id;
    return;
  end if;

  -- Membro de um escritorio que JA tem assinatura (de outra pessoa) nao abre
  -- uma segunda: um escritorio, um plano, um pagante.
  if exists (
    select 1
    from public.law_firm_members m
    join public.law_firm_license_subscriptions s
      on s.law_firm_id = m.law_firm_id and s.status <> 'canceled'
    where m.profile_id = caller and m.status = 'active'
  ) then
    raise exception 'Firm already has a subscription';
  end if;

  return query
  insert into public.law_firm_license_subscriptions
    (owner_profile_id, plan_code, billing_cycle, status, trial_ends_at)
  values
    -- 30 dias sem cartao, qualquer que seja o ciclo: o teste e do produto,
    -- nao da forma de pagar.
    (caller, plan.code, cycle, 'trialing', now() + interval '30 days')
  returning
    law_firm_license_subscriptions.id,
    law_firm_license_subscriptions.plan_code,
    law_firm_license_subscriptions.billing_cycle,
    law_firm_license_subscriptions.status,
    law_firm_license_subscriptions.trial_ends_at,
    law_firm_license_subscriptions.law_firm_id;
end;
$$;

revoke all on function public.choose_law_firm_plan(text, text) from public, anon;
grant execute on function public.choose_law_firm_plan(text, text) to authenticated;

notify pgrst, 'reload schema';
