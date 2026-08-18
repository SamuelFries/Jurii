# Notificações

Um só caminho: tudo nasce de uma linha em `public.notifications`, inserida
por função `SECURITY DEFINER` (o app não tem grant de insert). Dessa linha
saem, de graça, o sino em tempo real (a tabela está na publication do
Realtime) e o push (trigger `notifications_push_dispatch` → Edge Function
`send-push`).

## Tipos vivos e quem recebe

| Tipo | Escopo | Destinatário | Origem |
|---|---|---|---|
| `team_invite` | lawyer | advogado convidado | `invite_verified_lawyer_to_law_firm` |
| `case_request` | client | cliente | trigger de `case_requests` (idempotente: 1 linha por solicitação, atualizada depois) |
| `case_request_response` | lawyer | advogado + quem propôs | `respond_to_case_request` |
| `firm_case_started` | firm | gestores ativos do escritório | `respond_to_case_request` (fan-out) |
| `lawyer_recommendation` | client | cliente | `recommend_lawyer_to_client` |
| `lawyer_recommended` | lawyer | advogado indicado | `recommend_lawyer_to_client` |
| `appointment_reminder` | lawyer | advogado | `dispatch_appointment_reminders` (pg_cron, 1x por compromisso) |
| `case_update` | client | cliente | `ingest_case_movements` (andamento processual, já coalescido) e `reopen_legal_case` |
| `case_closed` | client | cliente | `close_legal_case` (convite de avaliação; toque abre o caso) |
| `firm_join_requested` | firm | donos/admins ativos da banca | `solicitar_entrada_por_link` (metadata `join_request_id`; `law_firm_id` preenchido) |
| `firm_join_decided` | client | quem pediu entrada por link | `decidir_entrada_no_escritorio` (sem metadata; título distingue aprovação de recusa) |
| `firm_join_decided_admin` | firm | os outros gestores da banca | `avisa_gestores_da_decisao` (informativa) |

**Armadilha permanente:** o sino filtra por escopo e o escopo é derivado do
TIPO (`infer_notification_scope`). Tipo novo precisa ser declarado lá, numa
migration que reescreva a função inteira — senão a notificação cai no sino
errado e o destinatário nunca a vê.

`message` está declarado na função de escopo e tem ícone no app, mas **nunca
é inserido**: não existe notificação por mensagem de chat. Se um dia existir,
vai precisar de coalescência própria (o trigger de push é `for each row`, sem
throttle: 20 mensagens seriam 20 pushes).

## Comportamento do sino (app)

- **Abrir não marca tudo como lido.** O destaque de não lida é o que ajuda a
  achar o que falta ver. Marca-se ao tocar em cada uma, ou de uma vez pelo
  botão "Marcar todas como lidas" no cabeçalho.
- **Tocar abre o destino** (conversa ou caso) e marca como lida no mesmo
  gesto. A tabela de destinos está em "Toque na notificação", no fim deste
  documento.
- Cada item mostra **quando chegou** (`formatRelativeTime`: "agora",
  "há 5 min", "ontem", "10/07").
- Swipe para a esquerda apaga.

`metadata` tem uma inconsistência histórica de nome para o caso:
`legal_case_id` em `case_request_response`, `case_id` em `firm_case_started`
e `case_update`. O model absorve os dois em `JuriiNotification.caseId`.

## Push

- Trigger central: **toda** linha nova dispara `send-push`. Nenhum tipo
  precisa de código próprio.
- Sem os secrets do Vault o trigger é NO-OP: a notificação é criada
  normalmente, só não sai push.
- **Token morto é removido sozinho**: quando o FCM responde `UNREGISTERED` ou
  `INVALID_ARGUMENT` (app desinstalado, token rotacionado), a função apaga o
  token via `delete_push_token_by_value` (service_role). Sem isso a tabela só
  crescia e toda notificação futura tentava entregar nos tokens mortos.
