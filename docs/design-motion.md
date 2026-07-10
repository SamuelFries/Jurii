# Design premium e motion - Jurii

Atualizado em: 10/07/2026  
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

## Validacao

Rodado em 10/07/2026:

- `dart format` nos arquivos alterados;
- `flutter analyze` sem issues;
- `flutter test` com 47 testes passando.

## Falta fazer

Prioridade alta:

- Animar entrada de bolhas novas no `ChatScreen`.
- Criar transicao mais refinada conversa -> resumo na triagem IA.
- Trocar spinners restantes por skeletons nos fluxos mais acessados.
- Criar um wrapper unico para cards de listagem, reduzindo duplicacao entre
  advogado/escritorio/casos.

Prioridade media:

- Animar badge do `NotificationBell` quando uma notificacao chega.
- Animar itens dentro da bottom sheet de notificacoes.
- Melhorar timeline de `CaseDetailsScreen` com entrada dos updates e linha
  visual de progresso.
- Aplicar motion nos fluxos de login/cadastro: entrada do logo/form, erro com
  `AnimatedSize`, loading menos brusco.
- Animar selecao de chips e areas no `PracticeAreaSelector`.

Prioridade depois:

- Migrar mais telas de `AppTheme.*` estatico para `context.jColors` antes de
  ativar dark mode real.
- Revisar responsividade dos dashboards em telas pequenas depois das animacoes.
- Adicionar testes focados para os helpers de motion se eles passarem a carregar
  mais comportamento.

## Cuidados para proximas alteracoes

- Evitar `AnimatedSwitcher` em textos/botoes que testes ou usuarios clicam em
  sequencia rapida, porque o widget antigo fica temporariamente na arvore.
- Em listas longas, limitar delays de stagger para nao atrasar a interacao.
- Em telas juridicas sensiveis, motion deve esclarecer estado e hierarquia, nao
  mascarar informacao.
