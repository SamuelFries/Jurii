# Convite por link (secretária e estagiário)

Advogado entra na equipe pela OAB (`invite_verified_lawyer_to_law_firm`).
Secretária e estagiário, que não têm OAB, entram por **link de uso único**:
o gestor gera, a pessoa abre e PEDE para entrar, e um dono/admin aprova ou
recusa na Equipe. O link nunca concede sozinho.

Backend (em produção): `20260912120000_convite_por_link.sql` e
`20260914120000_o_link_pede_em_vez_de_conceder.sql`. O app e o webapp
consomem exatamente as mesmas RPCs; não há segundo fluxo.

## O link

Canônico: `https://app.jurii.com.br/convite/<token>` (token: 48 hex).
Também aceito pelo app: `jurii://convite/<token>`.

`lib/utils/invite_link.dart` é a fonte única de montar e ler o link
(`buildInviteLink`, `inviteTokenFromUri`). O token só existe no momento em
que o link nasce: o servidor guarda o hash. Fechou a folha sem copiar,
gera outro (o antigo fica na lista de abertos, para cancelar).

## Como o app recebe o link

`InviteLinkService` (`lib/services/invite_link_service.dart`), ligado em
`main.dart`:

- `getInitialLink` (o link ABRIU o app) e `uriLinkStream` (chegou com o app
  vivo) caem no mesmo lugar.
- O token fica em `tokenPendente` e a navegação espera
  `appCanRouteNotifications` (o mesmo portão do push): nem no boot, nem no
  login, nem no portão de completar cadastro. Quando o app fica utilizável,
  a `InviteLinkScreen` abre sozinha com o token intacto. É assim que quem
  não tem conta cria a conta e cai de volta no convite.
- A tela de login mostra "X convidou você..." enquanto há token pendente
  (`ConviteAguardandoAviso`), para a pessoa não achar que o link se perdeu.
- O mesmo token duas vezes (Android entrega initial e stream) abre uma
  tela só.

## Telas

- `InviteLinkScreen` (quem recebeu): espia (`espiar_link_de_convite`, roda
  sem sessão) e mostra um estado por vez: válido (nome, iniciais, papel
  FIXO, "Pedir para entrar"), inexistente, expirado, revogado, usado,
  meu pedido pendente / aprovado / recusado / expirado. Papel não se edita.
- Equipe (`FirmTeamScreen`): o botão de convidar abre DUAS portas
  (advogado por OAB; secretária/estagiário por link). `InviteByLinkSheet`
  escolhe o papel, gera, mostra o link com Copiar e Compartilhar (folha
  nativa, `share_plus`). `FirmJoinRequestsSection` lista pedidos
  pendentes (nome, e-mail, CPF confirmado, Aprovar/Recusar) e links
  abertos (Cancelar); some quando não há nada.
- Notificações: `firm_join_requested` abre `JoinRequestsScreen`;
  `firm_join_decided` aprovado entra na banca (ver docs/notificacoes.md).

## Sem App Link configurado, nada quebra

O link abre no navegador e o webapp resolve (`/convite/[token]` é rota
pública lá). O App Link (Android) e o Universal Link (iOS) só fazem o
mesmo link abrir o app direto quando ele está instalado.

### Android (App Link)

- `AndroidManifest.xml`: intent-filter `https://app.jurii.com.br/convite/*`
  com `autoVerify="true"`, mais `jurii://convite`.
- O Android confere `https://app.jurii.com.br/.well-known/assetlinks.json`
  (repo jurii-webapp, `public/.well-known/`). O arquivo está com um
  marcador no lugar do SHA-256. **Falta o SHA-256 do certificado que
  assina o app de release**: com Play App Signing, é o da chave de
  assinatura do app em Play Console > Configuração > Integridade do app
  (vale listar também o da chave de upload); fora do Play,
  `keytool -list -v -keystore <keystore.jks> -alias <alias>`, linha
  SHA256, formato `AA:BB:...`. Debug builds têm outro certificado: para
  testar em debug, acrescentar o SHA-256 do `~/.android/debug.keystore`
  (senha `android`, alias `androiddebugkey`).
- Conferir no aparelho: `adb shell pm get-app-links br.com.jurii.app`
  deve mostrar `app.jurii.com.br: verified`.

### iOS (Universal Link)

- `ios/Runner/Runner.entitlements` está preparado com
  `applinks:app.jurii.com.br`, mas NÃO ligado ao projeto Xcode de
  propósito: com a entitlement ligada, um build assinado por conta sem a
  capability Associated Domains (conta gratuita) deixa de instalar.
- Depende de: conta Apple Developer paga; App ID `br.com.jurii.app` com
  Associated Domains; em Xcode, Runner > Signing & Capabilities > + Associated
  Domains > `applinks:app.jurii.com.br` (o Xcode liga a entitlement);
  `apple-app-site-association` no jurii-webapp com o Team ID real no lugar
  do marcador.
