# Notas para troca com o socio - auditoria, busca, casos, LGPD e design

Atualizado em: 11/07/2026
Branch atual: `fix/design`
Base atual: `main`/`origin/main` no commit `3ee49f2`
(`Adiciona patch de escopo dos casos do escritorio`)

## Resumo executivo

Pegamos a branch `feat/auditoriaLLM`, revisamos as mudancas, validamos o que ja
existia e fechamos tres frentes importantes:

1. busca juridica com menos falsos positivos;
2. escopo correto de casos dentro da area do escritorio;
3. inicio de exclusao LGPD completa via Edge Function, com service role,
   auditoria e banimento do usuario no Auth.

A parte de busca e escopo de casos ja esta em `main`. A parte LGPD esta na
branch `fix/exclusao`, com patch SQL, Edge Function publicada e app chamando a
Function em vez da RPC direta.

## O que revisamos primeiro

Analisei a branch `feat/auditoriaLLM`, que tinha varias mudancas de seguranca,
busca e integracao. A avaliacao foi positiva: as mudancas estavam indo na
direcao certa, mas ainda havia pontos que precisavam de validacao em banco e
algumas pendencias LGPD.

Antes de seguir, rodei validacoes locais:

- `flutter analyze`;
- `flutter test`.

Tambem fizemos smoke tests remotos contra Supabase usando a conta de teste
`vscode@gmail.com`, sem executar a exclusao de conta.

## Patch 041 e 042

O patch 041 trouxe hardening de seguranca: bloqueio de autopromocao para
advogado, reducao de exposicao de PII, restricoes em mensagens `system`,
endurecimento de verificacoes e limites em anexos de chat.

O patch 042 corrigiu o matching de areas juridicas na busca. O problema principal
era substring solta: por exemplo, `iss` casava dentro de `demissao`, causando
falso positivo de Direito Tributario em relato trabalhista.

Depois de rodar os seeds/patches corretos, validamos:

- `legal_search_intents` populado;
- `legal_categories` populado;
- termo ambiguo `das` removido;
- `demissao` nao inferindo mais Tributario;
- `meu marido me bateu` inferindo Criminal;
- `inss negou meu auxilio` inferindo Previdenciario;
- recomendacoes de advogados/escritorios continuando a executar;
- autopromocao bloqueada.

## Patch 043 - escopo dos casos do escritorio

Criei `supabase/legacy_patches/patch_043_fix_firm_case_scope.sql`.

O problema: a area do escritorio podia enxergar ou reatribuir casos pessoais de
advogados membros, ou ate casos de outro escritorio, apenas porque aquele
advogado fazia parte do escritorio.

A correcao foi recriar:

- `fetch_law_firm_cases`;
- `assign_law_firm_case`.

Agora essas funcoes so tratam como caso do escritorio linhas em `legal_cases`
com `law_firm_id = law_firm_id_value`.

Tambem atualizei:

- `docs/security.md`;
- `supabase/README.md`.

Smoke tests feitos depois do patch:

- escritorio aleatorio nao lista casos indevidos;
- escritorio proprio executa;
- usuario sem papel gerencial nao consegue atribuir caso;
- busca juridica continuou correta.

Esse patch foi commitado como:

`3ee49f2 Adiciona patch de escopo dos casos do escritorio`

## Patch 044 - exclusao LGPD via Edge Function

Depois disso atacamos a proxima pendencia LGPD: exclusao de conta.

Antes, o app chamava `delete_current_account()` diretamente pelo cliente. Isso
fazia o soft-delete transacional, mas nao conseguia cobrir tudo que precisa de
privilegio elevado, como apagar Storage sensivel e banir o usuario em
`auth.users`.

Criei:

- `supabase/legacy_patches/patch_044_account_deletion_lgpd.sql`;
- `supabase/functions/delete-account/index.ts`.

Tambem atualizei:

