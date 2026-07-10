# Notas para troca com o socio - auditoria, busca, casos, LGPD e design

Atualizado em: 10/07/2026
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

Criei `supabase/patch_043_fix_firm_case_scope.sql`.

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

- `supabase/patch_044_account_deletion_lgpd.sql`;
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
supabase --output-format text db query --linked --file supabase/patch_044_account_deletion_lgpd.sql
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

## Como revisar esta branch

Arquivos principais:

- `supabase/patch_044_account_deletion_lgpd.sql`;
- `supabase/functions/delete-account/index.ts`;
- `lib/repositories/profile_repository.dart`;
- `docs/security.md`;
- `supabase/README.md`;
- `.gitignore`.

Fluxo esperado para ambiente novo:

1. rodar `supabase/patch_044_account_deletion_lgpd.sql` depois do patch 043;
2. publicar a Function:

```bash
supabase functions deploy delete-account --project-ref rlgtgipxltucrtkyrmag --use-api
```

3. testar com uma conta descartavel confirmada antes de usar em conta real.

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

Criei e apliquei `supabase/patch_045_profiles_id_update_grant.sql`:

```sql
grant update (id) on public.profiles to authenticated;
```

E seguro porque a policy `profiles_update_own` ja e
`using (id = auth.uid()) with check (id = auth.uid())` — conceder UPDATE em `id`
nao permite repontar a linha para outro usuario; o `SET id = EXCLUDED.id` vira
no-op.

Aplicado em 06/07/2026 via:

```bash
supabase --output-format text db query --linked --file supabase/patch_045_profiles_id_update_grant.sql
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
