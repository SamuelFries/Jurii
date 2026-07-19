# Jurii Supabase

Este diretório agora usa o fluxo de migrations do Supabase CLI como fonte
principal para novos ambientes.

## Estrutura

- `migrations/20260711190000_squashed_legacy_baseline.sql`: baseline atual do
  banco, gerada a partir de `schema.sql` + patches 001 a 045.
- `migrations/20260712...` em diante: migrations incrementais de verificação,
  avaliações, recomendações/notificações e hardening de segurança.
- `tests/`: testes pgTAP de autorização e invariantes do banco.
- `legacy_patches/`: histórico dos patches antigos. Use para auditoria ou para
  entender a origem de uma regra, não como fluxo normal de setup.
- `functions/delete-account/`: Edge Function de exclusão LGPD.
- `proposals/`: propostas SQL ainda não aplicadas como migration oficial.

## Ambiente novo

Para um projeto Supabase vazio:

```bash
supabase link --project-ref SEU_PROJECT_REF
supabase migration list --linked
supabase db push
```

Isso aplica a baseline e todas as migrations incrementais de
`supabase/migrations/`. Depois configure o app com:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://SEU-PROJETO.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

Os `dart-define` são opcionais para o projeto padrão da Jurii, mas devem ser
usados quando você quiser apontar para outro ambiente.

## Ambiente local com Docker

O projeto tambem tem `supabase/config.toml` para rodar a stack local da CLI:

```bash
supabase start
supabase db reset
supabase status
```

O seed da CLI esta desativado porque a baseline ja inclui os dados/seeds
necessarios. Para detalhes, pre-requisitos e smoke tests SQL, veja
`docs/supabase-local.md`.

## Projeto remoto atual

O projeto remoto da Jurii recebeu manualmente o conteúdo que foi consolidado na
baseline. O reparo histórico abaixo já foi executado no projeto atual; ele só é
necessário ao recuperar outro ambiente legado que tenha o schema, mas não o
histórico da CLI.

Em 14/07/2026, `supabase db push --linked` aplicou a migration
`20260714220000_security_hardening_round2.sql` e, depois, a migration
`20260714230000_account_deletion_storage_paths_rpc.sql`. A segunda adiciona a
RPC administrativa mínima usada pela exclusão LGPD, sem liberar `SELECT`
direto para `service_role`. A Edge Function `delete-account` versão 2 também
foi publicada e validada com uma conta burner completa. O
`supabase migration list --linked` confirmou local e remoto sincronizados. A
migration de hardening revoga o contrato antigo de leitura direta de PII em
`profiles`; por isso apenas a versão do app que usa `fetch_current_profile()` e
`upsert_current_profile()` deve permanecer suportada. Builds antigos deixam de
carregar o perfil.

A migration `20260718160000_profile_customization.sql` foi adicionada ao
repositório para a edição do perfil pessoal e aplicada ao projeto remoto em
18/07/2026 com `supabase db push --linked`. A conferência posterior por
`supabase migration list --linked` confirmou local e remoto sincronizados. Ela
atualiza `upsert_current_profile()`
para validar/remover telefone e tornar CPF preenchido imutável; adiciona as RPCs
`update_current_profile_customization()` e `set_current_profile_avatar()`;
revoga `UPDATE` direto de `avatar_url`; restringe tamanho e MIME types do bucket
`profile-avatars`; e permite `DELETE` somente na pasta do próprio usuário. Como
o build anterior ainda usa `UPDATE` direto no fluxo de foto profissional, o app
compatível com as novas RPCs deve ser promovido após este push.

No app, o lápis do cabeçalho e `Dados Pessoais` levam à mesma tela. Nome,
telefone e avatar são editáveis; e-mail e CPF são somente leitura. A validação
local do avatar aceita JPG/JPEG, PNG e WEBP, confere magic bytes e limita a foto
a 5 MB, enquanto o bucket aplica limite de 10 MB como barreira de servidor. A
URL pública é derivada no banco de um objeto na pasta do próprio usuário. A
edição de bio, áreas e demais dados profissionais permanece fora desta migration
e deverá ter contrato próprio.

A migration `20260718180000_profile_avatar_surfaces.sql` leva o `avatar_url`
público aos contratos de recomendação, mini perfil e conversa sem ampliar o
acesso a PII. Ela recria `fetch_recommended_lawyers()`,
`fetch_lawyer_public_profile()`, `fetch_chat_profile()`,
`fetch_conversation_for_current_user()` e
`fetch_conversations_for_current_user()` porque a adição de uma coluna em
`RETURNS TABLE` exige `DROP FUNCTION` antes da nova assinatura de retorno. Os
grants são restaurados somente para `authenticated`; `anon` permanece sem
`EXECUTE`.

Na migration `20260718180000`, a URL devolvida pertencia apenas à contraparte
individual. Cliente com escritório e chat interno de equipe retornavam `NULL`,
porque `law_firms` ainda não possuía foto própria. O teste
`supabase/tests/profile_avatar_surfaces_test.sql` cobre grants e os dois lados
de uma conversa cliente-advogado com rollback; a migration corporativa descrita
abaixo passa a preencher apenas o ramo cliente-escritório.

A mesma migration neutraliza `avatar_url` legado: o helper interno
`safe_profile_avatar_url()` aceita somente caminho da pasta do titular com
objeto existente em `profile-avatars`, remove qualquer host armazenado e devolve
um caminho público relativo. `set_current_profile_avatar()` passa a persistir o
mesmo formato. O app monta a URL absoluta com o `SUPABASE_URL` configurado; uma
URL externa sem objeto local é descartada e usa o fallback de iniciais.