- `lib/repositories/profile_repository.dart`;
- `docs/security.md`;
- `supabase/README.md`;
- `.gitignore`, para ignorar `supabase/.temp/` criado pelo `supabase link`.

### O que o patch SQL faz

`patch_044_account_deletion_lgpd.sql` cria a tabela
`public.account_deletion_audit`, com RLS ativo, sem acesso para `anon` ou
`authenticated`, e com `select/insert/update` liberado apenas para
`service_role`.

Ele tambem recria `public.delete_current_account()` mantendo o soft-delete
transacional existente e corrigindo literals antigos de exibicao, como
`(conta excluida)`.

Em 06/07/2026, o patch foi aplicado no projeto remoto pelo Supabase CLI:

```bash
supabase --output-format text db query --linked --file supabase/legacy_patches/patch_044_account_deletion_lgpd.sql
```

### O que a Edge Function faz

A Edge Function `delete-account` roda com `service_role` e executa o fluxo:

1. valida o JWT do usuario;
2. cria linha de auditoria em `account_deletion_audit`;
3. apaga Storage sensivel dos buckets `verification-documents` e
   `profile-avatars`;
4. chama `delete_current_account()` como o proprio usuario, preservando
   `auth.uid()`;
5. bane o usuario em `auth.users`;
6. tenta encerrar sessoes;
7. atualiza a auditoria como `completed` ou `failed`.

Nao apagamos anexos de chat nem documentos de caso nessa rotina, porque podem
ser prova/evidencia. Isso precisa de uma politica de retencao propria.

### Ajuste importante no deploy

A primeira versao da Edge Function importava `jsr:@supabase/supabase-js@2`.
Durante o deploy, o bundler remoto do Supabase falhou com erro 500/OOM.

Para resolver, reescrevi a Function para usar `fetch` direto nos endpoints REST,
Auth e Storage do Supabase, sem dependencia externa. Com isso o deploy passou.

Status remoto confirmado:

- Function `delete-account` ativa;
- `verify_jwt=true`;
- secrets padrao presentes, incluindo `SUPABASE_URL`, `SUPABASE_ANON_KEY` e
  `SUPABASE_SERVICE_ROLE_KEY`.

## Testes executados na rodada LGPD

Locais:

- `git diff --check`;
- `flutter analyze`;
- `flutter test` com 36 testes passando.

Deploy/verificacao da Edge Function:

- `supabase functions deploy delete-account --project-ref rlgtgipxltucrtkyrmag --use-api`;
- `supabase functions list --project-ref rlgtgipxltucrtkyrmag`.

HTTP seguro:

- `OPTIONS /functions/v1/delete-account` retornou `200`;
- `POST /functions/v1/delete-account` sem token retornou `401`;
- `GET /functions/v1/delete-account` com JWT valido retornou `405`, ou seja,
  o token chega na Function, mas metodo errado nao dispara exclusao.

Banco/seguranca:

- `patch_044_account_deletion_lgpd.sql` rodou com sucesso via Supabase CLI;
- consulta SQL remota confirmou que `public.account_deletion_audit` existe;
- consulta SQL remota confirmou que `delete_current_account` esta como
  `SECURITY DEFINER`;
- REST publico contra `account_deletion_audit` retornou `permission denied`,
  como esperado.

## O que nao foi testado de proposito

Nao executei `POST /delete-account` com a conta `vscode@gmail.com`, porque isso
baniria e excluiria a conta de verdade.

Tentei criar uma conta descartavel
`codex.delete.test.20260706.1439@example.com`, mas o projeto exige confirmacao
de email e o signup nao retornou sessao/JWT. Sem JWT confirmado, nao dava para
testar o fluxo destrutivo completo com seguranca.

Proximo teste ideal: criar/confirmar uma conta descartavel real, fazer login,
executar `POST /functions/v1/delete-account` nela e conferir:

- linha `completed` em `account_deletion_audit`;
- `deleted_at` preenchido em `profiles`;
- CPF, telefone e avatar limpos;
- arquivos de verificacao/avatar removidos;
- usuario banido em `auth.users`;
- login posterior bloqueado.

