# Segurança & LGPD — Estado atual e pendências

Última auditoria: julho/2026 (auditoria multi-agente + verificação manual).

## Corrigido pelo patch_041 (consolidado na baseline)

`supabase/legacy_patches/patch_041_security_hardening.sql` fecha os furos
encontrados e agora está consolidado na baseline de migrations:

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

## Corrigido pelo patch_043 (consolidado na baseline)

`supabase/legacy_patches/patch_043_fix_firm_case_scope.sql` fecha a pendência
crítica de escopo de casos do escritório e agora está consolidado na baseline:
`fetch_law_firm_cases` e
`assign_law_firm_case` agora tratam como caso do escritório apenas linhas em
`legal_cases` com `law_firm_id = law_firm_id_value`. Um advogado poder ser
membro de um escritório não basta mais para esse escritório enxergar ou
reatribuir casos pessoais do advogado, nem casos vinculados a outro escritório.

## Corrigido pelo patch_044 + Edge Function (consolidado na baseline)

`supabase/legacy_patches/patch_044_account_deletion_lgpd.sql` e a Edge
Function `supabase/functions/delete-account` fecham a exclusão de conta. O SQL
está consolidado na baseline; a Function está ativa no projeto atual e ainda
precisa ser publicada separadamente nos demais ambientes. A função roda com
`service_role`, apaga Storage sensível de verificação/avatar, chama o
soft-delete transacional existente, bane o usuário em `auth.users` e registra
auditoria em `account_deletion_audit`.

Anexos de chat e documentos de caso não são apagados nessa rotina porque podem
ser prova/evidência; eles continuam dependendo de uma política de retenção
própria.

### Teste remoto com conta burner — bloqueio corrigido em 14/07/2026

O fluxo destrutivo foi finalmente exercitado com uma conta confirmada e
descartável. Antes do POST foram persistidos CPF, telefone, uma verificação
pendente, um documento no bucket privado e um avatar público.

O `POST /functions/v1/delete-account` retornou `500` e criou corretamente uma
auditoria `failed`. A falha acontece antes do soft-delete: a Function consulta
os caminhos pelo REST usando `service_role`, mas esse papel recebe
`permission denied` ao selecionar:

- `verification_documents`;
- `law_firm_verification_documents`;
- `profiles`.

O comportamento de falha foi seguro: perfil, arquivos e login permaneceram
intactos, evitando uma exclusão parcial silenciosa. Para não deixar a conta de
teste ativa, o cleanup foi concluído manualmente pelos mesmos componentes:
Storage zerado, RPC de soft-delete executada, usuário banido, relogin com HTTP
`400` e token antigo com HTTP `403`.

A correção foi implementada pela migration
`20260714230000_account_deletion_storage_paths_rpc.sql`. A RPC administrativa
`get_account_deletion_storage_paths(uuid)` usa `SECURITY DEFINER`, não devolve
PII e expõe somente `bucket_id` e `storage_path`. `PUBLIC`, `anon` e
`authenticated` não podem executá-la; apenas `service_role` recebeu `EXECUTE`,
sem ganhar `SELECT` direto nas tabelas. SQL e Edge Function também descartam
caminhos que não começam pela pasta exata do titular.

A Function versão 2 foi publicada e um novo teste destrutivo foi executado com
o perfil descartável `78fad775-0155-477d-9146-c68847ef6d1d`. O resultado foi:

- `POST /functions/v1/delete-account` com HTTP `200` e `ok=true`;
- auditoria final `completed`, sem warning, com os timestamps de conclusão e
  banimento preenchidos;
- documento privado e avatar removidos, ambos com contagem final zero;
- `deleted_at` preenchido e CPF, telefone e avatar anulados;
- verificação e metadados do documento removidos;
- usuário marcado como excluído e banido;
- novo login com HTTP `400` e token antigo com HTTP `403`.

O contrato da RPC tem oito asserções pgTAP próprias. Junto das 61 asserções da
rodada anterior, a suíte local passou com 69/69 testes.

## Corrigido no app — Política e Termos acessíveis

O app agora tem telas internas para `Política de Privacidade` e `Termos de Uso`,
acessíveis pelo perfil e pelos textos de concordância em login/cadastro. O
conteúdo é uma versão inicial de transparência e ainda deve passar por revisão
jurídica antes da publicação nas lojas.

## Implementado no diff — customização segura do perfil pessoal