Em 18/07/2026, `supabase db push --linked` aplicou
`20260718180000_profile_avatar_surfaces.sql` no projeto remoto e
`supabase migration list --linked` confirmou o histórico sincronizado.

A migration seguinte,
`20260718200000_law_firm_profile_avatar.sql`, adiciona a foto publica e opcional
do escritorio. Ela cria o bucket dedicado `law-firm-avatars`, as colunas
nullable `law_firm_verifications.avatar_storage_path` e
`law_firms.avatar_url`, e a RPC autenticada
`set_current_law_firm_verification_avatar()`. O caminho precisa seguir
`{auth.uid()}/{verificationId}/{arquivo}`, apontar para um objeto real e
pertencer a uma verificacao rascunho/pendente do titular. A aprovacao
administrativa valida a referencia novamente antes de publicar a URL relativa
no escritorio; sem foto, o fluxo continua inalterado e a UI usa iniciais.

`fetch_recommended_law_firms()` e as RPCs de conversa passam a devolver esse
avatar quando o cliente esta vendo um escritorio. O bucket e separado de
`profile-avatars` para que a exclusao da conta do responsavel nao remova a marca
de uma organizacao ja aprovada. `get_account_deletion_storage_paths()` inclui
somente imagens de verificacoes ainda nao aprovadas, e a Edge Function nao faz
folder sweep em `law-firm-avatars`.

A mesma migration revoga `INSERT/UPDATE` amplo em
`law_firm_verifications`: `authenticated` so recebe as colunas do formulario;
vinculo com escritorio, caminho do avatar e campos de revisao ficam reservados
as RPCs apropriadas. A foto e publica por natureza e, no app, o usuario e
informado disso antes de escolher o arquivo.

Em 18/07/2026, `supabase db push --linked` aplicou `20260718200000` no projeto
remoto e `supabase migration list --linked` confirmou o historico sincronizado.
A Edge Function `delete-account` foi publicada em seguida na versao 4 e ficou
`ACTIVE`, evitando incompatibilidade entre a nova resposta da RPC de limpeza e
o conjunto de buckets reconhecido pela Function. Localmente, o pgTAP focado
passou com 39/39 assercoes, a suite completa com 156/156 e o lint do schema
publico nao encontrou erros.

Para registrar apenas o histórico da migration no remoto atual:

```bash
supabase migration repair --linked --status applied 20260711190000
```

Depois disso, `supabase migration list --linked` deve mostrar a baseline como
aplicada local e remotamente.

## Mudanças futuras

Não crie mais `patch_046...` na raiz do diretório. Para qualquer alteração nova:

```bash
supabase migration new nome_curto_da_mudanca
```

Edite o arquivo criado em `supabase/migrations/` e aplique com:

```bash
supabase db reset
supabase test db supabase/tests --local
supabase migration list --linked
supabase db push
```

Regras práticas:

- migrations são **forward-only**;
- evite editar migration já aplicada em remoto;
- coordene app e banco quando a migration mudar ou revogar um contrato usado
  por clientes já publicados;
- prefira funções/RPCs idempotentes (`create or replace function`) quando fizer
  sentido;
- documente no topo da migration o problema, a decisão e a verificação;
- rode testes de RLS/RPC quando a mudança tocar permissões, Storage,
  conversas, casos ou LGPD.

## Edge Function LGPD

Depois de aplicar a baseline e as migrations incrementais em um ambiente novo,
publique a Function:

```bash
supabase functions deploy delete-account
```

Confirme que o ambiente da Function tem acesso a `SUPABASE_URL`,
`SUPABASE_ANON_KEY` e `SUPABASE_SERVICE_ROLE_KEY`. O app chama a Function
`delete-account`; a chave `service_role` nunca entra no app nem no repositório.
A Function acessa os caminhos sensíveis somente por
`get_account_deletion_storage_paths(uuid)`, executável exclusivamente por
`service_role`.

## Operações administrativas úteis

Aprovar advogado criando o perfil profissional:

```sql
select public.approve_lawyer_verification('ID_DA_VERIFICACAO');
```

Aprovar escritório criando/vinculando `law_firms` e dono:

```sql
select public.approve_law_firm_verification('ID_DA_VERIFICACAO');
```

Recusar com motivo:

```sql
select public.reject_lawyer_verification(
  'ID_DA_VERIFICACAO',
  'MOTIVO',
  null
);

select public.reject_law_firm_verification(
  'ID_DA_VERIFICACAO',
  'MOTIVO',
  null
);
```

Enquanto o Jurii for apenas app, essa revisão é manual por um operador
privilegiado no SQL Editor do Dashboard do Supabase. As funções não são
executáveis por `anon` ou `authenticated`; o grant de backend confiável é da
`service_role`. A página revisora, os papéis de funcionário e a auditoria
nominal entram junto com o futuro webapp; `service_role` nunca deve ir para o
navegador.

Evite aprovar verificações apenas mudando `status` manualmente: o app depende
dos vínculos criados por essas funções.

## Histórico legado

Os arquivos em `legacy_patches/` foram mantidos de propósito. Eles explicam a
história do banco até julho/2026, incluindo hardening de segurança, busca
jurídica, escopo de casos, anexos e LGPD. Em setup novo, use a baseline em
`migrations/`; consulte os patches somente para investigação.