## Decisoes tomadas

- Mantivemos a logica transacional sensivel dentro de
  `delete_current_account()`.
- Levamos para Edge Function apenas o que precisa de privilegio elevado:
  Storage, banimento no Auth e auditoria tecnica.
- Nao apagamos anexos de chat/caso sem politica de retencao, para nao destruir
  prova potencial.
- Evitamos colocar `service_role` no app; a chave fica apenas no ambiente da
  Edge Function.
- Reescrevemos a Function sem dependencias externas para reduzir risco de deploy
  no bundler remoto.

## Frente seguinte - Politica de Privacidade e Termos no app

Depois do patch 044, avancei na pendencia de deixar Politica de Privacidade e
Termos de Uso acessiveis dentro do produto.

O que foi feito:

- criei conteudo versionado em `lib/data/legal_documents.dart`;
- criei a tela reutilizavel `lib/screens/legal_document_screen.dart`;
- criei `lib/widgets/legal_agreement_notice.dart` para transformar os textos de
  concordancia do login/cadastro em links reais;
- liguei os itens `Termos de Uso` e `Política de Privacidade` do perfil às novas
  telas;
- atualizei `docs/security.md` para marcar essa parte como resolvida no app,
  mantendo como pendencias a revisao juridica final, canal oficial do titular,
  DPO/encarregado, consentimento e retencao documental.

Observacao: o texto dentro do app e uma versao inicial de transparencia para
produto. Antes de publicar nas lojas, ainda precisa de revisao juridica e da
definicao do canal oficial de privacidade.

## Frente atual - Design premium e motion

Em 10/07/2026 comecei a frente de polimento visual e animacoes do app. Criei um
documento especifico em `docs/design-motion.md` para registrar o que foi feito,
o que falta fazer e os cuidados de implementacao.

O que foi implementado nesta primeira leva:

- criei `lib/widgets/jurii_motion.dart` com helpers reutilizaveis:
  `JuriiPressable`, `JuriiFadeThroughSwitcher`, `JuriiStaggeredItem`,
  `JuriiAnimatedCounter`, `JuriiSkeletonCard` e `JuriiSkeletonList`;
- adicionei transicao leve entre abas em `MainNavigation`, `LawyerNavigation` e
  `FirmNavigation`;
- animei os bottom navs (`JuriiBottomNav` e `FirmBottomNav`) com indicador,
  escala de icone, troca outlined/filled e texto animado;
- apliquei press feedback nos cards principais de advogados, escritorios,
  conversas, categorias e casos;
- adicionei entrada em cascata em listas/grids de descoberta, mensagens e casos;
- troquei alguns spinners por skeletons nas listas de recomendacoes/casos;
- animei contadores dos dashboards de advogado/escritorio;
- melhorei a confirmacao visual de documentos anexados nas verificacoes de
  advogado e escritorio.

Validacao feita:

- `dart format` nos arquivos alterados;
- `flutter analyze` limpo;
- `flutter test` com 47 testes passando.

O que ainda falta nessa frente esta listado em `docs/design-motion.md`. Os
proximos melhores alvos sao: animar bolhas novas do chat, melhorar a transicao
conversa -> resumo da triagem IA, animar badge/sheet de notificacoes e trocar
spinners restantes por skeletons.

Continuidade da frente de design em 10/07/2026:

- criei `lib/widgets/jurii_empty_state.dart` com um empty state reutilizavel e
  apliquei em mensagens, casos, agenda, recomendacoes, chat vazio, notificacoes
  vazias e updates vazios;
- adicionei `JuriiPulse` em `lib/widgets/jurii_motion.dart`;
- melhorei o `ChatScreen`: skeleton no carregamento, entrada animada de bolhas,
  composer com foco animado, botao de envio responsivo, `+` com pulso/rotacao e
  menu de opcoes em cascata;