O lápis do cabeçalho e o item `Dados Pessoais` abrem a mesma tela de edição.
Somente nome, telefone e avatar são mutáveis nesse fluxo; e-mail e CPF ficam
visíveis apenas para conferência e em modo somente leitura. Alterar e-mail
exigiria o fluxo próprio do provedor de autenticação, e o CPF permanece fora da
edição comum por ser identificador protegido.

O avatar continua no bucket público `profile-avatars`, portanto sua exposição
deve permanecer informada na Política de Privacidade. Antes do upload, o app:

- aceita apenas JPG/JPEG, PNG ou WEBP;
- compara extensão/MIME com a assinatura real do arquivo (magic bytes);
- limita a seleção a 5 MB;
- grava o objeto em `{auth.uid()}/` com nome único.

A troca envia o objeto primeiro e confirma nome, telefone e avatar na RPC
transacional `update_current_profile_customization()`. `avatar_url` não possui
mais `UPDATE` direto: `set_current_profile_avatar()` verifica a existência do
objeto em `profile-avatars/{auth.uid()}/` e deriva a origem do issuer assinado do
JWT, impedindo URL externa escolhida por cliente adulterado. Só depois o app
tenta limpar a URL anterior quando ela resolve para a própria pasta. A migration
`20260718160000_profile_customization.sql` adiciona a policy de `DELETE` limitada
a essa pasta e restringe o bucket aos MIME types permitidos, com limite de 10 MB
como defesa adicional do servidor. O app remove o objeto recém-enviado se a
persistência da URL falhar, evitando órfão nesse caminho de erro.

A mesma migration endurece `upsert_current_profile()`: o telefone é normalizado
para 10 ou 11 dígitos nacionais, aceita `+55`, rejeita letras, usa `NULL` para
preservar o valor existente e string vazia para removê-lo. CPF válido pode ser
definido em perfil incompleto, mas torna-se imutável depois do primeiro
preenchimento. Em 18/07/2026, `supabase db push --linked` aplicou a migration no
remoto e `supabase migration list --linked` confirmou o histórico sincronizado.
Como o `UPDATE (avatar_url)` direto foi revogado, o app compatível com
`set_current_profile_avatar()` deve ser promovido para manter o fluxo de foto
profissional funcional.

O escopo atual é exclusivamente o perfil pessoal. Bio, áreas de atuação e
outros dados do perfil profissional ficam para uma etapa futura, com RPCs,
validação e autorização específicas.

## Avatar público nas superfícies de usuário

A migration `20260718180000_profile_avatar_surfaces.sql` propaga
`profiles.avatar_url` apenas por RPCs que já validavam a relação ou a
visibilidade do perfil: recomendação de advogado, mini perfil autorizado e
conversas do usuário atual. Os contratos continuam sem expor CPF e telefone; a
RPC do mini perfil mantém o e-mail vazio. `anon` continua sem `EXECUTE` nessas
funções.

Na migration `20260718180000`, o avatar de uma conversa era apenas o da
contraparte individual: advogado para o cliente e cliente para
advogado/escritório. A resposta ainda era nula em conversa com escritório e no
canal interno da equipe, evitando atribuir a foto de um funcionário à
organização. A migration corporativa descrita abaixo passa a preencher somente
o ramo cliente-escritório com a foto própria da organização. As bolhas de
mensagem continuam sem foto até existir resolução segura por `sender_id`, e o
app mantém iniciais como fallback para URL ausente, carregando ou inválida.

Como existia escrita direta antes da migration de customização, URLs legadas
podiam apontar para hosts externos. A migration de superfícies normaliza todas
as linhas existentes: só preserva o caminho quando ele pertence ao perfil e há
um objeto correspondente em `storage.objects`; o host é removido. A RPC de
gravação também passa a persistir apenas o caminho público relativo. O
`ProfileAvatar` reconstrói a URL usando exclusivamente o `SUPABASE_URL`
configurado e rejeita qualquer valor sem um caminho válido do bucket, impedindo
requisição de rastreamento para host arbitrário mesmo em metadado legado.

Em 18/07/2026, a migration foi aplicada ao projeto remoto e a conferência por
`supabase migration list --linked` mostrou `20260718180000` presente tanto no
histórico local quanto no remoto.

## Avatar publico e opcional do escritorio

