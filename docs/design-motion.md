# Design premium e motion - Jurii

Atualizado em: 11/07/2026
Branch: `fix/design`

Este documento registra a frente de polimento visual, microinteracoes e animacoes
do app. A ideia e deixar a Jurii mais fluida e premium sem mudar regra de
negocio, sem inventar uma nova identidade visual e sem sair do `AppTheme`.

## Principios

- Motion curto e discreto: feedback rapido, sem parecer decorativo demais.
- Usar `Curves.easeOutCubic` como curva principal, igual ao menu `+` do chat.
- Respeitar `MediaQuery.disableAnimations` nos helpers novos.
- Preferir componentes reutilizaveis a animacoes espalhadas tela por tela.
- Manter a paleta navy/dourado/roxo existente e evitar refatoracao visual ampla
  nesta primeira leva.

## Feito nesta primeira leva

### Infraestrutura

Criei `lib/widgets/jurii_motion.dart` com:

- `JuriiMotion`: duracoes e curvas padrao;
- `JuriiPressable`: leve escala no toque para cards e atalhos;
- `JuriiFadeThroughSwitcher`: troca de tela/estado com fade e slide curto;
- `JuriiStaggeredItem`: entrada em cascata para listas e grids;
- `JuriiAnimatedCounter`: contador que renderiza o valor inicial direto e anima
  mudancas posteriores;
- `JuriiSkeletonCard` e `JuriiSkeletonList`: loading visual para listas.

### Navegacao

- `MainNavigation`, `LawyerNavigation` e `FirmNavigation` agora usam
  `JuriiFadeThroughSwitcher` para trocar abas com uma transicao leve.
- `JuriiBottomNav` e `FirmBottomNav` ganharam:
  - indicador animado;
  - escala sutil no icone selecionado;
  - troca animada de icone outlined/filled;
  - texto com cor/peso animados;
  - press feedback nos itens.

### Home e descoberta

- `CategoriesSection` ganhou entrada em cascata no grid.
- `RecommendedLawyersSection` e `OfficesSection` ganharam:
  - skeleton loading no lugar de spinner circular;
  - fade-through entre loading/empty/lista;
  - entrada em cascata dos cards.
- `CategoryCard`, `LawyerProfileCard` e `OfficeCard` usam press feedback.

### Mensagens e casos

- `ConversationCard` ganhou press feedback.
- Listas de conversas em cliente, advogado e escritorio usam
  `JuriiStaggeredItem`.
- Segmento `Clientes/Equipe` em mensagens do escritorio ganhou transicao de
  estado e press feedback.
- `LawyerCaseCard`, cards de caso do cliente e cards de caso do escritorio
  ganharam press feedback e/ou entrada em cascata.
- Loadings de casos de advogado/escritorio usam skeleton list.

### Dashboards profissional e escritorio

- Atalhos rapidos dos dashboards de advogado e escritorio usam press feedback.
- Cards de metricas do advogado e escritorio usam `JuriiAnimatedCounter`.
- Linhas de atencao do dashboard do advogado tambem animam numeros quando eles
  mudam.

### Verificacao

- Cards de documento nas verificacoes de advogado e escritorio usam
  `AnimatedContainer` para transicionar borda de erro/sucesso.
- Estado `Selecionar` -> `Anexado` ganhou check visual e borda verde, sem manter
  texto antigo na arvore para nao atrapalhar testes ou cliques rapidos.

## Feito nesta segunda leva

### Infraestrutura complementar

- Adicionei `JuriiPulse` em `lib/widgets/jurii_motion.dart` para chamar atencao
  de forma sutil em badges e pontos de descoberta.
- Criei `lib/widgets/jurii_empty_state.dart` com `JuriiEmptyState`, um estado
  vazio reutilizavel com icone, titulo, mensagem, acao opcional e entrada
  animada.

### Chat e triagem IA

