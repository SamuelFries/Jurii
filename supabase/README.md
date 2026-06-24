# Jurii Supabase Setup

## 1. Criar as tabelas

Abra o Supabase Dashboard, vá em **SQL Editor**, cole todo o conteúdo de
`supabase/schema.sql` e execute.

Esse script cria:

- enums
- tabelas
- índices
- triggers de `updated_at`
- buckets de Storage
- policies RLS
- seeds iniciais de categorias e escritórios

Para um ambiente novo do Jurii, execute também os patches em ordem crescente
depois do `schema.sql`. O app atual depende das funções e ajustes criados até
o patch 028.

## 2. Configurar o app Flutter

No Supabase Dashboard, copie:

- Project URL
- Publishable key

Rode o app com:

```bash
flutter run \
  --dart-define=SUPABASE_URL=SUA_PROJECT_URL \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=SUA_PUBLISHABLE_KEY
```

Esses valores também estão configurados como padrão em `SupabaseConfig`, então
os `dart-define` são opcionais neste projeto. Use `dart-define` se quiser
apontar para outro ambiente.

## 2.1. Patch para perfis automáticos

Se você já rodou o `schema.sql` antes da criação do arquivo
`patch_001_auth_profile_trigger.sql`, rode também esse patch no SQL Editor.
Ele cria automaticamente uma linha em `profiles` quando um usuário se cadastra
pelo Supabase Auth.

## 2.2. Patch para recursão de RLS

Se aparecer no terminal:

```text
infinite recursion detected in policy for relation "legal_cases"
```

rode também `patch_002_fix_rls_recursion.sql` no SQL Editor.
Ele substitui policies recursivas por funções `security definer`.

## 2.3. Patch para CPF no cadastro

Se você já rodou o `schema.sql` antes do cadastro enviar CPF nos metadados do
Auth, rode `patch_003_auth_profile_cpf.sql` no SQL Editor. Ele atualiza o
trigger de criação de perfil para salvar o CPF recebido durante o cadastro.

## 2.4. Patch para verificação de escritório

Rode `patch_004_law_firm_verification.sql` antes de integrar a área do
escritório. Esse patch cria as tabelas de verificação de escritório e ajusta
`law_firm_members` para aceitar donos, admins e secretárias sem exigir OAB.

## 2.5. Patch para permissões das roles do Supabase

Se o app mostrar erros como:

```text
permission denied for table profiles
Grant SELECT ON public.profiles TO authenticated
```

rode `patch_005_public_grants.sql` no SQL Editor. As policies RLS controlam as
linhas acessíveis, mas o Postgres também precisa de permissões de tabela para
as roles `anon` e `authenticated`.

## 2.6. Patch para aprovar escritório

Rode `patch_006_approve_law_firm_verification.sql` depois dos patches 004 e
005. Ele cria uma função administrativa para aprovar a verificação de
escritório do jeito que o app espera: preenchendo `law_firm_id`, criando ou
atualizando o registro em `law_firms` e vinculando o dono em
`law_firm_members`.

Depois de enviar uma solicitação pelo app, aprove pelo SQL Editor com:

```sql
select public.approve_law_firm_verification('ID_DA_VERIFICACAO');
```

Evite aprovar apenas mudando `status` manualmente para `approved`, porque o app
precisa do vínculo com o escritório para abrir a área administrativa com dados
reais.

## 2.7. Patch para convites e notificações

Rode `patch_007_team_invites_notifications.sql` depois do patch 006. Ele cria:

- tabela `notifications`
- função `invite_verified_lawyer_to_law_firm`
- função `respond_to_law_firm_invite`
- permissões para o sino de notificações
- validação para que apenas donos/admins ativos convidem advogados

Na área do escritório, o botão de convidar usa a OAB para localizar uma
verificação profissional aprovada. Se encontrar, o Supabase cria um membership
com status `invited` e uma notificação para o advogado.

