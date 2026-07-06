-- Patch 041 — Hardening de segurança (auditoria jul/2026).
--
-- Corrige os furos de RLS/privilégios encontrados na auditoria:
--   1. Auto-promoção a advogado: qualquer usuário podia dar UPDATE em
--      profiles.lawyer_status='approved' (grant amplo do patch_005) e inserir
--      a própria linha em lawyer_profiles, furando a verificação OAB.
--   2. Vazamento de PII (LGPD): a policy profiles_select_approved_lawyers_public
--      expunha a linha INTEIRA de profiles (cpf, phone, email) de todo advogado
--      aprovado para qualquer usuário autenticado.
--   3. Auto-aprovação de verificações: o WITH CHECK das policies de UPDATE de
--      lawyer_verifications/law_firm_verifications não impedia o próprio autor
--      de setar status='approved'.
--   4. Spoofing de sender_type: cliente podia inserir mensagem como
--      'system'/'lawyer' (engenharia social no chat).
--   5. verification_documents aceitava insert apontando para verificação alheia.
--   6. Bucket chat-attachments sem limite de tamanho/tipo no Storage (o RPC
--      valida, mas upload direto pela Storage API não passava pelo RPC).
--   7. Typo público "(delleted account)" → "(conta excluída)".
--
-- Rodar após o patch_040. Não remove dados; apenas policies/grants/config.
-- Reversível: cada bloco documenta o estado anterior.

-- ---------------------------------------------------------------------------
-- 1. profiles: privilégios por coluna.
--    Antes: grant select,insert,update on profiles to authenticated (patch_005)
--    permitia escrever lawyer_status/member_since diretamente.
--    As funções SECURITY DEFINER (handle_new_auth_user, approve_lawyer_verification,
--    delete_current_account etc.) não são afetadas — rodam como owner.
-- ---------------------------------------------------------------------------

revoke insert, update on public.profiles from authenticated;
revoke select on public.profiles from anon;

grant insert (id, full_name, email, initials, cpf, phone, avatar_url)
on public.profiles to authenticated;

grant update (full_name, email, initials, cpf, phone, avatar_url)
on public.profiles to authenticated;

-- ---------------------------------------------------------------------------
-- 2. profiles: remove a policy que expunha a linha inteira (cpf/phone/email)
--    de advogados aprovados a qualquer autenticado. Os cards e entrypoints do
--    app usam RPCs SECURITY DEFINER (fetch_recommended_lawyers,
--    fetch_chat_profile, start_or_get_lawyer_conversation), que continuam
--    funcionando e retornam apenas campos não sensíveis.
-- ---------------------------------------------------------------------------

drop policy if exists "profiles_select_approved_lawyers_public"
on public.profiles;

-- ---------------------------------------------------------------------------
-- 3. lawyer_profiles: fim do self-service de perfil profissional.
--    A criação passa a ocorrer somente via fluxo de aprovação/convite
--    (funções SECURITY DEFINER). O advogado poderá editar apenas campos
--    não privilegiados do próprio perfil (bio, áreas, foto, disponibilidade)
--    quando a tela de edição existir.
-- ---------------------------------------------------------------------------

drop policy if exists "lawyer_profiles_insert_own" on public.lawyer_profiles;

revoke insert, update on public.lawyer_profiles from authenticated;

grant update (bio, practice_areas, is_available, professional_photo_url)
on public.lawyer_profiles to authenticated;

-- ---------------------------------------------------------------------------
-- 4. lawyer_verifications: o autor pode editar a própria verificação em
--    rascunho/pendente, mas nunca mudar status para aprovado nem preencher
--    campos de revisão. Aprovação continua exclusiva de
--    approve_lawyer_verification (service_role).
-- ---------------------------------------------------------------------------

drop policy if exists "lawyer_verifications_update_own_pending"
on public.lawyer_verifications;

create policy "lawyer_verifications_update_own_pending"
on public.lawyer_verifications for update
to authenticated
using (user_id = auth.uid() and status in ('draft', 'pending'))
with check (
  user_id = auth.uid()
  and status in ('draft', 'pending')
  and reviewer_id is null
  and reviewed_at is null
);

-- Mesmo endurecimento para verificações de escritório (patch_004 só checava
-- owner_profile_id no WITH CHECK).

drop policy if exists "law_firm_verifications_update_own_pending"
on public.law_firm_verifications;

create policy "law_firm_verifications_update_own_pending"
on public.law_firm_verifications for update
to authenticated
using (owner_profile_id = auth.uid() and status in ('draft', 'pending'))
with check (
  owner_profile_id = auth.uid()
  and status in ('draft', 'pending')
);

