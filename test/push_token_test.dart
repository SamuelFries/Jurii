import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/repositories/push_token_repository.dart';

void main() {
  group('PushPlatform', () {
    test('valores batem com o CHECK do banco (ios/android/web)', () {
      expect(PushPlatform.ios.value, 'ios');
      expect(PushPlatform.android.value, 'android');
      expect(PushPlatform.web.value, 'web');
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