Se você já rodou esse patch antes da versão com aceitar/recusar convite, rode
o patch 007 novamente. Ele é idempotente e atualiza as funções existentes.

## 2.8. Patch para mensagens e chat

Rode `patch_008_messaging_integration.sql` para liberar o chat real. Ele:

- permite que membros ativos do escritório acessem conversas do escritório
- mantém o acesso do cliente e do advogado responsável
- permite envio de mensagens por participantes autorizados
- atualiza `last_message` e `last_message_at` automaticamente quando uma
  mensagem é enviada

## 2.9. Patch para perfis e início de conversa

Rode `patch_009_profile_conversation_entrypoints.sql` depois do patch 008. Ele:

- permite exibir dados básicos de advogados aprovados nos cards públicos
- cria `approve_lawyer_verification`
- cria `start_or_get_law_firm_conversation`
- cria `start_or_get_lawyer_conversation`
- evita conversas duplicadas ao clicar novamente em enviar mensagem

Para aprovar um advogado criando o perfil profissional:

```sql
select public.approve_lawyer_verification('ID_DA_VERIFICACAO');
```

## 2.10. Patch para chat em tempo real

Rode `patch_010_realtime_messages_profiles.sql` depois do patch 009. Ele:

- adiciona `public.messages` à publication do Supabase Realtime
- permite que membros ativos do escritório leiam o nome do cliente em conversas
  do escritório
- mantém as mensagens chegando no app sem botão de atualizar

## 2.11. Patch para advogados recomendados

Rode `patch_011_recommended_lawyers_rpc.sql` depois do patch 010. Ele cria a
função `fetch_recommended_lawyers`, usada pela home do cliente para listar os
advogados reais cadastrados em `lawyer_profiles` sem cair em mocks por bloqueios
de RLS entre tabelas.

## 2.12. Patch para nomes corretos nas conversas

Rode `patch_012_conversation_display_names_rpc.sql` depois do patch 011. Ele
cria a função `fetch_conversations_for_current_user`, que devolve o nome certo
para cada inbox:

- cliente vê o advogado ou escritório
- advogado vê o cliente
- escritório vê o cliente

## 2.13. Patch para abrir perfis pelo chat

Rode `patch_013_chat_profile_entrypoints.sql` depois do patch 012. Ele cria:

- `fetch_chat_profile`, usado para abrir o perfil do cliente pelo chat
- `fetch_lawyer_public_profile`, usado para abrir o perfil do advogado pelo chat

## 2.14. Patch para Meus Casos

Rode `patch_014_cases_integration.sql` depois do patch 013. Ele cria:

- `fetch_client_cases`
- `fetch_lawyer_cases`
- `fetch_law_firm_cases`

Essas funções alimentam as abas de casos do cliente, advogado e escritório.

## 2.15. Patch para solicitações e atualizações de caso

Rode `patch_015_case_requests_updates.sql` depois do patch 014. Ele cria:

- `case_requests`
- `case_updates`
- `create_case_request`
- `respond_to_case_request`
- `fetch_case_requests_for_client`
- `fetch_case_updates`
- `add_case_update`

Esse patch habilita o fluxo em que advogado ou escritório envia uma solicitação
de caso, o cliente aceita ou recusa, e os profissionais registram atualizações.

## 2.16. Patch para aceite de caso no sino e no chat

Rode `patch_016_case_request_actions.sql` depois do patch 015. Ele:

- adiciona `metadata` nas mensagens
- vincula cada solicitação a uma mensagem do chat e uma notificação
- permite aceitar ou recusar pelo sino, chat ou Meus Casos
- sincroniza o status da solicitação em todos os pontos de entrada
- notifica advogado e escritório quando o cliente aceita ou recusa
- impede que casos do cliente apareçam indevidamente no fluxo profissional

## 2.17. Patch para envio de verificação profissional

