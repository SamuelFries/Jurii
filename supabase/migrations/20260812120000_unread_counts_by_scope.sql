-- Quantas notificacoes esperam em CADA fluxo, numa consulta so.
--
-- O app tem tres fluxos (cliente, advogado, escritorio) e o sino de cada um
-- conta apenas o proprio escopo. Consequencia: quem esta no modo cliente NAO
-- FICA SABENDO que chegou uma solicitacao de caso no modo advogado. Para um
-- usuario que tem os tres, isso nao e atrito de navegacao — e lead perdido,
-- porque ele so descobre quando lembra de trocar de modo.
--
-- Esta funcao existe para o seletor de modo poder marcar onde ha algo
-- esperando. Uma ida ao servidor em vez de tres (uma por escopo), e contagem
-- feita no banco em vez de materializar as linhas so para medir o tamanho.
--
-- Devolve SEMPRE os tres escopos, inclusive com zero: assim o app desenha a
-- lista de modos direto do resultado, sem precisar preencher buraco.

create or replace function public.fetch_unread_notification_counts(
  law_firm_id_value uuid default null
)
returns table (scope text, unread integer)
language sql
stable
security definer
set search_path = public
as $$
  with escopos(nome) as (
    values ('client'), ('lawyer'), ('firm')
  )
  select
    escopos.nome,
    coalesce((
      select count(*)::integer
      from public.notifications n
      where n.recipient_profile_id = auth.uid()
        and n.read_at is null
        and n.scope::text = escopos.nome
        -- Escritorio: quem participa de mais de um so quer o do escritorio
        -- que esta aberto. Sem o filtro, o contador do seletor mostraria a
        -- soma de todos e nao bateria com o sino de dentro do modo.
        and (
          escopos.nome <> 'firm'
          or law_firm_id_value is null
          or n.law_firm_id = law_firm_id_value
        )
    ), 0)
  from escopos
  where auth.uid() is not null;
$$;

revoke all on function public.fetch_unread_notification_counts(uuid)
from public, anon;

grant execute on function public.fetch_unread_notification_counts(uuid)
to authenticated;

notify pgrst, 'reload schema';