- `ChatScreen` agora usa skeleton list durante carregamento de mensagens.
- Bolhas novas entram com `JuriiStaggeredItem`, vindo da direita/esquerda
  conforme autoria.
- O composer ganhou foco animado, sombra superior sutil e botao de envio que
  responde ao texto digitado.
- O botao `+` ganhou fundo animado quando aberto, rotacao usando `JuriiMotion` e
  ponto dourado pulsante quando a triagem ainda precisa ser descoberta.
- As opcoes do menu `+` agora entram em cascata e usam press feedback.
- A ida conversa -> triagem IA usa `PageRouteBuilder` com fade/slide curto.
- Tiles de anexo dentro das bolhas usam press feedback.

### Empty states

- Apliquei `JuriiEmptyState` em mensagens de cliente/advogado/escritorio.
- Apliquei `JuriiEmptyState` em casos de cliente/advogado/escritorio.
- Apliquei `JuriiEmptyState` em agenda, recomendacoes de advogados,
  recomendacoes de escritorios, chat vazio, notificacoes vazias e updates vazios
  de caso.

### Notificacoes e detalhes de caso

- Badge do `NotificationBell` agora aparece/desaparece com scale/fade e usa
  `JuriiPulse` quando ha notificacoes pendentes.
- Itens da bottom sheet de notificacoes entram em cascata.
- `CaseDetailsScreen` trocou spinner de atualizacoes por skeleton list.
- Atualizacoes do caso agora aparecem como timeline visual, com linha e ponto de
  progresso.

## Feito nesta terceira leva

### Formularios de autenticacao

- Criei `lib/widgets/jurii_form_motion.dart` com:
  - `JuriiFormErrorBanner`: banner de erro animado com `AnimatedSize`, icone e
    superficie vermelha padronizada;
  - `JuriiFormProgressCard`: card de progresso para formularios longos.
- `LoginScreen` ganhou entrada em cascata no logo, campos, CTA, divisores,
  botoes sociais, CTA de cadastro e aviso legal.
- A navegacao login -> cadastro agora usa fade/slide curto com `PageRouteBuilder`.
- O modal de recuperacao de senha usa o novo banner de erro.
- `RegisterScreen`, `RegisterForm` e `RegisterSocialButtons` ganharam entrada em
  cascata nos principais blocos.
- Indicadores de forca de senha no cadastro e reset agora usam `AnimatedSize` e
  barras com `AnimatedContainer`.
- `PasswordResetScreen` ganhou entrada em cascata e banner de erro padronizado.

### Areas de atuacao e verificacao

- `PracticeAreaSelector` deixou de usar `FilterChip` padrao e passou a usar
  chips Jurii com `JuriiPressable`, borda/cor animadas, sombra leve e check que
  aparece com `AnimatedSize`.
- Formularios de verificacao de advogado e escritorio ganharam
  `JuriiFormProgressCard`, mostrando progresso em tempo real conforme dados,
  areas e documentos sao preenchidos.
- Mensagens de erro de envio nas verificacoes agora usam
  `JuriiFormErrorBanner`.

## Feito nesta quarta leva

### Componentes compartilhados

- Adicionei `JuriiLoadingButton` em `lib/widgets/jurii_form_motion.dart` para
  padronizar CTA com loading: sombra, altura, label -> spinner com
  `AnimatedSwitcher` e suporte a cor customizada.
- Adicionei `JuriiModalSheetScaffold` para bottom sheets com handle, radius,
  safe area e ajuste de teclado consistentes.

### Aplicacoes

- Substitui CTAs carregando em login, cadastro, reset de senha e verificacoes de
  advogado/escritorio por `JuriiLoadingButton`.
- A troca icone/logo -> spinner dos botoes sociais de login/cadastro agora usa
  `AnimatedSwitcher`.
- Bottom sheets de recuperacao de senha, solicitacao de caso no chat e adicionar
  atualizacao em caso usam `JuriiModalSheetScaffold`.