A foto pedida na verificacao do escritorio nao e comprovante e nao e
obrigatoria. Ela nao entra no bucket privado `verification-documents` nem no
bucket pessoal `profile-avatars`: a migration
`20260718200000_law_firm_profile_avatar.sql` usa o bucket publico dedicado
`law-firm-avatars`, com MIME restrito a JPEG/PNG/WEBP e limite de 10 MB. O app
aplica um limite menor de 5 MB e valida os magic bytes antes do upload.

O namespace obrigatorio e
`{auth.uid()}/{verificationId}/{arquivo}`. A policy de `INSERT` exige que o
segundo segmento identifique uma verificacao rascunho/pendente do proprio
usuario. Nao existe `UPDATE` de objeto. O `DELETE` autenticado fica limitado a
verificacoes ainda nao aprovadas, evitando que o antigo responsavel apague o
avatar de uma organizacao ja validada.

O caminho tambem nao possui escrita direta na tabela. A RPC
`set_current_law_firm_verification_avatar()` trava a verificacao, confirma
titularidade/status, valida formato e existencia do objeto e so entao preenche
`avatar_storage_path`. Na aprovacao, a referencia e validada outra vez e a URL
relativa e copiada para `law_firms.avatar_url`; URL externa escolhida pelo
cliente nao e aceita. Ausencia da foto deixa ambas as colunas nulas e preserva o
fallback por iniciais.

As RPCs de recomendacao e conversa expõem somente esse avatar corporativo
validado. A conversa cliente-escritorio recebe a foto da organizacao; o lado do
escritorio continua recebendo o avatar do cliente e o canal interno da equipe
continua sem um avatar geral incorreto.

A migration tambem fecha um privilegio anterior em
`law_firm_verifications`: `authenticated` perde `INSERT/UPDATE` amplo e recebe
somente as colunas do formulario. `law_firm_id`, `avatar_storage_path`, revisor,
datas e motivo de recusa nao podem ser forjados pelo app. A rotina LGPD passa a
devolver fotos corporativas somente para verificacoes nao aprovadas. A Edge
Function apaga exatamente esses caminhos e nao varre a pasta corporativa, de
modo que o avatar de um escritorio aprovado sobrevive a transferencia do dono.

Em 18/07/2026, a migration foi aplicada no projeto remoto e o historico
local/remoto confirmou `20260718200000`. A Edge Function `delete-account` foi
publicada na versao 4 e ficou `ACTIVE`. A validacao local passou com 39/39
assercoes pgTAP focadas, 156/156 na suite completa e lint do schema publico sem
erros.

## Implementado e aplicado na migration de hardening 2 (14/07/2026)

`20260714220000_security_hardening_round2.sql` implementa correções para seis
achados da auditoria e foi aplicada ao projeto remoto em 14/07/2026:

1. **PII entre contrapartes** — `authenticated` perdeu `SELECT` direto em
   e-mail, CPF e telefone. Campos públicos continuam disponíveis por coluna;
   o titular usa `fetch_current_profile()` para carregar a própria linha e
   `upsert_current_profile()` para gravar somente o próprio perfil. A RPC de
   perfil do chat não devolve mais e-mail: o contato permanece na Jurii.
2. **Roster de escritórios** — `law_firm_members` só é visível para o próprio
   usuário/convite ou para membros ativos daquele escritório. Helpers de cargo
   não aceitam consultar UUID de terceiro e não são executáveis por `anon`.
3. **Ex-dono e membership inativo** — autoridade vem exclusivamente de
   `law_firm_members.status='active'`; uma verificação histórica aprovada não
   concede mais poderes. O app também deixou de fabricar workspace a partir da
   verificação quando não existe vínculo ativo.
4. **Conversas e agenda arbitrárias** — `INSERT/UPDATE` direto foi revogado.
   Conversas continuam nascendo pelas RPCs `start_or_get_*`; a agenda permanece
   somente leitura até existir uma RPC que valide conversa/caso.
5. **Anexo entregue** — o uploader só apaga o blob enquanto ele ainda não tem
   linha em `message_attachments`. A verificação é `SECURITY DEFINER`, portanto
   continua bloqueando mesmo se o autor perder acesso posterior à conversa.
6. **Convite por OAB** — para chamada autorizada e entrada bem-formada, cada
   retorno é um UUID opaco novo; os efeitos de uma repetição são idempotentes.
   Erros de autorização, formato e rate limit continuam explícitos. Há limite
   de 20 tentativas por hora, e a busca parte do perfil profissional aprovado e
   valida a decisão mais recente do titular. Convite/aceite não promovem status.
   Uma recusa posterior invalida convites e suspende o papel profissional,
   mantendo papéis administrativos independentes.

