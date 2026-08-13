-- Quem foi analisado FICA SABENDO.
--
-- O DEFEITO: approve_lawyer_verification, reject_lawyer_verification e as
-- irmãs do escritório não criam notificação nenhuma (medido em
-- 13/08/2026). A pessoa envia os documentos e fica esperando em silêncio:
-- só descobre a decisão se voltar sozinha e abrir a tela. Num processo que
-- leva dias úteis e decide se ela pode trabalhar na plataforma, isso é o
-- pior lugar possível para o produto ficar mudo.
--
-- ONDE O AVISO ENTRA: nos invólucros de revisão, e não dentro das
-- approve_/reject_. Assim as funções que o app já usa continuam com o
-- comportamento que sempre tiveram, e quem avisa é o caminho novo, usado
-- pelo painel da equipe.
--
-- O ESCOPO segue o estado em que a pessoa FICA: aprovado vira 'lawyer'
-- (ele passa a ter área de advogado, e é lá que a notificação aparece);
-- recusado volta a 'client', que é o escopo que o aplicativo mostra para
-- quem não é profissional.

create or replace function public.review_lawyer_verification(
  verification_id_value uuid,
  approve_value boolean,
  reason_value text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  alvo uuid;
  motivo text;
begin
  if not public.is_jurii_staff() then
    raise exception 'Only Jurii staff can review verifications';
  end if;

  if approve_value then
    alvo := public.approve_lawyer_verification(verification_id_value, auth.uid());

    insert into public.notifications
      (recipient_profile_id, actor_profile_id, type, title, body, scope, metadata)
    values (
      alvo,
      auth.uid(),
      'verification_approved',
      'Sua verificação foi aprovada',
      'Sua área de advogado já está liberada na Jurii.',
      'lawyer',
      '{}'::jsonb
    );

    return alvo;
  end if;

  motivo := nullif(trim(coalesce(reason_value, '')), '');
  if motivo is null then
    raise exception 'Rejection reason is required';
  end if;

  alvo := public.reject_lawyer_verification(
    verification_id_value,
    motivo,
    auth.uid()
  );

  -- O MOTIVO VAI NO CORPO da notificação, e não só na tela de
  -- verificação: quem recebe precisa saber o que corrigir sem ter que
  -- caçar onde estava escrito.
  insert into public.notifications
    (recipient_profile_id, actor_profile_id, type, title, body, scope, metadata)
  values (
    alvo,
    auth.uid(),
    'verification_rejected',
    'Sua verificação precisa de ajustes',
    motivo,
    'client',
    jsonb_build_object('rejection_reason', motivo)
  );

  return alvo;
end;
$$;

create or replace function public.review_law_firm_verification(
  verification_id_value uuid,
  approve_value boolean,
  reason_value text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  dono uuid;
  motivo text;
begin
  if not public.is_jurii_staff() then
    raise exception 'Only Jurii staff can review verifications';
  end if;

  select owner_profile_id into dono
  from public.law_firm_verifications
  where id = verification_id_value;

  if approve_value then
    perform public.approve_law_firm_verification(
      verification_id_value,
      auth.uid()
    );

    if dono is not null then
      insert into public.notifications
        (recipient_profile_id, actor_profile_id, type, title, body, scope, metadata)
      values (
        dono,
        auth.uid(),
        'verification_approved',
        'Seu escritório foi aprovado',
        'O painel do escritório já está liberado na Jurii.',
        'lawyer',
        '{}'::jsonb
      );
    end if;

    return dono;
  end if;

  motivo := nullif(trim(coalesce(reason_value, '')), '');
  if motivo is null then
    raise exception 'Rejection reason is required';
  end if;

  perform public.reject_law_firm_verification(
    verification_id_value,
    motivo,
    auth.uid()
  );

  if dono is not null then
    insert into public.notifications
      (recipient_profile_id, actor_profile_id, type, title, body, scope, metadata)
    values (
      dono,
      auth.uid(),
      'verification_rejected',
      'O pedido do escritório precisa de ajustes',
      motivo,
      'client',
      jsonb_build_object('rejection_reason', motivo)
    );
  end if;

  return dono;
end;
$$;

revoke all on function public.review_lawyer_verification(uuid, boolean, text) from public;
grant execute on function public.review_lawyer_verification(uuid, boolean, text) to authenticated;
revoke all on function public.review_law_firm_verification(uuid, boolean, text) from public;
grant execute on function public.review_law_firm_verification(uuid, boolean, text) to authenticated;

notify pgrst, 'reload schema';