- Loadings de mensagens do cliente, mensagens do advogado, mensagens do
  escritorio e casos do cliente passaram de spinner solto para skeleton list com
  contexto de tela.

## Feito nesta quinta leva

### Cards de listagem

- Criei `lib/widgets/jurii_list_card.dart` com superficie reutilizavel para
  cards de lista: padding, radius, borda, sombra sutil, press feedback e respeito
  a `MediaQuery.disableAnimations`.
- Ajustei `JuriiPressable` para permitir `clipBehavior: Clip.none` quando o
  componente precisa preservar sombra externa, mantendo o comportamento antigo
  como default.
- Apliquei `JuriiListCard` em cards de conversa, advogado, escritorio, caso do
  advogado, caso do cliente, caso do escritorio, prioridade do dashboard do
  advogado e membro de equipe do escritorio.
- Mantive o conteudo interno dos cards e callbacks existentes; a mudanca foi de
  superficie, consistencia visual e reducao de duplicacao.

## Feito nesta sexta leva

### Bottom sheets de equipe e escritorio

- Troquei os dialogs antigos de convite de advogado e edicao de cargos da equipe
  por `showModalBottomSheet` com `JuriiModalSheetScaffold`.
- O convite de advogado agora usa layout compacto de OAB, `JuriiFormErrorBanner`
  e `JuriiLoadingButton` em vez de spinner manual dentro de `FilledButton`.
- A edicao de cargos agora usa tiles selecionaveis animados, com borda/cor
  transicionando conforme selecao e estado desabilitado para cargo de dono
  quando o usuario nao pode altera-lo.
- Padronizei o bottom sheet de atribuicao de caso do escritorio com
  `JuriiModalSheetScaffold` e `JuriiListCard`, deixando a escolha de advogado
  com avatar, check animado e superficie consistente.

## Feito nesta setima leva

### Spinners restantes (prioridade alta) — decisao caso a caso

Trocados por skeleton (contexto de lista/secao, onde spinner esconde o layout):

- Home do advogado: secao "Hoje", casos prioritarios e novos contatos.
- Agenda: lista de compromissos.
- Triagem IA: abertura da conversa (hoje o servico local e instantaneo, mas a
  IA remota tera latencia real ali).

Mantidos de proposito (nao sao pendencia):

- Spinners dentro de botoes (excluir conta, abrir chat, enviar, anexar) — e o
  padrao `JuriiLoadingButton`/feedback pontual de acao.
- Splash de bootstrap no `main.dart` (momento de marca, nao de conteudo).
- Indicadores pontuais do chat (avatar carregando, imagem no dialog).

### Cards e sheets (prioridade media)

- Card de compromisso da agenda migrou para `JuriiListCard` + entrada em
  cascata. Removido `onTap` vazio que dava ripple num card sem acao — ripple
  em card inerte sugere interacao que nao existe.
- Bottom sheet de notificacoes padronizado com `JuriiModalSheetScaffold`.
  CUIDADO de layout descoberto aqui: dentro do scaffold a Column nao repassa
  altura limitada, entao `Flexible`+ListView quebra — listas longas dentro do
  scaffold precisam de teto explicito (`ConstrainedBox` com maxHeight
  proporcional a tela).
- Dialogs de confirmacao destrutiva (excluir conta, sair da triagem) FICAM
  como `AlertDialog` — confirmacao destrutiva pede dialog, nao sheet.

### Formularios de verificacao por etapas (prioridade media)

- Novo `JuriiFormSectionHeader` em `jurii_form_motion.dart`: circulo numerado
  (1/2/3) que vira check verde animado quando a etapa completa, conversando
  com o `JuriiFormProgressCard`.
- Aplicado nos dois formularios (advogado e escritorio): Dados, Areas e
  Documentos agora sao etapas visuais; no escritorio com accent roxo.
- `PracticeAreaSelector` recebeu `label: 'Selecione as areas'` nesses usos
  para o rotulo do campo nao duplicar o titulo da secao.