Rode `patch_017_fix_profile_rls_lawyer_verification_submit.sql` depois do
patch 016 se o envio da verificação profissional falhar com:

`infinite recursion detected in policy for relation "profiles"`

Ele corrige a policy recursiva entre `profiles` e `lawyer_profiles` e cria a
RPC `submit_lawyer_verification`, usada pelo app para enviar a análise da OAB.

## 2.18. Patch para ambiguidade na RPC de verificação

Rode `patch_018_fix_lawyer_verification_rpc_ambiguity.sql` depois do patch 017
se o envio da verificação profissional falhar com:

`column reference "id" is ambiguous`

Ele recria a RPC `submit_lawyer_verification` sem referências ambíguas a `id`.

## 2.19. Patch para rascunhos de conversa

Rode `patch_019_hide_empty_conversation_drafts.sql` depois do patch 018. Ele
faz com que conversas abertas a partir do perfil de advogado ou escritório só
apareçam nas abas de mensagens depois que uma mensagem real for enviada.

Isso evita que o simples ato de tocar em **Enviar mensagem** crie uma conversa
persistente visível caso o usuário desista e volte sem escrever nada.

## 2.20. Patch de estabilidade do primeiro envio de mensagem

Rode `patch_020_restore_chat_draft_metadata.sql` depois do patch 019. Ele
mantém os rascunhos vazios escondidos pela listagem, mas restaura os metadados
do rascunho usados pelo fluxo de chat antes da primeira mensagem real.

## 2.21. Patch para coluna metadata em mensagens

Rode `patch_021_ensure_message_metadata.sql` depois do patch 020 se o envio de
mensagem falhar com:

`column messages.metadata does not exist`

Ele garante que `public.messages.metadata` exista, tenha default `{}` e esteja
pronta para mensagens comuns, cards de solicitação de caso e notificações. O
patch também solicita reload do schema da API do Supabase.

## 2.22. Patch para casos e métricas do escritório

Rode `patch_022_firm_case_operations.sql` depois do patch 021. Ele:

- garante `created_at` em `law_firm_members`, usado nos fluxos de caso
- faz a aba de casos do escritório incluir casos aceitos por advogados membros
- cria `fetch_law_firm_operation_metrics` para a home do escritório usar dados reais

## 2.23. Patch para realtime de notificações

Rode `patch_023_notifications_realtime.sql` depois do patch 022. Ele adiciona
`public.notifications` à publication `supabase_realtime`, permitindo que o sino
das homes atualize quando uma solicitação de caso, convite ou resposta chegar.

## 2.24. Patch para reparar superfícies de solicitação de caso

Rode `patch_024_case_request_surfaces_repair.sql` depois do patch 023 se uma
solicitação de caso for criada, mas o cliente não receber notificação nem card
acionável no chat. Ele cria/atualiza mensagem de sistema, notificação e faz
backfill das solicitações pendentes já existentes.

## 2.25. Patch para segmentar notificações por fluxo

Rode `patch_025_notification_scopes.sql` depois do patch 024. Ele adiciona o
escopo das notificações:

- `client`: aparece apenas no fluxo do cliente
- `lawyer`: aparece apenas no fluxo profissional
- `firm`: aparece apenas no fluxo do escritório

O patch também faz backfill das notificações antigas e instala um trigger para
classificar novas notificações automaticamente pelo tipo.

## 2.26. Patch para tags de áreas e busca

Rode `patch_026_practice_area_tags_search.sql` depois do patch 025. Ele:

- adiciona `practice_areas` em advogados, escritórios e verificações
- preserva `primary_area`, `practice_area` e `specialty` como área principal
- atualiza as funções de envio/aprovação para salvar múltiplas tags
- cria busca por área para a Home do cliente em advogados e escritórios
- solicita reload do schema da API do Supabase

## 2.27. Patch para escopo estrito dos casos do advogado

