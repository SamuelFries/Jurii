-- A cobrança passa a ser por ESCRITÓRIO, e não por pessoa.
--
-- O QUE ESTAVA ERRADO, e é o que hoje mantém fechada a porta do segundo
-- escritório: a licença era da PESSOA. `has_law_firm_license(perfil)`
-- respondia "sim" para qualquer assinatura ativa, inclusive uma já gasta com
-- o escritório A. Ou seja, quem já tem banca passaria pelo portão para abrir
-- a segunda pagando uma assinatura só. E `choose_law_firm_plan` nem deixava
-- comprar a segunda: ele achava a assinatura existente e a ATUALIZAVA, então
-- tentar contratar de novo trocava o plano da primeira.
--
-- O MODELO CERTO já cabia na tabela, que sempre teve `law_firm_id` anulável:
--
--   assinatura SEM escritório  =  licença comprada e ainda não gasta
--   assinatura COM escritório  =  licença gasta naquela banca
--
-- A aprovação do cadastro já amarra a assinatura ao escritório que nasce
-- (approve_law_firm_verification faz isso desde a 20260821120000). Faltava o
-- resto da regra enxergar essa distinção.
--
-- Com ela, abrir o segundo escritório deixa de ser um caso especial: é
-- comprar a segunda licença. E a regra da Seccional (20260902120000) continua
-- guardando o lado da OAB, que é outra pergunta.

-- ---------------------------------------------------------------------------
-- 0. O índice que dizia "uma pessoa, um plano"
-- ---------------------------------------------------------------------------
--
-- `law_firm_license_one_per_owner` era a expressão FÍSICA da premissa antiga:
-- único por dono, logo uma assinatura por pessoa para sempre. Ele é a razão
-- de o segundo escritório ser impossível mesmo com a função corrigida.
--
-- O que fica no lugar é a mesma ideia no nível certo: uma pessoa pode ter N
-- assinaturas, uma por banca, mais NO MÁXIMO UMA ainda não gasta. Assim
-- ninguém acumula licença comprada e não usada, e a regra deixa de depender
-- de a função lembrar de reaproveitar.
--
-- `law_firm_license_one_per_firm` já existia e continua: um escritório, uma
-- licença. Essa metade sempre esteve certa.
drop index if exists public.law_firm_license_one_per_owner;

create unique index if not exists law_firm_license_one_unspent_per_owner
  on public.law_firm_license_subscriptions (owner_profile_id)
  where law_firm_id is null and status <> 'canceled';

-- ---------------------------------------------------------------------------
-- 1. O portão: licença NÃO GASTA
-- ---------------------------------------------------------------------------
--
-- Esta função é o `with check` de law_firm_verifications_insert_own, ou seja,
-- é o que decide quem pode pedir a abertura de um escritório. Errar aqui
-- fecha a porta para todo mundo, então a mudança é a menor possível: continua
-- respondendo só sobre quem pergunta (trava da 20260901120000), e ganha a
-- exigência de a assinatura ainda não estar amarrada a uma banca.
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
      and sub.status in ('trialing', 'active')
      -- A LICENÇA NÃO GASTA. Sem isto, a assinatura do escritório A abre o
      -- escritório B de graça, e uma banca paga por duas.
      and sub.law_firm_id is null
  );
$$;

revoke all on function public.has_law_firm_license(uuid) from public;
grant execute on function public.has_law_firm_license(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Contratar e trocar de plano, com o escritório no argumento
-- ---------------------------------------------------------------------------
--
-- `drop` e `create`, e não `create or replace`: o argumento novo muda a
-- assinatura, e manter as duas versões deixaria o PostgREST com uma
-- sobrecarga ambígua. A troca é segura mesmo com o webapp antigo no ar,
-- porque ele chama por parâmetro NOMEADO (plan_code_value, billing_cycle_value)
-- e o terceiro tem valor padrão: a chamada de dois argumentos continua
-- resolvendo para esta função.
drop function if exists public.choose_law_firm_plan(text, text);

create or replace function public.choose_law_firm_plan(
  plan_code_value text,
  billing_cycle_value text default 'monthly',
  law_firm_id_value uuid default null
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

  -- ---------------------------------------------------------------------
  -- COM escritório: trocar o plano DAQUELA banca
  -- ---------------------------------------------------------------------
  if law_firm_id_value is not null then
    -- Quem troca o plano de um escritório é quem o administra, e quem
    -- responde isso é o mesmo helper de sempre. Sem esta linha, o id no
    -- corpo da requisição trocaria o plano da banca dos outros.
    if not public.is_active_law_firm_manager(law_firm_id_value) then
      raise exception 'Only active office owners and admins can change the plan';
    end if;

    select * into sub
    from public.law_firm_license_subscriptions s
    where s.law_firm_id = law_firm_id_value
      and s.status <> 'canceled'
    order by s.created_at asc
    limit 1;

    if not found then
      raise exception 'Firm has no subscription';
    end if;

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

  -- ---------------------------------------------------------------------
  -- SEM escritório: uma licença nova, para abrir uma banca
  -- ---------------------------------------------------------------------
  --
  -- Procura uma licença JÁ COMPRADA E NÃO GASTA antes de criar outra: é a
  -- pessoa mudando de ideia sobre o plano antes de abrir o escritório, e ela
  -- não pode virar duas cobranças.
  select * into sub
  from public.law_firm_license_subscriptions s
  where s.owner_profile_id = caller
    and s.law_firm_id is null
    and s.status <> 'canceled'
  order by s.created_at asc
  limit 1;

  if found then
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

  -- A trava antiga era "Firm already has a subscription": ela existia para
  -- dizer "uma pessoa, um plano", e caiu junto com essa premissa. O que ela
  -- protegia continua protegido pelo ramo de cima: cada escritório tem a
  -- assinatura dele, e trocar o plano exige ser gestor daquela banca.
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

revoke all on function public.choose_law_firm_plan(text, text, uuid) from public, anon;
grant execute on function public.choose_law_firm_plan(text, text, uuid) to authenticated;

notify pgrst, 'reload schema';
