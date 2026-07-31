import 'package:flutter/widgets.dart';

/// Navegador global do app.
///
/// Existe por causa do push: quando o usuário toca numa notificação com o app
/// em segundo plano (ou fechado), não há `BuildContext` de tela nenhuma para
/// navegar. O sino continua usando o contexto local dele; esta chave é o
/// caminho para quem chega de fora da árvore de widgets.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// O app está numa tela onde faz sentido empilhar um destino?
///
/// Falso durante o boot, na tela de login, na recuperação de senha e no portão
/// de completar cadastro (que é BLOQUEANTE de propósito: nada do app abre antes
/// de nome e CPF existirem). Sem isso, tocar num push abriria a conversa por
/// cima desse portão, contornando a regra.
///
/// Quando falso, o toque não navega e a notificação fica NÃO LIDA — ela
/// continua no sino, que é onde a pessoa a encontra depois.
final ValueNotifier<bool> appCanRouteNotifications = ValueNotifier<bool>(false);
