# Segurança & LGPD — Estado atual e pendências

Última auditoria: julho/2026 (auditoria multi-agente + verificação manual).

## Corrigido pelo patch_041 (rodar no SQL Editor)

`supabase/patch_041_security_hardening.sql` fecha os furos encontrados:

1. **Auto-promoção a advogado (crítico)** — `grant update` amplo em `profiles`
   permitia `lawyer_status='approved'` pelo próprio usuário; agora privilégios
   por coluna bloqueiam `lawyer_status`/`member_since`, e `lawyer_profiles`
   perdeu o insert self-service.
2. **PII de advogados exposta (crítico/LGPD)** — a policy
   `profiles_select_approved_lawyers_public` entregava linha inteira (CPF,
   telefone, e-mail) de todo advogado aprovado a qualquer autenticado; removida
   (o app usa RPCs que retornam só campos públicos).
3. **Auto-aprovação de verificações** — `WITH CHECK` agora impede o autor de
   mudar o status para `approved` (advogado e escritório).
4. **Spoofing de `sender_type`** — cliente não consegue mais inserir mensagem
   como `system`/`lawyer` (engenharia social no chat).
5. **`verification_documents` de terceiros** — insert agora exige que a
   verificação pertença ao autor.
6. **Bucket `chat-attachments`** — limites de tamanho/MIME aplicados no
   Storage (upload direto contornava a validação do RPC).
7. Typo público "(delleted account)" → "(conta excluída)".

No app: CPF com dígitos verificadores e normalizado (11 dígitos), e-mail com
regex, senha mínima 8 unificada, mensagens de erro sem detalhes internos
(patches/RPC/schema cache viraram `debugPrint`), validação de magic bytes nos
anexos do chat.

## Corrigido pelo patch_043 (rodar no SQL Editor)

`supabase/patch_043_fix_firm_case_scope.sql` fecha a pendência crítica de
escopo de casos do escritório: `fetch_law_firm_cases` e
`assign_law_firm_case` agora tratam como caso do escritório apenas linhas em
`legal_cases` com `law_firm_id = law_firm_id_value`. Um advogado poder ser
membro de um escritório não basta mais para esse escritório enxergar ou
reatribuir casos pessoais do advogado, nem casos vinculados a outro escritório.

## Corrigido pelo patch_044 + Edge Function (rodar/deployar)

`supabase/patch_044_account_deletion_lgpd.sql` e a Edge Function
`supabase/functions/delete-account` fecham a exclusão de conta: a função roda
com `service_role`, apaga Storage sensível de verificação/avatar, chama o
soft-delete transacional existente, bane o usuário em `auth.users` e registra
auditoria em `account_deletion_audit`.

Anexos de chat e documentos de caso não são apagados nessa rotina porque podem
ser prova/evidência; eles continuam dependendo de uma política de retenção
própria.

## Pendências que dependem de decisão/infra (NÃO resolvidas)

| # | Risco | Detalhe | Proposta |
| --- | --- | --- | --- |
| 1 | **PII entre contrapartes** | `can_select_profile` dá a linha inteira de `profiles` (CPF, telefone) ao advogado do caso e vice-versa | Segregar CPF/telefone em tabela própria ou trocar por RPC de campos mínimos |
| 2 | **Roster de escritórios público** | Qualquer autenticado lê `law_firm_members` de qualquer escritório ativo | Restringir a membros; expor equipe pública via RPC com nome/área apenas |
| 3 | **Sem papel admin** | Aprovação de OAB/escritório é manual via SQL Editor com service_role; sem trilha de revisão | Painel admin + role de revisor + RPCs auditadas (`reviewer_id` real) |
| 4 | **Ex-dono retém poderes** | patch_031: quem consta como owner numa verificação aprovada segue gerente mesmo com membership desativado | Basear autoridade só em `law_firm_members` ativo |
| 5 | **Conversas/agendas arbitrárias** | Cliente pode criar conversa apontando lawyer/caso alheio (spam de inbox) | Exigir criação via RPCs `start_or_get_*` e validar coerência na policy |
| 6 | **Enumeração de OAB** | RPC de convite responde diferente p/ OAB existente e ainda promove `lawyer_status` no convite não aceito | Resposta genérica + mover upsert de `lawyer_profiles` para o aceite |
| 7 | **Delete de anexo entregue** | Uploader pode apagar objeto do Storage já vinculado a mensagem (anexo pode ser prova) | Restringir delete a objetos sem linha em `message_attachments` |
| 8 | **Verificação sem documentos** | Upload de documentos OAB/escritório é placebo (botão marca `uploaded=true`, nada sobe) | Implementar FilePicker + Storage + inserts; exigir docs na aprovação |

## LGPD — visão geral

- Dados sensíveis em jogo: relatos jurídicos, documentos de identidade/OAB,
  CPF, mensagens cliente‑advogado, fotos.
- Buckets privados com URL assinada (300s) para anexos ✅; avatares públicos
  (aceitável, mas informar na política de privacidade).
- **Faltam no produto**: Política de Privacidade e Termos acessíveis (itens do
  perfil hoje são links mortos — obrigatório antes das lojas), registro de
  consentimento, DPO/canal do titular, política de retenção documentada.
- IA de triagem: ver requisitos de consentimento em `docs/ai-intake.md`.

## Chaves

- App usa apenas `publishable key` (pública por design) — segurança depende de
  RLS. `service_role` nunca entra no repositório/app.
- URL + publishable key têm fallback hardcoded em `lib/services/supabase_config.dart`
  para DX; produção deve injetar via `--dart-define` (e o fallback faz todo
  build apontar para produção — decidir se um modo demo explícito
  `--dart-define=USE_MOCKS=true` substitui o comportamento atual).
