-- Avaliacao: ninguem avalia a si mesmo nem o proprio escritorio
--
-- Cenario real (teste do Samuel, 29/07): a mesma conta operando como cliente
-- e como advogado consegue ter caso aceito "consigo mesma" — e ai o gate de
-- avaliacao (caso aceito com o profissional) libera a autoavaliacao. O mesmo
-- vale para membros de escritorio avaliando a propria banca: qualquer membro
-- ativo com um caso como cliente da firma passaria no gate.
--
-- Fix num ponto so: can_review_professional e o predicado unico usado pela
-- submissao (submit_professional_review) E pela elegibilidade que decide se
-- o botao "Avaliar" aparece (fetch_review_eligibility). Guardas novas:
--   - alvo advogado: o proprio advogado (auth.uid() = lawyer_profiles.id,
--     que e o id do profile) nao avalia;
--   - alvo escritorio: membro ATIVO do escritorio (qualquer papel: dono,
--     admin, advogado, secretaria) nao avalia. Ex-membros podem — nao sao
--     mais parte da banca.
--
-- Corpo VERBATIM da definicao vigente (20260713120000:132), so com as duas
-- guardas adicionadas. submit/eligibility nao mudam: delegam ao predicado.

create or replace function public.can_review_professional(
  target_type_value text,
  target_id_value uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when target_type_value = 'lawyer' then (
      target_id_value is distinct from auth.uid()
      and (
        exists (
          select 1 from public.legal_cases lc
          where lc.client_id = auth.uid()
            and lc.assigned_lawyer_id = target_id_value
        )
        or exists (
          select 1 from public.case_requests cr
          where cr.client_id = auth.uid()
            and cr.lawyer_id = target_id_value
            and cr.status = 'accepted'
        )
      )
    )
    when target_type_value = 'law_firm' then (
      not exists (
        select 1 from public.law_firm_members lfm
        where lfm.law_firm_id = target_id_value
          and lfm.profile_id = auth.uid()
          and lfm.status = 'active'
      )
      and (
        exists (
          select 1 from public.legal_cases lc
          where lc.client_id = auth.uid()
            and lc.law_firm_id = target_id_value
        )
        or exists (
          select 1 from public.case_requests cr
          where cr.client_id = auth.uid()
            and cr.law_firm_id = target_id_value
            and cr.status = 'accepted'
        )
      )
    )
    else false
  end;
$$;

revoke all on function public.can_review_professional(text, uuid)
  from public, anon;
grant execute on function public.can_review_professional(text, uuid)
  to authenticated;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Verificacao pos-push (SQL Editor):
--   select prosrc like '%is distinct from auth.uid()%'
--   from pg_proc where proname = 'can_review_professional';  -- true
-- ---------------------------------------------------------------------------
