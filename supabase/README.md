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
o patch 024.

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
