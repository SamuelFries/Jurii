import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/services/supabase_config.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:jurii/widgets/profile_avatar.dart';

const _avatarPath =
    '/storage/v1/object/public/profile-avatars/'
    '92000000-0000-0000-0000-000000000001/avatar.png';

Widget _app({String? imageUrl}) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: Center(
        child: ProfileAvatar(
          imageUrl: imageUrl,
          initials: 'AS',
          size: 64,
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('URL nula ou em branco mostra as iniciais', (tester) async {
    for (final imageUrl in <String?>[null, '   ']) {
      await tester.pumpWidget(_app(imageUrl: imageUrl));

      expect(find.text('AS'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    }
  });

  testWidgets('URL remota cria NetworkImage com o endereço informado', (
    tester,
  ) async {
    await tester.pumpWidget(_app(imageUrl: _avatarPath));

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<NetworkImage>());
    expect(
      (image.image as NetworkImage).url,
      '${SupabaseConfig.url}$_avatarPath',
    );
  });

  testWidgets('host externo sem caminho do bucket cai para as iniciais', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(imageUrl: 'https://tracker.example/avatar.png'),
    );

    expect(find.text('AS'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('host legado é trocado pelo Supabase configurado', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(imageUrl: 'https://tracker.example$_avatarPath'),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as NetworkImage).url,
      '${SupabaseConfig.url}$_avatarPath',
    );
  });
}
