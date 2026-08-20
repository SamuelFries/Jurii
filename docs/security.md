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

## Moderação de conteúdo — denúncia e bloqueio (migration 20260801120000)

Chat entre desconhecidos é conteúdo gerado por usuário; a diretriz 1.2 da
App Store exige mecanismo de denúncia e de bloqueio. Implementado assim:

- **Bloqueio é por conversa e congela os dois lados**: todo contato entre um
  par acontece numa única conversa (`start_or_get_*` devolve sempre a mesma),
  então congelar a conversa bloqueia o par — inclusive no balcão do
  escritório, em que não existe "a" contraparte. Só quem bloqueou destrava.
- A trava é um **trigger de INSERT em `messages`** (`messages_block_guard`),
  não policy: cobre também anexo via RPC e sugestão de advogado, sem tocar na
  policy endurecida do patch_041. O erro é o marcador constante
  `conversation_blocked` (sem eco de entrada), traduzido pelo app.
- **Denúncias** ficam em `user_reports` (razão whitelistada, texto livre
  sanitizado com o mesmo regex do hardening de log injection, teto de 1000
  caracteres e 10 denúncias/dia por usuário). Leitura só pelo back-office,
  como as verificações: RLS sem policy + revoke de tabela; escrita apenas
  pela RPC `report_conversation`, que exige participação na conversa.
- `fetch_conversation_block_state` não revela nada a quem não participa.
- Tratamento das denúncias hoje: painel do Supabase
  (`select * from user_reports where status = 'open'`). A Apple espera ação
  em até 24h — processo operacional, não técnico.

Endurecimentos da revisão adversarial: o guard cobre também
`message_attachments` (anexar arquivo novo a mensagem antiga era canal
furando o bloqueio); o canal interno de equipe (`firm_internal`) fica fora
da moderação (não há "contraparte" e um membro poderia congelar o
escritório); dono/admin destravam bloqueios deixados por operadores do
próprio escritório (nunca o do cliente); o antiflood é serializado por
`pg_advisory_xact_lock` (count-then-insert era contornável por
concorrência). Decisão aceita: bloqueio de conta excluída permanece — a
conversa com uma conta excluída está morta de qualquer forma, e congelada é
o estado correto.

Testes: `supabase/tests/report_block_test.sql` (23 asserções).

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

## Postura contra SQL injection (auditoria de 30/07/2026)

Auditoria dedicada, com verificação direta em produção e não só leitura de
código. **Nenhuma vulnerabilidade de SQL injection foi encontrada**, e o
motivo é estrutural: nenhuma função do app monta comando SQL dinamicamente.

### O que foi verificado no banco de produção

| Invariante | Resultado |
|---|---|
| Funções `SECURITY DEFINER` sem `search_path` fixo | **0** de 88 |
| Funções do app com SQL dinâmico (`execute`/`format`/`quote_*`) | **0** |
| `authenticated`/`anon` com `CREATE` em `public` | **não** (PG17 já não concede) |
| Funções definer referenciando tabela sem `public.` | **0** |
| Tabelas de `public` sem RLS | **0** |

O único `execute` do banco está em `rls_auto_enable`, event trigger da
plataforma Supabase que liga RLS em tabela nova. Ele interpola
`object_identity` vindo do catálogo do próprio Postgres, já com aspas: não é
entrada de usuário.

### A peça que sustenta a busca

O texto que o usuário digita na busca chega ao **lado do padrão** de três
`LIKE` (`fetch_recommended_lawyers`, `fetch_recommended_law_firms` e
`legal_search_term_matches`). O que impede injeção de curinga é um único passo
de `normalize_practice_area_search`:

```sql
regexp_replace(..., '[^a-z0-9]+', ' ', 'g')
```

É uma **allowlist**: `%` e `_` viram espaço e nunca alcançam o padrão. Se
alguém "melhorar" esse regex (preservar acento, hífen, pontuação), a injeção
de curinga reabre em três funções ao mesmo tempo, em silêncio. Por isso há
teste travando exatamente esse comportamento.

Reforço de projeto que vale manter: as primitivas que confiam no chamador já
ter normalizado (`legal_search_term_matches`, `normalize_practice_area_search`)
**não são executáveis por `authenticated`** — só as três RPCs de fachada são.

### Achado corrigido (não era SQLi)

`normalize_law_firm_member_roles` ecoava o texto do cliente cru na mensagem de
exceção, que vai para o log do Postgres e para a resposta do PostgREST. Uma
quebra de linha no payload **forjava uma linha de log inteira** (reproduzido:
`array[E'owner\nFALSA LINHA...']`). Alcançável por qualquer `authenticated` via
`update_law_firm_member_roles`. Corrigido na migration `20260730150000`
removendo caracteres de controle e truncando o eco. Severidade baixa: é log
injection, não injeção de comando.