Isso remove o oráculo direto da resposta da RPC e reduz enumeração em massa,
mas não torna a existência da OAB matematicamente indistinguível: um gerente
que fez um convite válido ainda pode observar a nova linha no roster do próprio
escritório. Por isso a medida é registrada como mitigação, combinada com rate
limit, e não como eliminação absoluta de todo canal lateral.

Validação versionada em
`supabase/tests/security_hardening_round2_test.sql`: 61 asserções de grants,
RLS, PII, autoridade, helper de proteção do Storage, convite, rate limit e ciclo
de recusa, sempre em transação com rollback. O smoke pela Storage API continua
registrado abaixo como pendência separada.

A migration passou integralmente no Supabase local e foi aplicada ao projeto
remoto. `supabase migration list --linked` confirmou local e remoto em
`20260714220000`. Como ela revoga leituras diretas de PII em `profiles`, apenas
a versão compatível do app, que usa as novas RPCs de leitura e escrita, deve
permanecer suportada; builds antigos deixam de carregar o perfil.

## Grants por coluna em legal_cases (29/07/2026, migration 20260729150000)

`legal_cases` era a última tabela de escrita do app com grant de tabela
inteira para `authenticated` (INSERT e UPDATE desde a baseline; o hardening 2
não a alcançou). Com a chegada do `cnj_number` (andamento processual via
DataJud), o grant foi convertido para **colunas explícitas**: escrita direta
não alcança `cnj_number` (só a RPC `set_case_cnj_number`, que valida papel e
dígito verificador) nem as colunas de posse (`client_id`/`law_firm_id`/
`assigned_lawyer_id`) no UPDATE. As RPCs SECURITY DEFINER existentes não
dependem desses grants; o app nunca usou escrita direta. Tabelas novas
`case_movements` (leitura por `can_access_case`, escrita só pelo job via RPC
service_role) e `case_movement_sync_state` (sem grants — interna do job).
Cobertura de testes: `supabase/tests/case_process_timeline_test.sql` (28
asserções, incluindo os grants por coluna). Detalhes da feature em
`docs/andamento-processual.md`.

## Decisão operacional — revisão manual por enquanto

No estágio atual, OAB e escritórios são aprovados/recusados manualmente por um
operador privilegiado no SQL Editor do Dashboard do Supabase, usando as funções
`approve_*` e `reject_*`. Elas não são executáveis por `anon` ou
`authenticated`; o grant para automação de backend confiável é da
`service_role`. Não será criado painel administrativo dentro do app.

Quando o Jurii também for webapp, o site ganhará uma página revisora para os
funcionários responsáveis. Nessa etapa serão criados papel global de revisor,
fila, URLs assinadas de curta duração e auditoria por funcionário. Isso é uma
decisão de roadmap, não um bloqueio técnico do app atual.

## Pendências reais antes de produção ampla

- Endurecer também a gravação de `storage_path` para exigir a pasta do titular
  na origem, paginar pastas com mais de 1.000 objetos e avaliar uma segunda
  varredura depois do banimento para fechar upload concorrente.
- Revisão jurídica final da Política de Privacidade e dos Termos de Uso.
- Definir canal oficial do titular/DPO, registro de consentimento e política de
  retenção para mensagens, anexos e documentos de caso.
- Criar a futura RPC de agendamento antes de permitir escrita na agenda.
- Fazer smoke do bloqueio de delete também pela Storage API, além do teste SQL.

## LGPD — visão geral

- Dados sensíveis em jogo: relatos jurídicos, documentos de identidade/OAB,
  CPF, mensagens cliente‑advogado, fotos.
- Buckets privados com URL assinada (300s) para anexos ✅; avatares públicos
  (aceitável, mas informar na política de privacidade).
- **Faltam no produto**: revisão jurídica final dos textos legais, registro de
  consentimento, DPO/canal oficial do titular e política de retenção
  documentada.
- IA de triagem: ver requisitos de consentimento em `docs/ai-intake.md`.

## Chaves

- App usa apenas `publishable key` (pública por design) — segurança depende de
  RLS. `service_role` nunca entra no repositório/app.
- URL + publishable key têm fallback hardcoded em `lib/services/supabase_config.dart`
  para DX; produção deve injetar via `--dart-define` (e o fallback faz todo
  build apontar para produção — decidir se um modo demo explícito
  `--dart-define=USE_MOCKS=true` substitui o comportamento atual).