- `fetch_push_tokens_for_recipient` devolve no máximo os **20 mais recentes**,
  teto defensivo contra fan-out ilimitado por reinstalações.
- Tocar no push **abre o destino** (ver a seção abaixo).
- Com o app aberto, o push não aparece na bandeja (comportamento do Android);
  o sino em tempo real já cobre esse caso. Exibir em foreground exigiria
  `flutter_local_notifications`.

## Retenção

Job diário `purge-old-notifications` (pg_cron, 04:23) apaga **apenas**
notificações **já lidas** há mais de 90 dias. Não lida nunca é apagada.
Antes disso a tabela crescia para sempre (o único delete era o swipe).

Para mudar a janela: `select public.purge_old_notifications(interval '30 days');`

## Toque na notificação (30/07/2026)

Sino e push abrem o mesmo destino, resolvido num lugar só:
`destinationFor()` em `lib/services/notification_router.dart`.

| Notificação | Destino |
|---|---|
| `lawyer_recommendation`, `case_request`, `case_request_response` | a conversa |
| `case_update`, `firm_case_started` | o caso |
| `appointment_reminder`, `lawyer_recommended`, `team_invite` | nenhum (só marca como lida; `team_invite` resolve pelos botões do próprio item) |
| `firm_join_requested` | os pedidos de entrada da banca (`JoinRequestsScreen`, precisa de `law_firm_id` na linha) |
| `firm_join_decided` aprovado (título "Você entrou na equipe") | a área da banca: o roteador chama `NotificationRouter.enterFirmWorkspace`, que a raiz (main.dart) registra para recarregar os vínculos e trocar de área |
| `firm_join_decided` recusado, `firm_join_decided_admin` | nenhum |

**Conversa tem precedência sobre caso**: tipos como `case_request_response`
carregam os dois, e a conversa é onde a pessoa continua o assunto.

**O escopo do escritório nunca abre conversa**: o painel do escritório abre o
chat com limites próprios (não propõe caso, sem triagem) e abrir daqui, com os
padrões do `ChatScreen`, reintroduziria os dois. Sobra o caso, que é neutro.

### Abrir um caso só pelo id

`fetch_case_for_current_user` (migration `20260730180000`) devolve o que a tela
de detalhe precisa. Dois pontos que valem lembrar:

- **Quem decide se pode editar é o servidor** (`can_manage_case_updates`), não
  a tela. As listas passam esse flag por contexto (`lawyer_cases_screen` manda
  `true` fixo); quem chega por notificação não tem contexto nenhum.
- **O gate inclui gestor do escritório**, não só `can_access_case`. O fan-out de
  `firm_case_started` vai para todos os gestores ativos, mas
  `respond_to_case_request` só cria participante para cliente, advogado e quem
  pediu o caso. Sem esse ramo, o sócio que não pediu o caso recebia a
  notificação e o toque não abria nada. Não amplia visibilidade: é o mesmo
  escopo que `fetch_law_firm_cases` já concede.

### Armadilhas que a revisão adversarial pegou (não repetir)

- `Navigator.push` **só completa no pop**. Esperar por ele para marcar a
  notificação como lida deixava a marcação pendurada enquanto a pessoa lia o
  conteúdo. O router empilha sem esperar e devolve "empilhei", não "voltou".
- Marcar como lida **só quando abriu**. Se falhar, a notificação continua
  destacada no sino, que é a única pista que resta.
- O roteamento é ligado **antes** de pedir o token do FCM: quando vinha depois,
  um `getToken()` que falha (iOS sem APNs) matava o toque pela sessão inteira.
- `getInitialMessage` tem trava de **processo**, não de sessão: sem ela, um
  logout seguido de login reabria um toque já tratado.
- `navigator.mounted` **não detecta logout**. O router compara o uid antes e
  depois do await, senão empilharia a conversa do usuário anterior sobre o
  login.
- Roteamento só acontece com o app utilizável (`appCanRouteNotifications`):
  o portão de completar cadastro é bloqueante e um push não pode saltá-lo.