### As barreiras (por que isso não regride)

A auditoria achou o código limpo **por disciplina**, não por barreira. As duas
suítes abaixo convertem cada propriedade acima em teste, e ambas foram
validadas por sabotagem deliberada (quebrar o invariante faz o teste falhar):

- `supabase/tests/injection_guards_test.sql` (9 asserções): search_path fixo,
  qualificação com `public.`, ausência de SQL dinâmico, RLS em toda tabela,
  a allowlist do normalizador, o alcance das primitivas de busca e o eco sem
  caractere de controle.
- `test/query_safety_test.dart`: varre `lib/` e proíbe filtro montado com a
  sintaxe de string do PostgREST (`.or`, `.ilike`, `.textSearch`, `.not`,
  `.match`, `.like`), nome de RPC ou de tabela vindo de variável, `.filter()`
  com interpolação e nome de coluna dinâmico em comparação/ordenação.

### Higiene conhecida, não vulnerabilidade

77 funções definer usam `set search_path = public` em vez de `''`. Não é
explorável aqui (as três barreiras acima são independentes e a qualificação
com `public.` sozinha já basta), mas é o que um scanner aponta. Migrar para
`''` exigiria qualificar chamadas do catálogo; ganho marginal dado o estado
atual.

## Cadastro com e-mail de verdade (19/08/2026, migration 20260915120000)

O cadastro aceitava qualquer endereço, inclusive descartável (dez minutos de
caixa de entrada e some). Numa plataforma onde a conta carrega CPF, casos e
correspondência com advogado, isso é a porta do abuso: cria, usa, joga fora,
repete. E torna inútil a confirmação de e-mail, que é o único canal para
recuperar senha e avisar de movimentação processual.

A barreira vive no BANCO, não na tela: a chave anon é pública (está no app e
no bundle do navegador), e um `POST /auth/v1/signup` por curl contornaria
qualquer validação de formulário. O gatilho `recusa_email_descartavel` roda
`before insert or update of email, email_change on auth.users`, que é por onde
todo cadastro passa, venha do app, do webapp, do painel ou de fora.

- `public.disposable_email_domains`: 8326 domínios (a lista pública de
  github.com/disposable-email-domains, mais alguns conferidos à mão, menos os
  provedores legítimos). RLS habilitado e nenhuma policy, com os grants
  revogados: nem `anon` nem `authenticated` leem a tabela. Manutenção pelo
  painel, como `jurii_staff`.
- `public.email_e_descartavel(text)`: `security definer`, `search_path` fixo.
  Compara o domínio E os sufixos dele (`algo.mailinator.com` cai junto com
  `mailinator.com`, que é o contorno mais barato), buscando pela chave
  primária em vez de varrer 8 mil linhas com LIKE. Nunca compara o TLD
  sozinho, o que bloquearia um país inteiro.
- A função é executável por `anon` de propósito: a tela pergunta ANTES de
  enviar para dizer o motivo, em vez de mostrar erro de servidor. A lista não
  é segredo (é pública), e quem decide continua sendo o gatilho.
- `privaterelay.appleid.com` fica fora da lista de propósito: é o "Ocultar meu
  e-mail" da Apple, que o login com Apple usa. Bloquear quebraria o cadastro
  de quem entra por lá. Há teste travando isso.

Falha de rede na checagem prévia deixa o cadastro seguir (o banco decide):
errar para o lado de deixar passar só adianta a recusa para quem tem a palavra
final; errar para o lado de bloquear travaria cadastro legítimo por causa de
uma consulta.

Provado em `supabase/tests/email_descartavel_test.sql` (22 asserções): recusa
por caixa alta, espaço, ponto final de FQDN e subdomínio de vários níveis;
recusa na troca de endereço e já no pedido de troca (`email_change`); passagem
de provedor comum, domínio próprio de escritório e do e-mail privado da Apple;
tabela ilegível para quem está logado; função respondendo a `anon`. E medido
pela API real: `POST /auth/v1/signup` com `@mailinator.com` responde
`{"code":"23514","message":"Disposable email domains are not allowed"}`,
enquanto o cadastro legítimo responde 200 com sessão.

## Rodada de hardening (19-20/08/2026)

Auditoria adversarial em seis superfícies (RLS, funções definer, webapp,
segredos, app, storage), com cada achado reproduzido antes de virar correção.
Dos achados brutos, 5 sobreviveram à verificação; 14 foram refutados (barreira
que o auditor não viu, decisão deliberada do produto, ou teoria sem exploração).

### O convite por link tinha porta dos fundos (crítico, migration 20260916120000)