- a transicao conversa -> triagem IA agora usa fade/slide curto;
- tiles de anexo dentro do chat ganharam press feedback;
- `NotificationBell` ganhou badge animado/pulsante e itens da sheet em cascata;
- `CaseDetailsScreen` ganhou skeleton no loading de updates e timeline visual
  com linha/ponto de progresso.

Com isso, os itens de maior impacto visual listados para chat, notificacoes,
empty states e timeline de caso foram enderecados. O restante da frente ficou
mais ligado a formularios/login/cadastro, consolidacao de wrappers e ajustes de
responsividade.

Continuidade da frente de design em 11/07/2026:

- criei `lib/widgets/jurii_form_motion.dart` com `JuriiFormErrorBanner` e
  `JuriiFormProgressCard`;
- apliquei entrada em cascata nos fluxos de login, cadastro, cadastro social e
  redefinicao de senha;
- padronizei erros de login, cadastro, recuperacao de senha, reset e verificacao
  com banner animado em vez de texto solto;
- a rota login -> cadastro agora usa fade/slide curto;
- indicadores de forca de senha no cadastro e no reset agora animam a entrada e
  a mudanca das barras;
- `PracticeAreaSelector` agora usa chips Jurii customizados, com press feedback,
  borda/cor/sombra animadas e check animado;
- formularios de verificacao de advogado e escritorio ganharam card de progresso
  em tempo real conforme campos, areas e documentos sao preenchidos.

Com isso, tambem foram enderecados os itens pendentes de motion em
login/cadastro, selecao de areas e progresso visual de verificacao. O que fica
para a proxima rodada de design e mais estrutural: consolidar wrapper unico para
cards de listagem, revisar bottom sheets restantes e padronizar transicao
label/spinner em botoes.

Ainda em 11/07/2026, continuei a consolidacao de design system:

- adicionei `JuriiLoadingButton` para padronizar CTAs com loading e transicao
  label -> spinner;
- adicionei `JuriiModalSheetScaffold` para bottom sheets com handle, radius,
  safe area e comportamento de teclado consistentes;
- apliquei `JuriiLoadingButton` em login, cadastro, reset de senha e
  verificacoes de advogado/escritorio;
- os botoes sociais de login/cadastro agora animam logo/icone -> spinner;
- bottom sheets de recuperacao de senha, solicitacao de caso no chat e adicionar
  atualizacao no caso usam o scaffold padronizado;
- troquei spinners soltos por skeletons em mensagens do cliente, mensagens do
  advogado, mensagens do escritorio e casos do cliente.

O proximo passo de design passa a ser menos "tela isolada" e mais
consolidacao: wrapper unico para cards de listagem e migracao gradual de bottom
sheets restantes.

Ainda em 11/07/2026, avancei na quinta leva de design, focada em consolidar
cards de listagem:

- criei `lib/widgets/jurii_list_card.dart`, um wrapper reutilizavel para cards
  de lista com padding, borda, radius, sombra sutil e press feedback;
- ajustei `JuriiPressable` para permitir preservar sombra externa quando o card
  precisa desse efeito, sem mudar o comportamento default dos usos antigos;
- migrei para esse wrapper os cards de conversa, advogado, escritorio, caso do
  advogado, caso do cliente, caso do escritorio, prioridade do dashboard do
  advogado e membro de equipe do escritorio;
- a mudanca manteve conteudo e callbacks existentes, mas reduziu duplicacao e
  deixou as superficies de listagem mais consistentes/premium.

Validacao da quinta leva:

- `dart format` nos arquivos alterados;
- `flutter analyze` limpo;
- `flutter test` com 47 testes passando.

Com isso, a pendencia do wrapper unico para cards de listagem foi enderecada. O
proximo passo de design fica entre mapear spinners restantes em fluxos menos
acessados, expandir o scaffold padronizado para bottom sheets de equipe/
escritorio e revisar responsividade dos dashboards.

