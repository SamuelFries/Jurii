-- Endurecimento: três buracos medidos, não suspeitados.
--
-- Cada um foi PROVADO com a role real (`set local role authenticated` e o
-- sub de uma conta comum) antes de virar correção, e cada correção tem o
-- mesmo ataque refeito no pgTAP, agora tendo que falhar.

-- ---------------------------------------------------------------------------
-- 1. O token do calendário era legível por qualquer pessoa logada
-- ---------------------------------------------------------------------------
--
-- `calendar_feed_token` é uma CAPABILITY: a URL do feed é
-- `functions/v1/calendar-feed?token=...` e quem tem o token lê a agenda
-- inteira do advogado, com nome de cliente, horário e local de audiência.
-- Não há segunda porta.
--
-- A policy de leitura de lawyer_profiles é
-- `(id = auth.uid()) or (approved_at is not null)`: existe para o perfil
-- público funcionar, e junto com ela ia o token. Medido: uma conta comum,
-- recém-criada, lia o token de qualquer advogado aprovado da plataforma.
--
-- A correção é de COLUNA, não de policy: a policy precisa continuar
-- deixando ler o perfil. Ninguém perde nada, porque o dono nunca leu o
-- token por select: ele vem de get_calendar_feed_token(), que é SECURITY
-- DEFINER e roda como postgres (o app faz assim desde sempre, em
-- calendar_feed_repository.dart, e o webapp também).
--
-- `authenticated` e `anon` só tinham SELECT nessa coluna; sem UPDATE nem
-- INSERT.
--
-- REVOGAR SÓ A COLUNA NÃO FUNCIONA, e isso foi medido: com um grant de
-- SELECT na tabela inteira por cima, o revoke de coluna não tira nada. É
-- preciso derrubar o grant de tabela e devolver coluna a coluna.
--
-- Isso deixa uma armadilha: coluna nova nasce SEM grant, invisível para o
-- app. A armadilha é a direção certa (o padrão vira fechado), mas
-- silenciosa, então o pgTAP cobra a lista completa: quem adicionar coluna
-- vê o teste cair e decide, em vez de descobrir pela tela vazia.
--
-- A função de borda calendar-feed não é afetada: ela lê por service_role.
revoke select on public.lawyer_profiles from anon;
revoke select on public.lawyer_profiles from authenticated;

grant select (
  id, oab_number, oab_state, primary_area, practice_areas, bio,
  professional_photo_url, is_available, approved_at, created_at, updated_at,
  rating, reviews_count
) on public.lawyer_profiles to anon;

grant select (
  id, oab_number, oab_state, primary_area, practice_areas, bio,
  professional_photo_url, is_available, approved_at, created_at, updated_at,
  rating, reviews_count
) on public.lawyer_profiles to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Dava para INSERIR uma verificação já "aprovada"
-- ---------------------------------------------------------------------------
--
-- A policy de UPDATE de lawyer_verifications sempre exigiu
-- `status in ('draft','pending')` com revisor e data nulos. A de INSERT
-- pedia só `user_id = auth.uid()`.
--
-- Medido: uma conta comum inseriu uma linha com `status = 'approved'` e
-- `reviewed_at = now()`. Isso não vira advogado aprovado (quem escreve
-- lawyer_profiles e profiles.lawyer_status é approve_lawyer_verification,
-- que é service_role), mas FORJA A TRILHA: a linha aparece no histórico da
-- equipe como decisão aprovada, e sem reviewer_id o painel a rotula como
-- "antes do painel existir". Num sistema cuja razão de ser é dizer quem
-- verificou carteira profissional, trilha forjável é o defeito.
--
-- E, no caminho fácil, insere-se qualquer quantidade de 'pending' para
-- afogar a fila de revisão.
--
-- A regra passa a ser a mesma dos dois lados. `submit_lawyer_verification`
-- continua funcionando: ela é SECURITY DEFINER e sempre gravou 'pending'.
drop policy if exists lawyer_verifications_insert_own on public.lawyer_verifications;
create policy lawyer_verifications_insert_own
on public.lawyer_verifications
for insert
to authenticated
with check (
  user_id = (select auth.uid())
  and status = any (array['draft', 'pending']::verification_status[])
  and reviewer_id is null
  and reviewed_at is null
  and rejection_reason is null
);

-- ---------------------------------------------------------------------------
-- 3. has_law_firm_license respondia sobre qualquer pessoa
-- ---------------------------------------------------------------------------
--
-- A função recebe um profile_id e devolve se aquela pessoa tem licença
-- ativa. É SECURITY DEFINER com execute para `authenticated`, então virava
-- um oráculo: dado um uuid, qualquer pessoa logada descobria se aquele
-- perfil paga a Jurii.
--
-- Revogar o execute NÃO serve, e isso foi medido: a policy de INSERT de
-- law_firm_verifications chama a função, e a chamada acontece com os
-- privilégios de quem consulta. Sem o grant, abrir escritório para de
-- funcionar com `permission denied for function has_law_firm_license`.
--
-- Então a correção é dentro: a função passa a responder SÓ sobre quem
-- pergunta. O único chamador que existe já passa auth.uid() (a policy
-- acima), então nada legítimo muda. Chamada sem sessão (service_role,
-- dashboard) devolve false de propósito: quem administra tem a tabela.
create or replace function public.has_law_firm_license(profile_id_value uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.law_firm_license_subscriptions sub
    where sub.owner_profile_id = profile_id_value
      and profile_id_value = (select auth.uid())
      and sub.status in ('trialing', 'active')
  );
$$;

-- ---------------------------------------------------------------------------
-- 4. O balde case-documents aceitava qualquer coisa, de qualquer tamanho
-- ---------------------------------------------------------------------------
--
-- Ele ainda não é usado por nenhum dos dois aplicativos, mas a policy de
-- escrita já existe e deixa QUALQUER pessoa autenticada gravar na pasta
-- dela. Sem `file_size_limit` e sem `allowed_mime_types`, isso é conta de
-- armazenamento aberta: uma conta criada de graça enche o balde.
--
-- Os outros quatro baldes já travam os dois no servidor, e é por isso que
-- o mime forjado pelo navegador não vira nada: o storage recusa antes.
-- Este era o único fora do padrão.
--
-- Os limites espelham chat-attachments, que é o parente mais próximo
-- (documento que uma pessoa manda para outra ler). Quando a funcionalidade
-- de documentos do caso existir, é aqui que a lista se amplia, de propósito
-- e não por esquecimento.
update storage.buckets
set
  file_size_limit = 26214400,
  allowed_mime_types = array[
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/webp',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
  ]
where id = 'case-documents';