A 20260914 trocou o desenho do convite (o link passou a PEDIR entrada, com
aprovação de um gestor) mas deixou a função antiga, `aceitar_link_de_convite`,
viva e com `execute` concedido a `authenticated`. Quem tivesse o token e um
login qualquer chamava a RPC direto na API e entrava na banca como membro
ATIVO, sem pedido e sem ninguém aprovar. Reproduzido no banco local e pela API
com a chave publicável: a linha nasce em `law_firm_members` com status
`active`, e `law_firm_join_requests` fica vazia. Como `can_access_conversation`
libera qualquer membro ativo da banca, o estranho passava a ler a
correspondência do escritório com os clientes, que é exatamente o que o
redesenho queria impedir.

A função saiu. Ninguém a chamava (nem app, nem webapp, nem outra função).
`supabase/tests/convite_por_link_test.sql` ainda exercitava a porta como se
fosse o comportamento certo, e foi convertido para o caminho de pedir e
decidir; `porta_dos_fundos_do_convite_test.sql` trava que ela não volta, com
uma asserção larga que pega qualquer função futura de "aceitar convite"
executável por quem está logado.

### O caso só muda por RPC (alta, migration 20260918120000)

`legal_cases` tinha `title, area, status, description, last_update_label,
deadline_at` com update direto para `authenticated`, e a policy
(`can_manage_case`) considera o CLIENTE como quem gerencia o caso dele.
Reproduzido: o cliente fecha o próprio caso, reabre e reescreve o título
direto pela API, sem passar por `close_legal_case` nem `reopen_legal_case`.
Sem aviso ao advogado, sem registro de quem fechou, sem convite de avaliação,
e com o advogado vendo um título que não escreveu. O insert direto tinha o
mesmo problema de origem.

O grant de escrita saiu inteiro. As sete funções que escrevem na tabela são
todas SECURITY DEFINER e não dependem do grant de quem chama; app e webapp só
leem. As policies ficam como segunda camada, para o caso de alguém reconceder
o grant sem pensar. `caso_so_muda_por_rpc_test.sql` trava o invariante
(nenhuma coluna gravável), e a asserção de `case_process_timeline_test.sql`
que dizia "colunas de conteudo continuam com update direto (comportamento
preservado)" foi corrigida: ela travava justamente o furo.

### A fila da revisão não se fura (baixa, migration 20260919120000)

`lawyer_verifications` aceitava escrita direta. As policies seguravam o
essencial (ninguém se aprova: o WITH CHECK prende `status` em draft/pending e
exige `reviewer_id`/`reviewed_at` nulos), mas as colunas de tempo passavam, e
com elas o candidato reescrevia o próprio `submitted_at` para passar na frente
na fila que a equipe revisa por ordem de envio. O envio legítimo sempre foi
por `submit_lawyer_verification` (definer), no app e no webapp. Grant de
escrita revogado, mesmo desenho de `legal_cases`.

### O selo diz o que é (migration 20260917120000)

A fila de pedidos de entrada mostrava "CPF confirmado" para quem decide
aprovar alguém na equipe. Nada confirma esse CPF: ele é digitado no cadastro e
só passa por dígito verificador. O gestor lia "confirmado" e aprovava achando
que a plataforma checou a identidade, que é justamente a decisão que ele está
tomando. A coluna virou `cpf_informado`, e a tela diz "CPF informado", em tom
neutro. Um teste trava que nenhuma coluna volte a prometer "confirmado".

Este item foi refutado como vulnerabilidade (não dá acesso a nada), e corrigido
mesmo assim: interface que promete verificação inexistente é defeito de
honestidade, que numa decisão de acesso vale tanto quanto permissão.

### No webapp (PR próprio)

- `sharp` fixado em 0.35.x por `overrides`, fechando quatro CVEs herdadas do
  libvips sem subir o Next de major. `npm audit` em zero.
- `buscaEndereco` passou a exigir sessão: server action é endpoint POST como
  outro qualquer, e sem isso qualquer pessoa usava o servidor da Jurii como
  proxy para as três APIs externas da cascata de CEP. O Nominatim bane por IP.

### Refutados que valem registro

Não são defeitos, e ficam aqui para a próxima auditoria não gastar fôlego:
escrita em `messages` por estagiário (a policy olha participação, e o papel na
banca não dá passe); `assinaDocumentos` sem checar `jurii_staff` (a RLS do
storage decide, não a action); cookie de sessão sem `Secure` (o Supabase marca
em produção, e o HSTS já força HTTPS); token de convite na query string do
redirect (é o próprio destino da pessoa, e o link já é de uso único);
comparação do token do webhook com `!==` (o segredo tem entropia alta e o
canal é HTTPS: timing remoto não é caminho viável aqui); chave de service_role
nos scripts de prova (é a default do CLI local, não a de produção).
