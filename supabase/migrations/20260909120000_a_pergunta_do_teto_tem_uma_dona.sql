-- "Esta banca pode ganhar mais um advogado?" passa a ter UMA dona.
--
-- A regra mora em teto_de_advogados (20260906120000), e ela tem três
-- respostas que só fazem sentido juntas: NENHUMA linha de cobrança quer dizer
-- banca anterior ao licenciamento, que segue sem teto; linha viva quer dizer
-- cresce até o teto do plano; linha parada quer dizer congelada.
--
-- O PROBLEMA: as telas precisam da mesma resposta para avisar ANTES em vez de
-- recusar DEPOIS, e teto_de_advogados é revogada de authenticated. Sem esta
-- função, cada cliente reimplementa a regra na própria linguagem. O webapp já
-- tinha feito isso em TypeScript, e o app faria em Dart: três cópias da mesma
-- decisão, em três lugares que ninguém obriga a mudar juntos.
--
-- E o modo de errar a cópia é conhecido, porque o banco já errou assim: os
-- dois clientes leem a assinatura por consultas que filtram `canceled`, e com
-- esse filtro "nunca teve licença" e "teve e o cancelamento passou" chegam
-- idênticos. Foi exatamente essa confusão que fazia cancelar virar equipe
-- ilimitada, e ela reapareceria na tela dizendo "pode convidar" enquanto o
-- banco recusa.
--
-- Com uma função só, a tela e a trava não têm como divergir: são a mesma
-- frase, lida do mesmo lugar.

create or replace function public.banca_pode_crescer(law_firm_id_value uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  teto int;
  advogados int;
begin
  -- SÓ QUEM É DA CASA PERGUNTA. A resposta conta se a banca está inadimplente,
  -- que é informação de dentro: qualquer pessoa autenticada podendo varrer
  -- escritórios para descobrir quais estão devendo seria um mapa de quem está
  -- em dificuldade, servido pela nossa API.
  if not exists (
    select 1
    from public.law_firm_members m
    where m.law_firm_id = law_firm_id_value
      and m.profile_id = (select auth.uid())
      and m.status = 'active'
  ) then
    raise exception 'Not a member of this law firm';
  end if;

  teto := public.teto_de_advogados(law_firm_id_value);

  -- Sem teto: banca de antes do licenciamento, ou plano negociado.
  if teto is null then
    return true;
  end if;

  if teto = 0 then
    return false;
  end if;

  select count(*) into advogados
  from public.law_firm_members m
  where m.law_firm_id = law_firm_id_value
    and m.status in ('active', 'invited')
    and 'lawyer' = any(coalesce(m.roles::text[], array[m.member_role::text]));

  return advogados < teto;
end;
$$;

revoke all on function public.banca_pode_crescer(uuid) from public, anon;
grant execute on function public.banca_pode_crescer(uuid) to authenticated;

comment on function public.banca_pode_crescer(uuid) is
  'A banca cabe mais um advogado? Mesma regra de exige_vaga_de_advogado, para as telas avisarem antes de o servidor recusar.';

notify pgrst, 'reload schema';
