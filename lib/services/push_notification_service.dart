import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../repositories/push_token_repository.dart';

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
  });

  final PushTokenRepository _repository;

  StreamSubscription<String>? _tokenRefreshSub;
  String? _currentToken;

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

    try {
      final messaging = FirebaseMessaging.instance;
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
      _currentToken = null;
    }
  }
}