Ainda em 11/07/2026, avancei na sexta leva de design, focada nos fluxos de
equipe/escritorio:

- troquei os dialogs antigos de convidar advogado e editar cargos da equipe por
  bottom sheets com `JuriiModalSheetScaffold`;
- o convite de advogado agora usa layout compacto de OAB, banner de erro
  animado e `JuriiLoadingButton`;
- a edicao de cargos ganhou tiles selecionaveis animados em vez de checkbox
  list dentro de `AlertDialog`;
- padronizei tambem o bottom sheet de atribuir caso do escritorio, usando
  `JuriiModalSheetScaffold` e `JuriiListCard` para a lista de advogados.

Validacao da sexta leva:

- `dart format` nos arquivos alterados;
- `flutter analyze` limpo;
- `flutter test` com 47 testes passando.

Com isso, a pendencia de expandir o scaffold padronizado para bottom sheets de
equipe/escritorio foi enderecada. O proximo alvo de design mais logico e mapear
spinners restantes em fluxos menos acessados e decidir caso a caso entre
skeleton, botao carregando ou manter spinner pequeno contextual.

## Pendencias depois desta rodada

As maiores pendencias restantes em seguranca/LGPD estao documentadas em
`docs/security.md`. As principais sao:

- separar ou limitar ainda mais PII entre partes de um caso;
- restringir roster de escritorios ou expor equipe publica via RPC minima;
- criar papel/admin real para revisao de OAB/escritorio;
- resolver poderes de ex-dono de escritorio;
- criar conversas/agendas apenas por RPC coerente;
- evitar enumeracao de OAB em convite;
- impedir delete de anexo ja entregue;
- implementar upload real de documentos de verificacao;
- revisar juridicamente a Politica de Privacidade/Termos agora acessiveis no
  app, criar canal oficial do titular/DPO, registro de consentimento e politica
  de retencao documentada.

## Como revisar a frente LGPD nessa branch

Arquivos principais:

- `supabase/migrations/20260711190000_squashed_legacy_baseline.sql`
  (contém o antigo `patch_044`);
- `supabase/functions/delete-account/index.ts`;
- `lib/repositories/profile_repository.dart`;
- `docs/security.md`;
- `supabase/README.md`;
- `.gitignore`.

Fluxo esperado para ambiente novo:

1. aplicar a baseline com `supabase db push`;
2. publicar a Function `delete-account`:

```bash
supabase functions deploy delete-account --project-ref rlgtgipxltucrtkyrmag --use-api
```

3. testar a exclusao com uma conta descartavel confirmada antes de usar em
   conta real.

## Revisao da branch e correcao do grant de id (patch 045)

Atualizado em: 06/07/2026
Branch revisada: `feat/AI` (= `feat/auditoriaLLM` + patch_043 + LGPD/exclusao + politica/termos).

Fiz uma revisao completa da branch, como code review de terceiro. Validacoes
locais: `flutter analyze` limpo e `flutter test` com 37 testes passando. Li os
arquivos de maior risco (patches 041 a 044, `main.dart`, repositorios de
mensagens/notificacao/escritorio, `intake_ai_service.dart`, a Edge Function
`delete-account` e as telas de politica/termos). Avaliacao geral positiva.

### Bug confirmado em runtime: upsert de profiles bloqueado (403)

Suspeitei de uma interacao entre o hardening do patch_041 e o upsert do app.
O patch_041 revogou UPDATE amplo em `public.profiles` e concedeu UPDATE apenas
em `(full_name, email, initials, cpf, phone, avatar_url)` — `id` ficou com grant
de INSERT mas nao de UPDATE. Como o app faz `.upsert()` em profiles enviando
`id` (`profile_repository.dart`), o PostgREST gera
`INSERT ... ON CONFLICT (id) DO UPDATE SET ..., id = EXCLUDED.id`, e o ramo de
UPDATE toca `id` sem privilegio.

