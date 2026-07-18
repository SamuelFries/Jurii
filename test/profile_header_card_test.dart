import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:jurii/widgets/profile_header_card.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('sem avatarUrl mostra as iniciais e nenhuma imagem', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const ProfileHeaderCard(
          name: 'Ana Souza',
          email: 'ana@jurii.dev',
          initials: 'AS',
          memberSince: 'Cliente desde 2026',
        ),
      ),
    );

    expect(find.text('AS'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('com avatarUrl renderiza uma imagem', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const ProfileHeaderCard(
          name: 'Ana Souza',
          email: 'ana@jurii.dev',
          initials: 'AS',
          memberSince: 'Perfil profissional',
          avatarUrl: 'https://example.com/avatar.jpg',
        ),
      ),
    );

    // Antes do erro de rede (offline no teste), a Image está na árvore.
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('lápis expõe acessibilidade e dispara edição', (tester) async {
    var editCount = 0;

    await tester.pumpWidget(
      _wrap(
        ProfileHeaderCard(
          name: 'Ana Souza',
          email: 'ana@jurii.dev',
          initials: 'AS',
          memberSince: 'Cliente desde 2026',
          onEditTap: () => editCount++,
        ),
      ),
    );

    final editButton = find.byKey(const Key('profile_edit_button'));
    expect(editButton, findsOneWidget);
    expect(find.byTooltip('Editar perfil'), findsOneWidget);

    await tester.tap(editButton);

    expect(editCount, 1);
  });
}
