-- Revisao de performance do SQL: RLS por linha e indices de chave estrangeira
--
-- MEDIDO, nao chutado. Duas fontes de evidencia em producao (30/07):
--   1. `supabase db advisors --type performance`: 29 avisos, sendo 28 do
--      mesmo tipo (auth_rls_initplan) e 1 de politicas permissivas duplicadas.
--   2. Consulta ao catalogo: 25 chaves estrangeiras sem indice de apoio.
--
-- NAO ha reescrita de funcao aqui. As 88 funcoes do schema nao apresentaram
-- problema medido, e reescrever em massa "para melhorar" e justamente onde
-- mora o risco de trocar comportamento sem querer.
--
-- ---------------------------------------------------------------------------
-- 1. auth.uid() reavaliado POR LINHA (28 policies)
--
-- Numa policy, `auth.uid()` sem envolver e tratado como volatil e executado
-- uma vez POR LINHA avaliada; envolvido em `(select ...)` o planejador o trata
-- como InitPlan e executa UMA vez por consulta. Em varredura de N linhas isso
-- e a diferenca entre N chamadas e 1. E a recomendacao da propria Supabase
-- (lint 0003_auth_rls_initplan).
--
-- Semanticamente identico: `auth.uid()` e estavel dentro da transacao.
--
-- Os comandos abaixo foram GERADOS a partir de `pg_policies` (a expressao
-- vigente de cada policy, com a substituicao aplicada), nao redigidos a mao —
-- policy de RLS e o pior lugar possivel para um erro de transcricao.
-- ---------------------------------------------------------------------------

alter policy "appointments_select_related" on public.appointments
  using (((client_id = (select auth.uid())) OR (lawyer_id = (select auth.uid()))));

alter policy "case_documents_insert_related" on public.case_documents
  with check (((uploaded_by = (select auth.uid())) AND can_access_case(case_id)));

alter policy "case_documents_select_related" on public.case_documents
  using (((uploaded_by = (select auth.uid())) OR can_access_case(case_id)));

alter policy "case_participants_select_related" on public.case_participants
  using (((profile_id = (select auth.uid())) OR can_access_case(case_id)));

alter policy "case_requests_select_related" on public.case_requests
  using (((client_id = (select auth.uid())) OR (lawyer_id = (select auth.uid())) OR (requested_by_profile_id = (select auth.uid())) OR ((law_firm_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM law_firm_members lfm
  WHERE ((lfm.law_firm_id = case_requests.law_firm_id) AND (lfm.profile_id = (select auth.uid())) AND (lfm.status = 'active'::law_firm_member_status)))))));

alter policy "case_updates_insert_professional" on public.case_updates
  with check (((author_profile_id = (select auth.uid())) AND can_manage_case_updates(case_id)));

alter policy "law_firm_members_read_related" on public.law_firm_members
  using (((profile_id = (select auth.uid())) OR (lawyer_id = (select auth.uid())) OR (pending_lawyer_id = (select auth.uid())) OR (COALESCE(array_length(current_law_firm_member_roles(law_firm_id, (select auth.uid())), 1), 0) > 0)));

alter policy "law_firm_verification_documents_insert_own" on public.law_firm_verification_documents
  with check (((owner_profile_id = (select auth.uid())) AND (EXISTS ( SELECT 1
   FROM law_firm_verifications lfv
  WHERE ((lfv.id = law_firm_verification_documents.verification_id) AND (lfv.owner_profile_id = (select auth.uid())))))));

alter policy "law_firm_verification_documents_select_own" on public.law_firm_verification_documents
  using ((owner_profile_id = (select auth.uid())));

alter policy "law_firm_verifications_insert_own" on public.law_firm_verifications
  with check (((owner_profile_id = (select auth.uid())) AND (status = ANY (ARRAY['draft'::verification_status, 'pending'::verification_status])) AND (law_firm_id IS NULL) AND (avatar_storage_path IS NULL) AND (reviewer_id IS NULL) AND (reviewed_at IS NULL) AND (rejection_reason IS NULL)));

alter policy "law_firm_verifications_select_own" on public.law_firm_verifications
  using ((owner_profile_id = (select auth.uid())));

alter policy "law_firm_verifications_update_own_pending" on public.law_firm_verifications
  using (((owner_profile_id = (select auth.uid())) AND (status = ANY (ARRAY['draft'::verification_status, 'pending'::verification_status]))))
  with check (((owner_profile_id = (select auth.uid())) AND (status = ANY (ARRAY['draft'::verification_status, 'pending'::verification_status])) AND (law_firm_id IS NULL) AND (reviewer_id IS NULL) AND (reviewed_at IS NULL) AND (rejection_reason IS NULL)));

alter policy "lawyer_profiles_public_read_approved" on public.lawyer_profiles
  using (((id = (select auth.uid())) OR (approved_at IS NOT NULL)));

alter policy "lawyer_profiles_update_own" on public.lawyer_profiles
  using ((id = (select auth.uid())))
  with check ((id = (select auth.uid())));

alter policy "lawyer_verifications_insert_own" on public.lawyer_verifications
  with check ((user_id = (select auth.uid())));

alter policy "lawyer_verifications_select_own" on public.lawyer_verifications
  using ((user_id = (select auth.uid())));

alter policy "lawyer_verifications_update_own_pending" on public.lawyer_verifications
  using (((user_id = (select auth.uid())) AND (status = ANY (ARRAY['draft'::verification_status, 'pending'::verification_status]))))
  with check (((user_id = (select auth.uid())) AND (status = ANY (ARRAY['draft'::verification_status, 'pending'::verification_status])) AND (reviewer_id IS NULL) AND (reviewed_at IS NULL)));

alter policy "legal_cases_insert_as_client" on public.legal_cases
  with check ((client_id = (select auth.uid())));