-- ---------------------------------------------------------------------------
-- 5. verification_documents: o insert precisa apontar para uma verificação do
--    próprio usuário (antes bastava user_id = auth.uid(), permitindo poluir a
--    verificação de terceiros). Idem para documentos de escritório.
-- ---------------------------------------------------------------------------

drop policy if exists "verification_documents_insert_own"
on public.verification_documents;

create policy "verification_documents_insert_own"
on public.verification_documents for insert
to authenticated
with check (
  user_id = auth.uid()
  and exists (
    select 1
    from public.lawyer_verifications lv
    where lv.id = verification_documents.verification_id
      and lv.user_id = auth.uid()
  )
);

drop policy if exists "law_firm_verification_documents_insert_own"
on public.law_firm_verification_documents;

create policy "law_firm_verification_documents_insert_own"
on public.law_firm_verification_documents for insert
to authenticated
with check (
  owner_profile_id = auth.uid()
  and exists (
    select 1
    from public.law_firm_verifications lfv
    where lfv.id = law_firm_verification_documents.verification_id
      and lfv.owner_profile_id = auth.uid()
  )
);

-- ---------------------------------------------------------------------------
-- 6. messages: sender_type precisa corresponder ao papel real do remetente.
--    'client' apenas para o client_id da conversa; 'lawyer' apenas para quem
--    tem acesso e NÃO é o cliente; 'system' nunca via insert direto (somente
--    RPCs SECURITY DEFINER, que não passam por esta policy).
-- ---------------------------------------------------------------------------

drop policy if exists "messages_insert_related" on public.messages;

create policy "messages_insert_related"
on public.messages for insert
to authenticated
with check (
  sender_id = auth.uid()
  and public.can_access_conversation(messages.conversation_id)
  and (
    (
      sender_type = 'client'
      and exists (
        select 1
        from public.conversations c
        where c.id = messages.conversation_id
          and c.client_id = auth.uid()
      )
    )
    or (
      sender_type = 'lawyer'
      and exists (
        select 1
        from public.conversations c
        where c.id = messages.conversation_id
          and c.client_id is distinct from auth.uid()
      )
    )
  )
);

-- ---------------------------------------------------------------------------
-- 7. Storage: aplica no bucket os mesmos limites que o RPC
--    send_chat_attachment valida (upload direto pela Storage API deixava
--    passar qualquer tipo/tamanho).
-- ---------------------------------------------------------------------------

update storage.buckets
set
  file_size_limit = 10485760,
  allowed_mime_types = array[
    'image/jpeg',
    'image/png',
    'image/webp',
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
  ]
where id = 'chat-attachments';

-- ---------------------------------------------------------------------------
-- 8. Correção do sufixo público de conta excluída (typo + idioma).
--    Recria a função de exibição e corrige títulos já gravados.
-- ---------------------------------------------------------------------------

create or replace function public.profile_display_name(
  full_name_value text,
  deleted_at_value timestamptz,
  deleted_display_name_value text
)
returns text
language sql
immutable
as $$
  select case
    when deleted_at_value is not null then
      coalesce(
        nullif(trim(deleted_display_name_value), ''),
        nullif(trim(full_name_value), ''),
        'Usuário'
      ) || ' (conta excluída)'
    else
      coalesce(nullif(trim(full_name_value), ''), 'Usuário Jurii')
  end;
$$;

update public.conversations
set title = replace(title, ' (delleted account)', ' (conta excluída)')
where title like '% (delleted account)';

-- A função delete_current_account concatena o sufixo em conversations.title;
-- recria apenas o trecho? Não: a função inteira vive no patch_035. Para não
-- duplicar 300 linhas aqui, o texto novo passa a valer para exibição via
-- profile_display_name; o UPDATE acima corrige os títulos persistidos.
-- PENDÊNCIA: ao editar o patch_035 novamente, trocar o literal
-- ' (delleted account)' por ' (conta excluída)' dentro de
-- delete_current_account (linha ~226).

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Verificação pós-patch (rodar como usuário de teste autenticado):
--   update public.profiles set lawyer_status='approved' where id = auth.uid();
--     → deve falhar com "permission denied for table profiles".
--   select cpf from public.profiles where id <> auth.uid() limit 1;
--     → deve retornar 0 linhas para advogados não relacionados.
--   update public.lawyer_verifications set status='approved'
--     where user_id = auth.uid();
--     → deve falhar pela policy (WITH CHECK).
--   insert into public.messages (conversation_id, sender_id, sender_type, body)
--     values ('<conversa própria>', auth.uid(), 'system', 'x');
--     → deve falhar pela policy.
-- ---------------------------------------------------------------------------