Testei de verdade contra o `jurii-prod` (nao dava para provar so aplicando o
patch: rodar SQL pela CLI e superuser e nao passa pelos grants). Criei um usuario
confirmado via Admin API, loguei para pegar o JWT e repeti o mesmo upsert como
role `authenticated`:

- Antes: `POST /rest/v1/profiles` (Prefer: resolution=merge-duplicates)
  retornou `403` / `42501 permission denied for table profiles`; cpf/phone nao
  persistiram.

Severidade real e BAIXA hoje: a trigger `handle_new_auth_user` (patch_003,
SECURITY DEFINER) grava full_name/email/initials/cpf no cadastro sem passar por
grants, e o `signUp` manda cpf no metadata — entao o CPF persiste pela trigger,
nao pelo upsert. Nao ha outra tela do app que escreva em profiles. O caminho de
upsert fica morto: uma futura tela de editar perfil (telefone/avatar/nome)
falharia em silencio, porque o app engole o erro em try/catch.

### Correcao aplicada: patch_045

Criei e apliquei `supabase/legacy_patches/patch_045_profiles_id_update_grant.sql`:

```sql
grant update (id) on public.profiles to authenticated;
```

E seguro porque a policy `profiles_update_own` ja e
`using (id = auth.uid()) with check (id = auth.uid())` — conceder UPDATE em `id`
nao permite repontar a linha para outro usuario; o `SET id = EXCLUDED.id` vira
no-op.

Aplicado em 06/07/2026 via:

```bash
supabase --output-format text db query --linked --file supabase/legacy_patches/patch_045_profiles_id_update_grant.sql
```

Re-rodei o mesmo teste depois do patch:

- Depois: o upsert retornou `200`, e a linha voltou com
  `cpf = 52998224725` e `phone = 11999998888` persistidos.

Os dois usuarios de teste foram removidos (profiles + auth) ao fim de cada
execucao. O script de reproducao ficou no scratchpad da sessao
(`test_grant_id.sh`).

### Outras observacoes da revisao (nao bloqueantes)

- Edge Function `delete-account`: identidade vem do JWT validado (nunca do body),
  service_role so no ambiente, auditoria e fail-closed no Storage — bem feita.
  Pendencias: (1) o caminho destrutivo (POST real) ainda nao rodou ponta a ponta;
  (2) LGPD — `banUser` bane mas nao apaga `auth.users`, entao o e-mail original
  persiste no Auth (so o `profiles.email` e anonimizado); decidir entre banir ou
  deletar/limpar o e-mail; (3) a operacao nao e atomica (Storage -> soft-delete
  -> ban), mitigada pelo guard de `deleted_at` no app + retry idempotente.
- `lawyer_home_screen`: a secao "Hoje" filtra compromissos por
  `dateLabel == 'Hoje'` (string), acoplada ao texto de `appointment_repository`;
  melhor comparar data/`isToday`.
- `firm_workspace_repository`: os fallbacks de compatibilidade de schema usam
  `catch (_)` cego, que tambem engole erro de rede; ao menos logar.
- Dark mode: `darkTheme` foi construido mas nunca e exercitado (sem toggle, nem
  de dev) — risco de apodrecer sem ninguem notar quebras.

## Consolidação dos patches SQL em baseline de migrations

Atualizado em: 11/07/2026
Branch atual: `fix/design`

Depois da discussão sobre o volume de patches SQL no repositório, consolidei a
estrutura do Supabase para parar de crescer a fila `patch_001...`.

O que foi feito:

- criei `supabase/migrations/20260711190000_squashed_legacy_baseline.sql`;
- essa baseline junta `schema.sql` + patches 001 a 045 em uma migration única
  para ambientes novos;
- movi o `schema.sql` antigo para
  `supabase/legacy_patches/schema_pre_migration_baseline.sql`;
- movi os patches 001 a 045 para `supabase/legacy_patches/`;
- reescrevi `supabase/README.md` com o novo fluxo oficial:
  `supabase db push` para ambiente novo e `supabase migration new` para
  mudanças futuras;
