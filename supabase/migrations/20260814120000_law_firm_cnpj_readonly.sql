-- CNPJ visivel (e so isso) na edicao do cadastro do escritorio.
--
-- O CNPJ nao esta em law_firms: ele vive em law_firm_verifications, porque e
-- dado VERIFICADO e nao cadastro editavel. A tela de edicao precisa mostra-lo
-- — sem ele, a ausencia parece esquecimento em vez de decisao, e o gestor fica
-- sem conferir de qual CNPJ aquele escritorio e.
--
-- POR QUE UMA RPC, E NAO UMA COLUNA EM law_firms: copiar o CNPJ para a tabela
-- do escritorio o colocaria a um `select` de distancia de vazar nos RPCs de
-- descoberta, que devolvem law_firms para QUALQUER cliente autenticado. Aqui
-- ele so sai para quem ja pode editar o cadastro — o mesmo portao da
-- apresentacao, do painel de alcance e da propria edicao.

create or replace function public.fetch_law_firm_cnpj(law_firm_id_value uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select verification.cnpj
  from public.law_firm_verifications verification
  where verification.law_firm_id = law_firm_id_value
    and verification.status = 'approved'
    and public.is_active_law_firm_manager(law_firm_id_value)
  -- Uma firma pode ter mais de uma verificacao no historico (recusada e
  -- refeita); vale a aprovada mais recente.
  order by verification.reviewed_at desc nulls last, verification.id
  limit 1;
$$;

revoke all on function public.fetch_law_firm_cnpj(uuid) from public, anon;
grant execute on function public.fetch_law_firm_cnpj(uuid) to authenticated;

notify pgrst, 'reload schema';