Rode `patch_027_strict_lawyer_case_scope.sql` depois do patch 026 se um usuário
que também é advogado enxergar, no fluxo profissional, casos onde ele está
apenas como cliente.

Esse patch recria `fetch_lawyer_cases()` para listar somente casos onde o
usuário atua profissionalmente, como `assigned_lawyer_id` ou participante com
role `lawyer`/`firm_member`. Casos onde o usuário é `client` continuam
aparecendo apenas no fluxo do cliente.

## 2.28. Patch para convite do próprio advogado

Rode `patch_028_self_lawyer_invite_requires_acceptance.sql` depois do patch
027 se o dono/admin do escritório convidar o próprio perfil de advogado e a
notificação ficar pendente sem conseguir aceitar ou recusar.

Esse patch separa o membership ativo de líder/admin do aceite como advogado do
escritório. O usuário mantém acesso ao escritório, mas o vínculo como advogado
fica pendente até ser aceito pelo sino de notificações.

## 2.29. Patch para busca por intenção jurídica

Rode `patch_029_legal_search_intents.sql` depois do patch 028. Ele adiciona
uma camada ampla de intenção de busca para a Home do cliente, permitindo que
termos formais e informais como `Maria da Penha`, `meu marido me bateu`,
`estupro`, `pai não pagou pensão`, `fui demitido sem receber`, `nome sujo`,
`minha compra não chegou`, `INSS`, `bateram no meu carro` ou `whatsapp clonado`
encontrem advogados e escritórios pelas áreas jurídicas corretas.

O patch cria a tabela `legal_search_intents`, instala a função
`infer_legal_search_areas` e recria as RPCs `fetch_recommended_lawyers` e
`fetch_recommended_law_firms` para considerar essas intenções no ranking. O
patch é idempotente e pode ser executado novamente para atualizar o dicionário
de termos.

## 2.30. Patch para cargos múltiplos no escritório

Rode `patch_030_firm_member_multi_roles.sql` depois do patch 029. Ele:

- adiciona `roles text[]` em `law_firm_members` e faz backfill dos cargos atuais
- mantém `role` e `member_role` sincronizados para compatibilidade
- adiciona o papel `intern`/estagiário
- cria permissões por conjunto de cargos para gerenciar equipe e atribuir casos
- cria `update_law_firm_member_roles` para a UI de cargos da equipe
- cria `assign_law_firm_case` para dono/admin/secretaria atribuir casos a advogados
- restringe atualizações de caso ao advogado responsável/participante advogado
- atualiza os fluxos de convite e solicitação de caso para usar `roles`

## 2.31. Patch para reparar dono do escritório

Rode `patch_031_repair_firm_owner_roles.sql` depois do patch 030 se o criador
do escritório não conseguir convidar ou gerenciar membros. Ele corrige
memberships de donos que ficaram com `roles = ['lawyer']`, cria o vínculo de
dono caso esteja faltando e endurece as funções de permissão para reconhecer o
criador aprovado do escritório como dono.

## 2.32. Patch para liberar RPC de convites

Rode `patch_032_firm_invite_rpc_grants.sql` depois do patch 031 se o convite
de advogado ainda falhar com erro de função, permissão ou schema cache. Ele
garante `execute` em `invite_verified_lawyer_to_law_firm` para usuários
autenticados e força reload do schema da API.

## 2.33. Patch para reparar normalizacao do convite

Rode `patch_033_repair_invite_practice_area_normalizer.sql` depois do patch 032
se o convite falhar com `function public.normalize_practice_areas(text[]) does
not exist`. Ele cria a funcao usada pela RPC de convite e garante a tabela
`notifications`, que tambem e usada por esse fluxo.

## 2.34. Patch para excluir notificações

Rode `patch_034_notification_dismissal.sql` depois do patch 033. Ele adiciona
uma policy de `delete` em `notifications` para que o destinatário consiga
excluir notificações pelo gesto de deslizar no app, sem permitir apagar
notificações de outros usuários.

