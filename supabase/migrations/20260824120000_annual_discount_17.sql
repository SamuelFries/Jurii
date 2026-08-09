-- Desconto anual passa de 20% para 17%.
--
-- Decisao de produto (09/08/2026). Os valores foram escolhidos para o
-- EQUIVALENTE MENSAL sair em reais inteiros, porque e ele que a tela mostra:
-- o total do ano nao aparece mais, so o "por mes, cobrado anualmente".
--
--     plano        mensal   anual/mes   ano inteiro   desconto
--     essencial    R$ 149   R$ 124      R$ 1.488      16,8% -> 17%
--     escritorio   R$ 349   R$ 290      R$ 3.480      16,9% -> 17%
--     banca        R$ 699   R$ 580      R$ 6.960      17,0% -> 17%
--
-- O selo da tela e CALCULADO destes numeros (LicensePlan.annualDiscountPercent),
-- nao escrito a mao: os tres arredondam para 17%, e mexer aqui move o selo
-- junto.
--
-- Assinaturas ja contratadas no anual nao sao tocadas: o preco que valeu na
-- contratacao e assunto da cobranca, que acontece fora do app.

update public.law_firm_license_plans
set annual_price_cents = case code
  when 'essencial'  then 148800
  when 'escritorio' then 348000
  when 'banca'      then 696000
end
where code in ('essencial', 'escritorio', 'banca');

notify pgrst, 'reload schema';
