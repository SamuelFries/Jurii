-- O histórico das verificações já decididas.
--
-- POR QUE EXISTE: até aqui a equipe só via a fila do que falta. Decidido
-- virava invisível, e com ele foi embora a resposta de três perguntas que
-- aparecem sempre num processo que mexe com carteira profissional: por que
-- fulano foi recusado, quem decidiu, e quando.
--
-- O reviewer_id já era gravado desde a 20260828120000; faltava um jeito de
-- ler. A função devolve o NOME de quem decidiu, e não só o id, porque
-- auditoria que exige uma segunda consulta para virar frase não é lida.
--
-- LIMITE E PAGINAÇÃO: a fila esvazia sozinha, o histórico não. Sem teto,
-- um ano de operação viraria uma consulta que ninguém quer rodar. O
-- chamador manda quantas quer e de onde continuar.

create or replace function public.fetch_reviewed_verifications(
  limit_value int default 50,
  offset_value int default 0
)
returns table (
  kind text,
  id uuid,
  subject_id uuid,
  person_name text,
  person_email text,
  title text,
  detail text,
  status text,
  submitted_at timestamptz,
  reviewed_at timestamptz,
  reviewer_name text,
  rejection_reason text,
  documents jsonb
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_jurii_staff() then
    raise exception 'Only Jurii staff can review verifications';
  end if;

  return query
  select * from (
    -- Advogados
    select
      'lawyer'::text as kind,
      lv.id,
      lv.user_id as subject_id,
      coalesce(p.full_name, 'Sem nome') as person_name,
      u.email::text as person_email,
      'OAB ' || coalesce(lv.oab_number, '?') || '/' || coalesce(lv.oab_state::text, '?') as title,
      coalesce(lv.practice_area, 'Sem área informada') as detail,
      lv.status::text as status,
      lv.submitted_at,
      lv.reviewed_at,
      -- Quem decidiu, pelo nome. Nulo quando a decisão veio de antes do
      -- painel existir (as 81 aprovações feitas pelo dashboard).
      revisor.full_name as reviewer_name,
      lv.rejection_reason,
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'tipo', vd.document_type,
              'titulo', vd.title,
              'caminho', vd.storage_path,
              'bucket', 'verification-documents'
            )
            order by vd.document_type
          )
          from public.verification_documents vd
          where vd.verification_id = lv.id
        ),
        '[]'::jsonb
      ) as documents
    from public.lawyer_verifications lv
    join public.profiles p on p.id = lv.user_id
    left join auth.users u on u.id = lv.user_id
    left join public.profiles revisor on revisor.id = lv.reviewer_id
    where lv.status in ('approved', 'rejected')

    union all

    -- Escritórios
    select
      'law_firm'::text,
      lfv.id,
      lfv.owner_profile_id,
      coalesce(p.full_name, 'Sem nome'),
      coalesce(lfv.email, u.email::text),
      coalesce(lfv.firm_name, 'Escritório sem nome'),
      'CNPJ ' || coalesce(lfv.cnpj, '?'),
      lfv.status::text,
      lfv.submitted_at,
      lfv.reviewed_at,
      revisor.full_name,
      lfv.rejection_reason,
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'tipo', lvd.document_type,
              'titulo', lvd.title,
              'caminho', lvd.storage_path,
              'bucket', 'verification-documents'
            )
            order by lvd.document_type
          )
          from public.law_firm_verification_documents lvd
          where lvd.verification_id = lfv.id
        ),
        '[]'::jsonb
      )
    from public.law_firm_verifications lfv
    join public.profiles p on p.id = lfv.owner_profile_id
    left join auth.users u on u.id = lfv.owner_profile_id
    left join public.profiles revisor on revisor.id = lfv.reviewer_id
    where lfv.status in ('approved', 'rejected')
  ) tudo
  -- A decisão mais recente primeiro: o histórico é consultado de trás para
  -- frente. `nulls last` porque decisão antiga pode não ter data.
  order by tudo.reviewed_at desc nulls last, tudo.submitted_at desc
  limit greatest(1, least(limit_value, 200))
  offset greatest(0, offset_value);
end;
$$;

revoke all on function public.fetch_reviewed_verifications(int, int) from public;
grant execute on function public.fetch_reviewed_verifications(int, int) to authenticated;

-- Quantas já foram decididas, para a tela saber se há mais páginas sem
-- pedir a lista inteira.
create or replace function public.count_reviewed_verifications()
returns int
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  total int;
begin
  if not public.is_jurii_staff() then
    raise exception 'Only Jurii staff can review verifications';
  end if;

  select
    (select count(*) from public.lawyer_verifications where status in ('approved','rejected'))
    + (select count(*) from public.law_firm_verifications where status in ('approved','rejected'))
  into total;

  return total;
end;
$$;

revoke all on function public.count_reviewed_verifications() from public;
grant execute on function public.count_reviewed_verifications() to authenticated;

notify pgrst, 'reload schema';
