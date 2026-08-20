-- O selo diz o que é.
--
-- A fila de pedidos de entrada mostrava "CPF confirmado" para quem decide
-- aprovar alguém na equipe. Mas nada confirma esse CPF: ele é digitado no
-- cadastro e só passa por dígito verificador (is_valid_cpf). Não há consulta
-- à Receita, nem documento, nem selfie. O gestor lia "confirmado" e aprovava
-- achando que a plataforma tinha checado a identidade, que é exatamente a
-- decisão que o selo deveria informar, não enfeitar.
--
-- O dado continua útil (perfil sem CPF é mais provável de ser conta de
-- passagem), então o que muda é o nome: cpf_informado. Quem quiser
-- verificação de identidade de verdade precisa construí-la; até lá, a tela
-- não promete o que o banco não sabe.
--
-- Trocar o nome de uma coluna de retorno exige derrubar e recriar a função:
-- create or replace recusa a mudança.

drop function if exists public.listar_pedidos_de_entrada(uuid);

create or replace function public.listar_pedidos_de_entrada(law_firm_id_value uuid)
returns table (
  id uuid,
  requester_name text,
  requester_email text,
  cpf_informado boolean,
  member_role text,
  created_at timestamptz,
  expires_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;
  if not public.is_active_law_firm_manager(law_firm_id_value) then
    raise exception 'Only active office owners and admins can list requests';
  end if;

  return query
  select r.id,
         coalesce(p.full_name, 'Sem nome'),
         coalesce(p.email, ''),
         -- INFORMADO, não confirmado: o CPF é digitado no cadastro e passa
         -- só por dígito verificador. Vai como booleano porque o número não
         -- é da conta do gestor.
         (p.cpf is not null and length(regexp_replace(p.cpf, '\D', '', 'g')) = 11),
         r.member_role, r.created_at, r.expires_at
  from public.law_firm_join_requests r
  join public.profiles p on p.id = r.requester_id
  where r.law_firm_id = law_firm_id_value
    and r.status = 'pending'
    and r.expires_at > now()
  order by r.created_at asc;
end;
$$;

revoke all on function public.listar_pedidos_de_entrada(uuid) from public, anon;
grant execute on function public.listar_pedidos_de_entrada(uuid) to authenticated;
