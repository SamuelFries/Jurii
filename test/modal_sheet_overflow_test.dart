import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/jurii_notification.dart';
import 'package:jurii/repositories/notification_repository.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:jurii/widgets/jurii_form_motion.dart';
import 'package:jurii/widgets/notification_bell.dart';

/// O DEFEITO QUE ISTO TRAVA: o painel de notificações estourava por 113px num
/// iPhone comum com a lista cheia. A conta era `altura da tela * 0.55` para a
/// lista, dentro de uma folha que só tem 56,25% da tela (o teto de 9/16 do
/// showModalBottomSheet): sobravam 11px para cabeçalho, alça e SafeArea, que
/// precisam de ~130px.
///
/// A raiz não era o número: era o JuriiModalSheetScaffold passar altura
/// ILIMITADA para o filho, o que obriga quem está dentro a adivinhar uma
/// fração da tela em vez de usar o espaço que existe. Dez outras folhas usam
/// o mesmo scaffold e tinham o mesmo defeito latente.
///
/// Estes testes rodam em tamanhos de aparelho REAIS e com fonte de verdade,
/// porque a fonte padrão do flutter_test desenha cada glifo como um quadrado
/// de fontSize e mede tudo errado.

class _FakeNotificationRepository implements NotificationRepository {
  _FakeNotificationRepository(this.items);

  final List<JuriiNotification> items;

  @override
  Future<List<JuriiNotification>> fetchLatest({
    required NotificationScope scope,
    String? lawFirmId,
    int limit = 20,
  }) async => items;

  @override
  Future<int> fetchUnreadCount({
    required NotificationScope scope,
    String? lawFirmId,
  }) async => items.where((item) => item.isUnread).length;

  @override
  Future<void> markAsRead(String notificationId) async {}

  @override
  Future<void> markAllAsRead({
    required NotificationScope scope,
    String? lawFirmId,
  }) async {}

  @override
  Future<void> deleteNotification(String notificationId) async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<JuriiNotification> _notificacoes(int quantidade) =>
    List<JuriiNotification>.generate(
      quantidade,
      (index) => JuriiNotification(
        id: 'n$index',
        scope: NotificationScope.client,
        title: 'Notificação número $index',
        body: 'Corpo da notificação $index com um texto de tamanho realista.',
        type: 'message',
        createdAt: DateTime(2026, 8, 9, 10),
        readAt: index < 3 ? null : DateTime(2026, 8, 9, 11),
      ),
    );

/// Aparelhos reais, do menor em uso ao maior.
const _aparelhos = <String, Size>{
  'iPhone SE': Size(375, 667),
  'iPhone 14': Size(390, 844),
  'Pixel 7': Size(412, 915),
};

void main() {
  setUpAll(() async {
    final arquivo = File('/Library/Fonts/Arial Unicode.ttf');
    if (!arquivo.existsSync()) return;
    await (FontLoader('Medida')..addFont(
      Future.value(arquivo.readAsBytesSync().buffer.asByteData()),
    )).load();
  });

  Future<void> abrirPainel(
    WidgetTester tester, {
    required Size tamanho,
    required int quantidade,
    double escalaDeTexto = 1.0,
  }) async {
    tester.view.physicalSize = tamanho;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final base = AppTheme.lightTheme;
    await tester.pumpWidget(
      MaterialApp(
        theme: base.copyWith(
          textTheme: base.textTheme.apply(fontFamily: 'Medida'),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(escalaDeTexto)),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: NotificationBell(
              scope: NotificationScope.client,
              repository: _FakeNotificationRepository(
                _notificacoes(quantidade),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(NotificationBell));
    await tester.pumpAndSettle();
  }

  for (final aparelho in _aparelhos.entries) {
    testWidgets('painel cheio cabe no ${aparelho.key}', (tester) async {
      // Overflow vira exceção no ambiente de teste, então chegar ao fim com o
      // painel aberto já é a prova. A checagem do título garante que o painel
      // abriu de verdade e o teste não passou por não ter renderizado nada.
      await abrirPainel(tester, tamanho: aparelho.value, quantidade: 12);
      expect(find.text('Notificações'), findsOneWidget);
    });
  }

  testWidgets('painel cheio cabe com fonte grande de acessibilidade', (
    tester,
  ) async {
    // Quem aumenta a fonte do sistema é justamente quem mais precisa que a
    // tela não corte conteúdo.
    await abrirPainel(
      tester,
      tamanho: const Size(390, 844),
      quantidade: 12,
      escalaDeTexto: 1.3,
    );
    expect(find.text('Notificações'), findsOneWidget);
  });

  testWidgets('painel com poucas notificações não estica a folha', (
    tester,
  ) async {
    // Flexible é FROUXO de propósito: com duas notificações a folha encolhe
    // em vez de virar um painel alto e vazio. Se algum dia virar Expanded,
    // a folha passa a ocupar o teto sempre e este teste avisa.
    await abrirPainel(tester, tamanho: const Size(390, 844), quantidade: 2);

    // Teto do showModalBottomSheet sem isScrollControlled: 9/16 da tela.
    const teto = 844 * 9 / 16;
    final altura = tester.getSize(find.byType(JuriiModalSheetScaffold)).height;

    expect(
      altura,
      lessThan(teto),
      reason:
          'com 2 notificações a folha encostou no teto de ${teto.round()}px: '
          'virou painel alto e vazio',
    );
  });
}
