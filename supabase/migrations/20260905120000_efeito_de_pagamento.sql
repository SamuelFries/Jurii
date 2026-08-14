-- A única porta por onde uma assinatura muda de status.
--
-- O desenho da cobrança sempre disse que quem grava o resultado é o WEBHOOK,
-- com a service_role, que vive só nas variáveis de ambiente da Vercel. O que
-- faltava era a porta: sem ela, o webhook escreveria direto na tabela, e a
-- service_role passa por cima de toda a RLS. Uma chave que pode tudo,
-- escrevendo à mão numa tabela de cobrança, é a definição de porta larga.
--
-- Com esta função a chave continua sendo a mesma, mas ela só alcança UMA
-- operação, que valida a transição e é idempotente. E a operação fica
-- testável em pgTAP, que é onde regra de cobrança tem que estar.
--
-- NÃO É CHAMÁVEL POR CLIENTE. Sem grant para authenticated nem anon: quem
-- chama é o servidor do webhook, com a service_role.

create or replace function public.aplicar_efeito_de_pagamento(
  assinatura_id_value uuid,
  efeito_value text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  atual public.law_firm_license_subscriptions%rowtype;
  novo_status text;
begin
  if efeito_value not in ('ativar', 'pagamento_pendente', 'cancelar') then
    raise exception 'Unknown payment effect: %', coalesce(efeito_value, '(null)');
  end if;

  select * into atual
  from public.law_firm_license_subscriptions
  where id = assinatura_id_value
  for update;

  if not found then
    -- Assinatura que não existe NÃO é erro de servidor: o provedor pode
    -- chamar sobre uma cobrança de teste, ou sobre algo já apagado. Quem
    -- recebe precisa saber para responder 200 e não fazer o provedor
    -- reentregar para sempre.
    return 'desconhecida';
  end if;

  novo_status := case efeito_value
    when 'ativar' then 'active'
    when 'pagamento_pendente' then 'past_due'
    when 'cancelar' then 'canceled'
  end;

  -- CANCELADA NÃO VOLTA por webhook. Reativar é contratar de novo, e passa
  -- por choose_law_firm_plan; deixar um evento atrasado ressuscitar uma
  -- assinatura cancelada devolveria acesso a quem já saiu.
  if atual.status = 'canceled' and efeito_value <> 'cancelar' then
    return 'ignorada';
  end if;

  -- IDEMPOTENTE de propósito: provedor reentrega o mesmo evento quando não
  -- recebe 200 a tempo, e isso é normal, não é ataque. Aplicar duas vezes
  -- precisa dar no mesmo.
  if atual.status = novo_status then
    return 'sem mudanca';
  end if;

  update public.law_firm_license_subscriptions
  set status = novo_status, updated_at = now()
  where id = assinatura_id_value;

  return novo_status;
end;
$$;

revoke all on function public.aplicar_efeito_de_pagamento(uuid, text)
  from public, anon, authenticated;
grant execute on function public.aplicar_efeito_de_pagamento(uuid, text)
  to service_role;

notify pgrst, 'reload schema';
