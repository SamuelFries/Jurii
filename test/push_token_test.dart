import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/repositories/push_token_repository.dart';

void main() {
  group('PushPlatform', () {
    test('valores batem com o CHECK do banco (ios/android/web)', () {
      expect(PushPlatform.ios.value, 'ios');
      expect(PushPlatform.android.value, 'android');
      expect(PushPlatform.web.value, 'web');
    });

    test('web não registra push', () {
      // kIsWeb é const false num teste de VM, então o ramo web é podado antes
      // de rodar — não dá para exercitá-lo. Sobra travar a fonte: sem o
      // firebase-messaging-sw.js em web/, registrar no navegador só produz
      // failed-service-worker-registration a cada boot.
      final fonte = File(
        'lib/services/push_notification_service.dart',
      ).readAsStringSync();
      expect(fonte.contains('if (kIsWeb) return null;'), isTrue);
      expect(fonte.contains('return PushPlatform.web'), isFalse);
    });
  });

  group('PushTokenRepository sem Supabase (modo demo/teste)', () {
    const repo = PushTokenRepository();

    test('register é no-op e não lança', () async {
      await expectLater(
        repo.register(token: 'abc', platform: PushPlatform.android),
        completes,
      );
    });

    test('unregister é no-op e não lança', () async {
      await expectLater(repo.unregister('abc'), completes);
    });
  });
}
