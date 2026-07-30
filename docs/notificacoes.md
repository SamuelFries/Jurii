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
| `case_update` | client | cliente | `ingest_case_movements` (andamento processual, já coalescido) |

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
- **Tocar abre a conversa de origem** quando a notificação tem
  `metadata.conversation_id` (solicitação de caso, resposta, indicação). A
  notificação é marcada como lida no mesmo gesto.
  - O escopo **firm** não roteia: o painel do escritório abre o chat com
    limites próprios (não propõe caso, não mostra triagem) e rotear daqui com
    os padrões do `ChatScreen` reintroduziria os dois.
  - Tipos sem conversa (`case_update`, `appointment_reminder`,
    `lawyer_recommended`) só marcam como lida. Deep-link para caso e agenda
    fica para quando houver rota nomeada.
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
- Tocar no push abre o app, mas ainda **não navega** para o destino (exige
  rota nomeada + navigator global; feature separada).
- Com o app aberto, o push não aparece na bandeja (comportamento do Android);
  o sino em tempo real já cobre esse caso. Exibir em foreground exigiria
  `flutter_local_notifications`.

## Retenção

Job diário `purge-old-notifications` (pg_cron, 04:23) apaga **apenas**
notificações **já lidas** há mais de 90 dias. Não lida nunca é apagada.
Antes disso a tabela crescia para sempre (o único delete era o swipe).

Para mudar a janela: `select public.purge_old_notifications(interval '30 days');`
