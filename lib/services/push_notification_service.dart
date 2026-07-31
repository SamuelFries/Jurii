import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../repositories/notification_repository.dart';
import '../repositories/push_token_repository.dart';
import 'app_navigator.dart';
import 'notification_router.dart';

/// Handler de mensagens em background/app fechado. O SO exibe a notificacao
/// (payload `notification`) automaticamente; este handler precisa existir e ser
/// top-level com `vm:entry-point` para o firebase_messaging inicializar no
/// isolate de background.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Nada a fazer por enquanto — a exibicao e do sistema. Ponto de extensao
  // futuro (ex.: badge, dados) fica aqui.
}

/// Liga o app ao FCM: pede permissao, registra o token do dispositivo (via
/// [PushTokenRepository]) e o mantem atualizado. Tudo best-effort — nunca
/// derruba o fluxo de login/logout se o push falhar.
class PushNotificationService {
  PushNotificationService({
    this._repository = const PushTokenRepository(),
    this._notifications = const NotificationRepository(),
    this._router = const NotificationRouter(),
  });

  final PushTokenRepository _repository;
  final NotificationRepository _notifications;
  final NotificationRouter _router;

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _openedAppSub;
  String? _currentToken;

  /// Trava de processo: a mensagem que abriu o app é tratada uma vez só.
  bool _initialMessageChecked = false;

  /// Push so em iOS/Android/web; outras plataformas (macOS, etc.) sao ignoradas.
  static PushPlatform? _platform() {
    if (kIsWeb) return PushPlatform.web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return PushPlatform.ios;
      case TargetPlatform.android:
        return PushPlatform.android;
      default:
        return null;
    }
  }

  /// Chamado apos o login. Pede permissao, pega o token FCM e o registra.
  Future<void> registerForCurrentUser() async {
    final platform = _platform();
    if (platform == null) return;

    final messaging = FirebaseMessaging.instance;

    // ANTES do token, de propósito: rotear o toque não depende de token nem de
    // registro, só da sessão (que já existe aqui). Quando isto vinha depois, um
    // getToken() que falha — o caso comum no iOS sem APNs — matava o
    // roteamento pela sessão inteira.
    _listenToTaps(messaging);

    try {
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }

      final token = await messaging.getToken();
      // Token nulo acontece, por ex., em iOS sem APNs configurada — sem drama,
      // o dispositivo so nao recebe push ate ter o token.
      if (token == null || token.isEmpty) return;

      _currentToken = token;
      await _repository.register(token: token, platform: platform);

      // O FCM rotaciona o token; re-registra quando isso acontecer.
      _tokenRefreshSub ??= messaging.onTokenRefresh.listen((newToken) {
        _currentToken = newToken;
        unawaited(_repository.register(token: newToken, platform: platform));
      });
    } catch (error) {
      debugPrint('Push registration failed: $error');
    }
  }

  /// Toque no push abre o destino (conversa ou caso).
  ///
  /// `getInitialMessage` cobre o app fechado (o toque que ABRIU o app) e
  /// `onMessageOpenedApp` cobre o app em segundo plano.
  void _listenToTaps(FirebaseMessaging messaging) {
    _openedAppSub ??= FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);

    // A mensagem inicial pertence ao PROCESSO, não à sessão: consultar de novo
    // depois de um logout e novo login reabriria um toque já tratado. Por isso
    // a trava não é limpa em disableForCurrentUser.
    if (_initialMessageChecked) return;
    _initialMessageChecked = true;
    unawaited(
      messaging.getInitialMessage().then((message) {
        if (message != null) _handleTap(message);
      }),
    );
  }

  /// O push carrega só `notification_id` — os ids de caso/conversa ficam fora
  /// do payload, que trafega pelo FCM e repousa no aparelho. Buscamos a linha
  /// (protegida por RLS) para descobrir o destino.
  Future<void> _handleTap(RemoteMessage message) async {
    try {
      final notificationId = message.data['notification_id'] as String?;
      if (notificationId == null || notificationId.isEmpty) return;

      // O portão de completar cadastro é bloqueante; navegar por cima dele
      // contornaria a regra. Notificação fica NÃO LIDA e espera no sino.
      if (!appCanRouteNotifications.value) return;

      final notification = await _notifications.fetchById(notificationId);
      if (notification == null) return;

      final navigator = appNavigatorKey.currentState;
      if (navigator == null) return;

      // Marca como lida só se realmente abriu: quando não abre, a notificação
      // continua destacada no sino, que é a única pista que resta ao usuário.
      final opened = await _router.open(navigator, notification);
      if (opened) unawaited(_notifications.markAsRead(notification.id));
    } catch (error) {
      debugPrint('Push tap routing failed: $error');
    }
  }

  /// Chamado no logout (antes do signOut, enquanto ainda autenticado): remove o
  /// token deste dispositivo para o usuario nao receber push apos sair.
  Future<void> disableForCurrentUser() async {
    final token = _currentToken;
    try {
      if (token != null) await _repository.unregister(token);
    } catch (error) {
      debugPrint('Push unregister failed: $error');
    } finally {
      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = null;
      // Sem isto, o toque num push antigo tentaria navegar depois do logout.
      await _openedAppSub?.cancel();
      _openedAppSub = null;
      _currentToken = null;
    }
  }
}
