-- Revogar advogado tira ele do ar.
--
-- O DEFEITO, medido em 11/08/2026: reject_lawyer_verification era minuciosa
-- com os papeis de escritorio (derruba membership de advogado, limpa
-- lawyer_id, preserva papel administrativo) e NAO TOCAVA em lawyer_profiles.
-- O advogado revogado ficava com approved_at preenchido e is_available
-- true, entao continuava:
--   - na lista da descoberta (fetch_recommended_lawyers filtra so
--     is_available e deleted_at; usa approved_at apenas no ORDER BY),
--   - no perfil publico e nos favoritos.
-- Enquanto isso start_or_get_lawyer_conversation JA recusava abrir conversa
-- com ele, porque exige profiles.lawyer_status = 'approved'. Resultado:
-- anunciado ao cliente e inalcancavel no toque. Ninguem nunca viu, porque
-- nunca houve rejeicao: 41 verificacoes, 41 aprovadas, 0 rejeitadas. E
-- codigo nunca exercitado, nao codigo provado seguro.
--
-- POR QUE MEXER NA ORIGEM, E NAO GATEAR CADA FUNCAO: a descoberta, os
-- favoritos, a lista da equipe e o perfil publico ja filtram is_available.
-- Fazendo a revogacao derrubar essa coluna, as quatro passam a acertar de
-- uma vez, sem tocar no WHERE da funcao central da busca.
--
-- REVERSIVEL POR CONSTRUCAO: nada e apagado (bio, areas, foto, nota e
-- avaliacoes ficam), e a re-aprovacao devolve tudo, porque o upsert da
-- approve_lawyer_verification ja faz coalesce em approved_at. A unica
-- linha nova la devolve is_available SO para quem estava revogado, para
-- nao atropelar o advogado que se pausou sozinho.
--
-- MUDA UM ELO DA 20260826120000: aquela migration documentou que "nenhuma
-- funcao anula approved_at", e era verdade. Agora existe uma, e e esta.
-- approved_at nulo passa a TER SIGNIFICADO: nunca aprovado ou revogado. O
-- pgTAP da 20260826 foi atualizado para exigir que so a revogacao anule, em
-- vez de exigir zero.
--
-- As duas funcoes sao SECURITY DEFINER executaveis SOMENTE por
-- service_role (medido): sao operacao administrativa, nao caminho de
-- usuario. create or replace preserva assinatura, retorno e grants; os
-- corpos abaixo sao os de producao extraidos por pg_get_functiondef, com
-- as trocas marcadas em comentario.

CREATE OR REPLACE FUNCTION public.approve_lawyer_verification(verification_id_value uuid, reviewer_id_value uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  verification_row public.lawyer_verifications%rowtype;
  areas_value text[];
  primary_area_value text;
begin
  select *
  into verification_row
  from public.lawyer_verifications
  where id = verification_id_value;

  if not found then
    raise exception 'Lawyer verification not found: %', verification_id_value;
  end if;

  areas_value := coalesce(verification_row.practice_areas, '{}'::text[]);
  primary_area_value :=
    nullif(trim(coalesce(verification_row.practice_area, '')), '');

  if cardinality(areas_value) = 0 and primary_area_value is not null then
    areas_value := array[primary_area_value];
  end if;

  if primary_area_value is null and cardinality(areas_value) > 0 then
    primary_area_value := areas_value[1];
  end if;

  primary_area_value := coalesce(primary_area_value, 'Atendimento jurídico');

  update public.lawyer_verifications
  set
    status = 'approved',
    reviewed_at = now(),
    reviewer_id = reviewer_id_value,
    rejection_reason = null
  where id = verification_id_value;

  update public.profiles
  set lawyer_status = 'approved'
  where id = verification_row.user_id;

  insert into public.lawyer_profiles (
    id,
    oab_number,
    oab_state,
    primary_area,
    practice_areas,
    approved_at
  )
  values (
    verification_row.user_id,
    verification_row.oab_number,
    verification_row.oab_state,
    primary_area_value,
    areas_value,
    now()
  )
  on conflict (id) do update
  set
    oab_number = excluded.oab_number,
    oab_state = excluded.oab_state,
    primary_area = excluded.primary_area,
    practice_areas = excluded.practice_areas,
    approved_at = coalesce(
      public.lawyer_profiles.approved_at,
      excluded.approved_at
    ),
    -- Devolve ao ar SO quem estava revogado (approved_at nulo). Advogado
    -- que se pausou sozinho continua pausado: aprovar uma verificacao nova
    -- nao pode desfazer a escolha dele de nao atender.
    is_available = case
      when public.lawyer_profiles.approved_at is null then true
      else public.lawyer_profiles.is_available
    end;

  return verification_row.user_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.reject_lawyer_verification(verification_id_value uuid, reason_value text DEFAULT NULL::text, reviewer_id_value uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  verification_row public.lawyer_verifications%rowtype;
begin
  select *
  into verification_row
  from public.lawyer_verifications
  where id = verification_id_value;

  if not found then
    raise exception 'Lawyer verification not found: %', verification_id_value;
  end if;

  update public.lawyer_verifications
  set
    status = 'rejected',
    reviewed_at = now(),
    reviewer_id = reviewer_id_value,
    rejection_reason = nullif(trim(coalesce(reason_value, '')), '')
  where id = verification_id_value;

  update public.profiles
  set lawyer_status = 'client'
  where id = verification_row.user_id;

  -- O PERFIL TAMBEM SAI DO AR. Sem isto, revogar deixava lawyer_profiles
  -- intacto (approved_at cheio, is_available true) e o advogado revogado
  -- continuava na descoberta e no perfil publico, embora
  -- start_or_get_lawyer_conversation ja recusasse abrir conversa com ele:
  -- anunciado e inalcancavel ao mesmo tempo.
  --
  -- Anula approved_at (a re-aprovacao restaura, porque o upsert de
  -- approve_lawyer_verification faz coalesce do antigo com o novo) e
  -- derruba is_available, que e o que a descoberta de fato filtra. Nada e
  -- apagado: bio, areas, foto, nota e avaliacoes continuam onde estao.
  update public.lawyer_profiles
  set
    approved_at = null,
    is_available = false
  where id = verification_row.user_id;

  -- Revoga tambem a capacidade profissional dentro dos escritorios. Papeis
  -- administrativos independentes (owner/admin/secretary) sao preservados;
  -- membership exclusivamente de advogado e desativado.
  update public.law_firm_members
  set
    status = case
      when coalesce(
        array_length(array_remove(roles, 'lawyer'), 1),
        0
      ) = 0 then 'disabled'::public.law_firm_member_status
      else status
    end,
    roles = case
      when coalesce(
        array_length(array_remove(roles, 'lawyer'), 1),
        0
      ) = 0 then roles
      else public.normalize_law_firm_member_roles(
        array_remove(roles, 'lawyer')
      )
    end,
    lawyer_id = null,
    pending_lawyer_id = null,
    lawyer_invite_status = 'disabled'
  where (
      profile_id = verification_row.user_id
      or lawyer_id = verification_row.user_id
      or pending_lawyer_id = verification_row.user_id
    )
    and (
      'lawyer' = any(roles)
      or lawyer_invite_status = 'invited'
    );

  return verification_row.user_id;
end;
$function$;