alter policy "message_attachments_insert_related" on public.message_attachments
  with check (((uploaded_by = (select auth.uid())) AND can_access_conversation(conversation_id) AND (storage_path ~~ (((select auth.uid()))::text || '/%'::text)) AND (EXISTS ( SELECT 1
   FROM messages m
  WHERE ((m.id = message_attachments.message_id) AND (m.conversation_id = message_attachments.conversation_id))))));

alter policy "messages_insert_related" on public.messages
  with check (((sender_id = (select auth.uid())) AND can_access_conversation(conversation_id) AND (((sender_type = 'client'::message_sender_type) AND (EXISTS ( SELECT 1
   FROM conversations c
  WHERE ((c.id = messages.conversation_id) AND (c.client_id = (select auth.uid())))))) OR ((sender_type = 'lawyer'::message_sender_type) AND (EXISTS ( SELECT 1
   FROM conversations c
  WHERE ((c.id = messages.conversation_id) AND (c.client_id IS DISTINCT FROM (select auth.uid())))))))));

alter policy "notifications_delete_own" on public.notifications
  using ((recipient_profile_id = (select auth.uid())));

alter policy "notifications_select_own" on public.notifications
  using ((recipient_profile_id = (select auth.uid())));

alter policy "notifications_update_own" on public.notifications
  using ((recipient_profile_id = (select auth.uid())))
  with check ((recipient_profile_id = (select auth.uid())));

alter policy "profiles_insert_own" on public.profiles
  with check ((id = (select auth.uid())));

alter policy "profiles_select_own" on public.profiles
  using ((id = (select auth.uid())));

alter policy "profiles_update_own" on public.profiles
  using (((id = (select auth.uid())) AND (deleted_at IS NULL)))
  with check (((id = (select auth.uid())) AND (deleted_at IS NULL)));

alter policy "verification_documents_insert_own" on public.verification_documents
  with check (((user_id = (select auth.uid())) AND (EXISTS ( SELECT 1
   FROM lawyer_verifications lv
  WHERE ((lv.id = verification_documents.verification_id) AND (lv.user_id = (select auth.uid())))))));

alter policy "verification_documents_select_own" on public.verification_documents
  using ((user_id = (select auth.uid())));

-- ---------------------------------------------------------------------------
-- 2. Chaves estrangeiras sem indice
--
-- Duas dores distintas, ambas reais aqui:
--   (a) DELETE no pai varre o filho inteiro. O caminho de exclusao de conta
--       (LGPD) ja existe e cascateia por quase todas estas tabelas.
--   (b) Filtro/junção por essas colunas em funcao viva — `legal_cases.law_firm_id`
--       (fetch_law_firm_cases), `case_participants.profile_id` (can_access_case,
--       avaliado em TODO acesso a caso), `notifications.law_firm_id` (o sino do
--       escritorio filtra por ele).
--
-- Fora da lista de proposito: `law_firm_categories.category_id` (tabela de
-- vinculo minuscula, sem cascade e sem uso em consulta).
-- ---------------------------------------------------------------------------

create index if not exists appointments_case_id_idx on public.appointments(case_id);
create index if not exists appointments_law_firm_id_idx on public.appointments(law_firm_id);
create index if not exists case_documents_case_id_idx on public.case_documents(case_id);
create index if not exists case_documents_uploaded_by_idx on public.case_documents(uploaded_by);
create index if not exists case_participants_profile_id_idx on public.case_participants(profile_id);
create index if not exists case_requests_law_firm_id_idx on public.case_requests(law_firm_id);
create index if not exists case_requests_lawyer_id_idx on public.case_requests(lawyer_id);
create index if not exists case_requests_legal_case_id_idx on public.case_requests(legal_case_id);
create index if not exists case_requests_requested_by_idx on public.case_requests(requested_by_profile_id);
create index if not exists case_updates_author_profile_id_idx on public.case_updates(author_profile_id);
create index if not exists conversations_case_id_idx on public.conversations(case_id);
create index if not exists law_firm_invitation_attempts_firm_idx on public.law_firm_invitation_attempts(law_firm_id);
create index if not exists law_firm_members_lawyer_id_idx on public.law_firm_members(lawyer_id);
create index if not exists lfv_documents_owner_profile_id_idx on public.law_firm_verification_documents(owner_profile_id);
create index if not exists lfv_documents_verification_id_idx on public.law_firm_verification_documents(verification_id);
create index if not exists law_firm_verifications_firm_idx on public.law_firm_verifications(law_firm_id);
create index if not exists law_firm_verifications_reviewer_idx on public.law_firm_verifications(reviewer_id);
create index if not exists lawyer_verifications_reviewer_idx on public.lawyer_verifications(reviewer_id);
create index if not exists legal_cases_law_firm_id_idx on public.legal_cases(law_firm_id);
create index if not exists message_attachments_uploaded_by_idx on public.message_attachments(uploaded_by);
create index if not exists messages_sender_id_idx on public.messages(sender_id);
create index if not exists notifications_actor_profile_id_idx on public.notifications(actor_profile_id);
create index if not exists notifications_law_firm_id_idx on public.notifications(law_firm_id);
create index if not exists verification_documents_user_id_idx on public.verification_documents(user_id);

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Verificacao pos-push (SQL Editor):
--   select count(*) from pg_policies where schemaname='public'
--     and ((qual like '%auth.uid()%' and qual not like '%( SELECT auth.uid()%')
--       or (with_check like '%auth.uid()%'
--           and with_check not like '%( SELECT auth.uid()%'));   -- 0
--   -- e rodar `supabase db advisors --type performance`: so deve sobrar
--   -- o aviso de multiple_permissive_policies em profiles (ver docs).
-- ---------------------------------------------------------------------------