## 2.35. Patch para exclusão de conta

Rode `patch_035_account_deletion.sql` depois do patch 034. Ele implementa a
exclusão segura da conta como soft delete:

- marca o perfil com `deleted_at`
- remove o perfil profissional de advogado e verificações privadas
- mantém conversas, casos, documentos compartilhados e escritórios ativos
- exibe o nome histórico como `nome (delleted account)` em chats e casos
- impede abertura de perfil de contas deletadas
- transfere o escritório criado pelo usuário deletado para o membro ativo de
  maior hierarquia, usando a ordem dono, admin, advogado, secretária e estagiário
- bloqueia o login da conta deletada no app

## 2.36. Patch para vincular conversas de advogado ao escritorio

Rode `patch_036_link_lawyer_conversations_to_firm.sql` depois do patch 035. Ele
faz com que conversas iniciadas pelo perfil de um advogado ativo do escritorio
tambem recebam `law_firm_id`, para aparecerem na caixa de mensagens e nas
metricas da home do escritorio. O patch tambem faz backfill seguro das conversas
criadas depois que o advogado entrou no escritorio.

## 2.37. Patch para remover quantidade de advogados do cadastro

Rode `patch_037_remove_law_firm_lawyers_count.sql` depois do patch 036. Ele
remove a coluna legada `lawyers_count` de `law_firm_verifications`, porque o app
nao pede mais esse numero no cadastro do escritorio. A equipe real deve ser
medida pelos membros ativos em `law_firm_members`.

## 2.38. Patch para chat do advogado apos atribuicao de caso

Rode `patch_038_case_assignment_conversation_access.sql` depois do patch 037.
Ele faz com que uma conversa de escritorio vinculada a um caso apareca tambem
no fluxo de mensagens do advogado atribuido, sem criar chat duplicado. Ao
atribuir ou reatribuir o caso, a conversa recebe uma mensagem de sistema como
`Caso atribuido a Nome do Advogado`.

## 2.39. Patch para anexos no chat

Rode `patch_039_chat_message_attachments.sql` depois do patch 038. Ele cria o
bucket privado `chat-attachments`, a tabela `message_attachments`, policies de
Storage/RLS e a RPC `send_chat_attachment`. O app usa esse fluxo para enviar
fotos, PDFs e documentos Word em conversas existentes, sem criar um chat
separado.

## 2.40. Hotfix para anexos no chat

Rode `patch_040_fix_chat_attachment_metadata_update.sql` depois do patch 039 se
o envio de anexos falhar com erro de `metadata` ambiguo. Ele recria a RPC
`send_chat_attachment` com a referencia correta e recarrega o schema cache.

## 2.41. Patch para titulo de conversa com advogado

Rode `patch_041_client_lawyer_conversation_titles.sql` depois do patch 040. Ele
faz o cliente ver o nome do advogado responsavel quando a conversa possui
`lawyer_id`, mesmo que o advogado tambem esteja vinculado a um escritorio.

## 2.42. Hotfix para fotos do iPhone no chat

Rode `patch_042_allow_iphone_photo_attachments.sql` depois do patch 041. Ele
recria a RPC `send_chat_attachment` aceitando imagens HEIC/HEIF, formatos comuns
de fotos no iPhone.

## 3. Status da integração

A camada inicial de repositories já existe em `lib/repositories/`.
As áreas já conectadas ao Supabase, com fallback local quando o ambiente não
está configurado, são:

1. Auth + Profile
2. Home cliente: categorias, escritórios e advogados recomendados
3. Verificação profissional
4. Verificação de escritório
5. Casos e solicitações de aceite
6. Mensagens e chat em tempo real
7. Agenda

Ainda usam dados mockados como superfície de produto:

- métricas da home profissional
- resumo de hoje da home profissional
- métricas e overview da home do escritório
