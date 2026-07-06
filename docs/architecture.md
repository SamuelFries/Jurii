# Arquitetura do app Jurii

## Camadas

```
lib/
├── main.dart            # raiz: sessão, modos (cliente/advogado/escritório), navegação por abas
├── screens/             # telas (uma por arquivo)
├── widgets/             # componentes reutilizáveis
├── models/              # entidades imutáveis (const constructors, copyWith)
├── repositories/        # acesso a Supabase (tabelas + RPCs); UI nunca fala SQL
├── services/            # infraestrutura (SupabaseConfig, IntakeAIService)
├── data/                # dados estáticos reais (áreas, UFs, catálogo de documentos)
│   └── mock/            # dados fake para modo demo/pitch
├── theme/               # AppTheme, AppColors (ThemeExtension), ThemeController
└── utils/               # helpers puros (validators)
```

Convenções:

- **Repositories** encapsulam Supabase; telas recebem repositórios por
  parâmetro com default `const` (testável por injeção).
- **Models** imutáveis, `fromJson/rows` nos repositórios ou no model.
- **Mocks** só aparecem quando `!SupabaseConfig.isReady` (modo demo, sem
  Supabase configurado) ou usuário deslogado. Os mocks do pitch (commit
  `3f5a249`) foram removidos após a apresentação: a home do advogado
  ("Hoje", casos prioritários) e a equipe do escritório agora usam apenas
  dados reais, com empty states quando não há dados. Métricas por membro
  (casos ativos, tempo de resposta, avaliação) ainda não existem no banco —
  o repositório envia 0 e a UI oculta os badges até a feature existir.
- Textos de UI em PT-BR; erros técnicos vão para `debugPrint`, nunca para o
  usuário.

## Estado / navegação

Sem gerenciador de estado externo (decisão consciente para o estágio atual):
`_JuriiAppState` guarda a sessão e decide entre Login, Recovery, Cliente
(`MainNavigation`), Advogado (`LawyerNavigation`) e Escritório
(`FirmNavigation`). Cada navegação usa bottom nav própria.

Melhoria conhecida (não aplicada): as abas recriam as telas a cada troca
(`pages[currentIndex]` sem `IndexedStack`) — a busca da home se perde ao trocar
de aba. Trocar por `IndexedStack` exige repensar o refresh implícito de
Meus Casos, que hoje depende da recriação. Decisão de UX pendente.

## Tema e dark mode

- `AppColors` (`lib/theme/app_colors.dart`) é a fonte semântica de cores como
  `ThemeExtension`, com paletas `light` (idêntica às constantes históricas) e
  `dark` (navy profundo + dourado, identidade preservada).
- `AppTheme.lightTheme`/`darkTheme` registram a extension e todos os component
  themes (inputs com estados de erro, dialogs/sheets sem tint M3, snackbar,
  botões).
- `ThemeController` (ValueNotifier) já alimenta `themeMode` no MaterialApp.

**Estado atual:** o app permanece em `ThemeMode.light` porque as telas ainda
usam as constantes estáticas `AppTheme.*` (765 referências em 45 arquivos),
que não reagem ao tema.

**Receita da migração (mecânica, tela a tela):**

1. No `build`, trocar `AppTheme.token` por `context.jColors.token`
   (import `../theme/app_colors.dart`); remover `const` dos widgets afetados.
2. Rodar `flutter analyze` — os valores light são idênticos, zero mudança
   visual no tema claro.
3. Ao terminar todas as telas: default do `ThemeController` → `system`,
   expor toggle no perfil e persistir com `shared_preferences`.

## Busca inteligente

Duas camadas equivalentes:

- **Servidor**: `legal_search_intents` + `infer_legal_search_areas` +
  RPCs `fetch_recommended_lawyers/law_firms` (patch_029) — termo leigo
  ("marido me bateu", "golpe do pix") → área do direito, com pesos.
- **Local**: `lib/data/legal_practice_areas.dart` espelha as regras para
  fallback offline, chips e testes.

O casamento de termos respeita **limites de palavra** (`_searchIntentTermMatches`
+ `_containsAtWordBoundary`): termos-sigla curtos não casam dentro de outra
palavra (antes `iss` casava em "dem**iss**ao" → falso Tributário). As áreas são
**ranqueadas por força** (`scorePracticeAreasForSearch` conta quantos termos
bateram) — a que tem mais sinais fica em primeiro. A triagem da IA usa esse
score para descartar áreas secundárias fracas e exibir confiança real.

Ao adicionar termos, atualizar **os dois** (patch novo + arquivo local) e evitar
palavras curtas ambíguas (ex.: `das` foi removido por colidir com a contração).

## Testes

`flutter test` — suíte em `test/`: fluxo de cadastro/verificação/chat
(widget_test.dart, que também cobre precisão/ranqueamento da inferência),
validadores (validators_test.dart) e triagem IA (intake_ai_service_test.dart).

Para sentir a triagem na prática (o que os testes não capturam):
`dart run tool/intake_playground.dart` — conversa com a IA no terminal (Dart
puro, sem Flutter/Supabase) e imprime o resumo + a overview do advogado.
