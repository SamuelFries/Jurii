-- O logotipo do escritório vai para a revisão.
--
-- Aprovar um escritório PUBLICA a imagem que ele mandou: em
-- approve_law_firm_verification, avatar_storage_path vira law_firms.avatar_url,
-- que é o que o cliente vê na busca. Só que o painel da equipe nunca mostrou
-- essa imagem: as duas RPCs de revisão montavam a lista de documentos apenas
-- com law_firm_verification_documents, e o logotipo mora em outro balde.
--
-- Ou seja, a única peça que a decisão torna pública era a única que ninguém
-- olhava antes de decidir.
--
-- O balde law-firm-avatars é PÚBLICO (policy law_firm_avatars_public_read), o
-- que não muda nada de sigilo aqui: a imagem já era legível por qualquer um
-- que soubesse o caminho. O que muda é que agora ela aparece junto do resto.

-- ---------------------------------------------------------------------------
-- A lista de documentos do escritório, num lugar só
-- ---------------------------------------------------------------------------

-- INTERNA de propósito: nenhum grant de execute. As duas RPCs que a chamam são
-- SECURITY DEFINER de dono postgres, então lá dentro o usuário corrente já é
-- postgres e a chamada passa. Cliente nenhum alcança esta função, e por isso
-- ela não repete o is_jurii_staff() (quem cobra são as chamadoras, antes de
-- qualquer linha sair).
--
-- Existir separada é o ponto: a lista era escrita igual em dois lugares, e
-- corrigir um e esquecer o outro faria o histórico contar uma história
-- diferente da fila sobre a mesma verificação.
create or replace function public.law_firm_review_documents(
  verification_id_value uuid,
  avatar_storage_path_value text
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select
    -- O LOGOTIPO PRIMEIRO: é a peça que a aprovação publica, e quem revisa
    -- não deve precisar rolar até o fim para encontrá-la.
    case
      when avatar_storage_path_value is null then '[]'::jsonb
      else jsonb_build_array(
        jsonb_build_object(
          'tipo', 'profile_photo',
          'titulo', 'Foto de perfil do escritório',
          'caminho', avatar_storage_path_value,
          'bucket', 'law-firm-avatars'
        )
      )
    end
    ||
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'tipo', lvd.document_type,
            'titulo', lvd.title,
            'caminho', lvd.storage_path,
            -- MESMO balde do advogado: law_firm_verification_documents
            -- guarda o caminho escrito em verification-documents, que é
            -- privado. O balde do logotipo é outro, e vai acima.
            'bucket', 'verification-documents'
          )
          order by lvd.document_type
        )
        from public.law_firm_verification_documents lvd
        where lvd.verification_id = verification_id_value
      ),
      '[]'::jsonb
    );
$$;

revoke all on function public.law_firm_review_documents(uuid, text) from public;

-- ---------------------------------------------------------------------------
-- As duas RPCs passam a usar a lista completa
-- ---------------------------------------------------------------------------

-- `create or replace` e não drop+create: as colunas devolvidas são as mesmas,
-- muda só o CONTEÚDO de documents. Assim assinatura e grants ficam de pé, e o
-- webapp que já está no ar continua funcionando durante o deploy.
create or replace function public.fetch_pending_verifications()
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
  -- Advogados
  select
    'lawyer'::text,
    lv.id,
    lv.user_id,
    coalesce(p.full_name, 'Sem nome'),
    u.email::text,
    'OAB ' || coalesce(lv.oab_number, '?') || '/' || coalesce(lv.oab_state::text, '?'),
    coalesce(lv.practice_area, 'Sem área informada'),
    lv.status::text,
    lv.submitted_at,
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
    )
  from public.lawyer_verifications lv
  join public.profiles p on p.id = lv.user_id
  left join auth.users u on u.id = lv.user_id
  where lv.status = 'pending'

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
    lfv.created_at,
    public.law_firm_review_documents(lfv.id, lfv.avatar_storage_path)
  from public.law_firm_verifications lfv
  join public.profiles p on p.id = lfv.owner_profile_id
  left join auth.users u on u.id = lfv.owner_profile_id
  where lfv.status = 'pending'

  order by 9 asc nulls last;
end;
$$;

revoke all on function public.fetch_pending_verifications() from public;
grant execute on function public.fetch_pending_verifications() to authenticated;

-- Cópia fiel da 20260830120000: muda SÓ a expressão de documentos do
-- escritório. Aliases, ordenação e teto continuam idênticos de propósito,
-- para o diff mostrar a única coisa que está sendo decidida aqui.
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
      public.law_firm_review_documents(lfv.id, lfv.avatar_storage_path)
    from public.law_firm_verifications lfv
    join public.profiles p on p.id = lfv.owner_profile_id
    left join auth.users u on u.id = lfv.owner_profile_id
    left join public.profiles revisor on revisor.id = lfv.reviewer_id
    where lfv.status in ('approved', 'rejected')
  ) tudo
  order by tudo.reviewed_at desc nulls last, tudo.submitted_at desc
  limit greatest(1, least(limit_value, 200))
  offset greatest(0, offset_value);
end;
$$;

revoke all on function public.fetch_reviewed_verifications(int, int) from public;
grant execute on function public.fetch_reviewed_verifications(int, int) to authenticated;