### Migracao AppTheme.* -> context.jColors (primeiro item do "depois")

- **CONCLUIDA: as 819 referencias estaticas em 53 arquivos foram migradas.**
  Fora de `lib/theme/` restam apenas `AppTheme.lightTheme/darkTheme` no
  `main.dart` (wiring do MaterialApp, intencional).
- Helpers compartilhados (`JuriiListCard`, `JuriiEmptyState`,
  `JuriiFormProgressCard`, `JuriiLoadingButton`, `JuriiModalSheetScaffold`,
  `JuriiFormSectionHeader`, `PracticeAreaSelector`, `NotificationBell`)
  trocaram defaults const de cor por parametros `Color?` anulaveis resolvidos
  no build — API 100% compativel com os call sites existentes.
- Getters de cor em widgets viraram metodos com parametro `AppColors`
  (ex.: `_avatarColor(colors)`), e helpers static recebem `colors` de quem
  chama.
- Consequencia: **o app inteiro agora reage ao tema — o dark mode pode ser
  ativado** (ver "Falta fazer").

## Validacao

Rodado em 10/07/2026:

- `dart format` nos arquivos alterados;
- `flutter analyze` sem issues;
- `flutter test test/chat_triage_test.dart` passando depois dos ajustes de
  composer/menu `+`;
- `flutter test` com 47 testes passando.

Rodado em 11/07/2026:

- `dart format` nos arquivos alterados da terceira leva;
- `flutter analyze` sem issues;
- `flutter test` com 47 testes passando.
- `dart format` nos arquivos alterados da quarta leva;
- `flutter analyze` sem issues.
- `flutter test` com 47 testes passando.
- `dart format` nos arquivos alterados da quinta leva;
- `flutter analyze` sem issues.
- `flutter test` com 47 testes passando.
- `dart format` nos arquivos alterados da sexta leva;
- `flutter analyze` sem issues.
- `flutter test` com 47 testes passando.

Rodado na setima leva:

- `dart format lib/` (121 arquivos, 34 alterados);
- `flutter analyze` sem issues;
- `flutter test` com 49 testes passando;
- `grep AppTheme.` fora de `lib/theme/`: somente lightTheme/darkTheme no
  main.dart.

## Falta fazer

Prioridade alta:

- **Ativar o dark mode** (a migracao jColors esta completa): mudar o default
  do `ThemeController` para `system`, expor toggle no perfil e persistir com
  `shared_preferences` (receita em docs/architecture.md). ANTES de ativar,
  fazer um QA visual completo no tema escuro — a paleta dark foi desenhada
  mas nunca foi vista tela a tela.

Prioridade media:

- Expandir `JuriiListCard` para os cards privados que sobraram em detalhes de
  caso e telas de perfil quando houver ganho claro (agenda ja migrou).
- Revisar responsividade dos dashboards em telas pequenas depois das
  animacoes.

Prioridade depois:

- Adicionar testes focados para helpers de motion/composer se eles passarem a
  carregar mais comportamento.
- Golden tests do tema escuro nas telas principais quando o dark mode ativar.

## Cuidados para proximas alteracoes

- Evitar `AnimatedSwitcher` em textos/botoes que testes ou usuarios clicam em
  sequencia rapida, porque o widget antigo fica temporariamente na arvore.
- Em listas longas, limitar delays de stagger para nao atrasar a interacao.
- Em telas juridicas sensiveis, motion deve esclarecer estado e hierarquia, nao
  mascarar informacao.
- Codigo novo usa SEMPRE `context.jColors` (nunca `AppTheme.*` estatico — os
  tokens de cor sairam de circulacao fora de `lib/theme/`).
- Em componentes reutilizaveis, cor customizavel = parametro `Color?` anulavel
  resolvido no build com `?? colors.token`; default const de cor quebra o tema.
- Dentro de `JuriiModalSheetScaffold`, listas roláveis precisam de altura
  maxima explicita (`ConstrainedBox`); `Flexible` quebra.