- atualizei o README principal e `docs/security.md` para apontar para a
  baseline/legado.

Decisão importante: o projeto remoto atual já recebeu esses patches manualmente.
Então a baseline não deve ser aplicada de novo nesse remoto; ela deve apenas ser
marcada como aplicada no histórico da CLI:

```bash
supabase migration repair --linked --status applied 20260711190000
```

Daqui para frente, a regra passa a ser: nada de `patch_046`. Toda mudança nova
de banco deve entrar como migration timestampada em `supabase/migrations/`.

## Preparacao do Supabase local com Docker

Atualizado em: 11/07/2026
Branch de trabalho: `fix/DB`

Depois que o Docker Desktop ficou disponivel, preparei o repositório para rodar
o Supabase localmente via CLI, sem depender do projeto remoto para validar
migrations.

O que foi feito:

- rodei `supabase init` na branch `fix/DB`;
- adicionei `supabase/config.toml` ao projeto;
- ajustei `project_id = "jurii"` para manter um ambiente local estavel;
- desativei o seed da CLI em `[db.seed]`, porque a baseline consolidada ja
  contem os dados/seeds necessarios;
- mantive `supabase/.gitignore` gerado pela CLI para ignorar `.temp`,
  `.branches` e envs locais;
- criei `docs/supabase-local.md` com o fluxo local, comandos e smoke tests;
- atualizei `supabase/README.md` apontando para esse novo fluxo.

Tentei executar `supabase start` para baixar/subir a stack local. O processo
comecou a puxar as imagens do Supabase, mas falhou no Docker com:

```text
write /var/lib/desktop-containerd/daemon/io.containerd.metadata.v1.bolt/meta.db: input/output error
```

Diagnostico: o macOS estava com o disco praticamente cheio, entre ~106Mi e
~120Mi livres em `/`/`/Users/samuelfries`, e o Docker Desktop ocupando cerca de
13G. Com esse espaco livre, o Docker nao consegue concluir o pull das imagens
nem estabilizar o containerd.

Por seguranca, nao rodei `docker system prune` nem limpezas destrutivas amplas.
Tambem nao foi possivel rodar `supabase db reset`, porque a stack local nao
chegou a subir.

Proximo passo para finalizar essa validacao:

1. liberar alguns GB de disco ou aumentar o limite de disco do Docker Desktop;
2. reiniciar o Docker Desktop;
3. rodar `supabase start`;
4. rodar `supabase db reset`;
5. executar os smoke tests SQL documentados em `docs/supabase-local.md`.

### Nova tentativa apos limpeza do disco

Depois da limpeza do computador, o espaco livre subiu para cerca de 45GiB. Isso
removeu o bloqueio de disco do macOS, mas o Docker Desktop continuou sem subir
o daemon.

Resultado da nova tentativa:

- `df -h` confirmou espaco livre suficiente;
- `docker info` deixou de travar, mas passou a retornar
  `Cannot connect to the Docker daemon`;
- reiniciei o Docker Desktop por processo;
- os logs do Docker mostram que, durante a tentativa anterior sem espaco, o
  filesystem interno do Docker entrou em erro EXT4 e foi remontado como
  read-only:

```text
EXT4-fs (vda1): Remounting filesystem read-only
containerd ... garbage collection failed: input/output error
```

Diagnostico atualizado: a limpeza do macOS foi necessaria, mas agora o bloqueio
parece estar no disco interno do Docker Desktop (`Docker.raw`), provavelmente
corrompido/read-only depois do pull interrompido.

Nao executei limpeza destrutiva do Docker via CLI. O proximo passo seguro e
abrir Docker Desktop > Troubleshoot e usar Clean / Purge data ou Reset to
factory defaults. Isso apaga imagens, containers e volumes locais do Docker,
mas nao apaga o codigo do projeto. Depois disso, repetir:

```bash
docker info
supabase start
supabase db reset
```
