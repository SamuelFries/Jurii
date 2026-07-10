-- Patch 045 — Corrige o upsert de profiles bloqueado pelo hardening do patch_041.
--
-- Rode depois do patch_044.
--
-- Problema (confirmado em runtime, 2026-07-06): o patch_041 revogou UPDATE amplo
-- em public.profiles e concedeu UPDATE apenas em
--   (full_name, email, initials, cpf, phone, avatar_url).
-- O app faz `.upsert()` em profiles (lib/repositories/profile_repository.dart)
-- enviando `id`. Um upsert do PostgREST vira
--   INSERT ... ON CONFLICT (id) DO UPDATE SET ... , id = EXCLUDED.id
-- e o ramo DO UPDATE toca a coluna `id`, que tem grant de INSERT mas NÃO de
-- UPDATE. Resultado reproduzido com usuário de teste autenticado:
--   POST /rest/v1/profiles (Prefer: resolution=merge-duplicates)
--   -> HTTP 403, 42501 "permission denied for table profiles".
--
-- Impacto real hoje é BAIXO (o cadastro grava full_name/email/initials/cpf pela
-- trigger handle_new_auth_user, SECURITY DEFINER, que não passa por grants), mas
-- o caminho de upsert do app fica morto: qualquer edição futura de perfil
-- (telefone, avatar, nome) via esse upsert falharia em silêncio (o app engole o
-- erro em try/catch). Este patch destrava esse caminho.
--
-- Segurança: a policy profiles_update_own já é
--   using (id = auth.uid()) with check (id = auth.uid())
-- (supabase/schema.sql), então conceder UPDATE em `id` NÃO permite repontar a
-- linha para outro usuário — o WITH CHECK exige que o id resultante continue
-- sendo o do próprio usuário. Na prática o SET id = EXCLUDED.id é um no-op.

grant update (id) on public.profiles to authenticated;

notify pgrst, 'reload schema';

-- Verificação pós-patch (como usuário de teste autenticado, via REST):
--   POST /rest/v1/profiles
--     apikey: <publishable>  Authorization: Bearer <jwt do usuário>
--     Prefer: resolution=merge-duplicates,return=representation
--     body: {"id":"<auth.uid()>","full_name":"X","email":"...","initials":"X",
--            "cpf":"52998224725","phone":"11999998888"}
--   -> deve retornar 200/201 e a linha com cpf/phone atualizados
--      (antes deste patch retornava 403 / 42501).
