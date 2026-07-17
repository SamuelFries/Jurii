import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/repositories/calendar_feed_repository.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:jurii/widgets/calendar_sync_sheet.dart';

class _FakeCalendarFeedRepository extends CalendarFeedRepository {
  _FakeCalendarFeedRepository({this.token});

  String? token;
  int enableCalls = 0;
  int resetCalls = 0;
  int disableCalls = 0;

  @override
  Future<String?> fetchToken() async => token;

  @override
  Future<String> enable() async {
    enableCalls++;
    token = 'tok-123';
    return token!;
  }

  @override
  Future<String> reset() async {
    resetCalls++;
    token = 'tok-new';
    return token!;
  }

  @override
  Future<void> disable() async {
    disableCalls++;
    token = null;
  }
}

Widget _host(CalendarFeedRepository repo) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showCalendarSyncSheet(context, repository: repo),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('CalendarFeedRepository URLs', () {
    const repo = CalendarFeedRepository();

    test('feedUrl aponta para a função com o token', () {
      final url = repo.feedUrl('abc');
      expect(url, contains('/functions/v1/calendar-feed?token=abc'));
      expect(url, startsWith('https://'));
    });

    test('webcalUrl troca o esquema para webcal://', () {
      final url = repo.webcalUrl('abc');
      expect(url, startsWith('webcal://'));
      expect(url, contains('/functions/v1/calendar-feed?token=abc'));
    });
  });

  testWidgets('feed desativado mostra Ativar e liga ao tocar', (tester) async {
    final repo = _FakeCalendarFeedRepository(token: null);
    await tester.pumpWidget(_host(repo));

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Ativar sincronização'), findsOneWidget);

    await tester.tap(find.text('Ativar sincronização'));
    await tester.pumpAndSettle();

    expect(repo.enableCalls, 1);
    // Depois de ativar, a URL com o token aparece.
    expect(find.textContaining('token=tok-123'), findsOneWidget);
    expect(find.text('Abrir no meu calendário'), findsOneWidget);
  });

  testWidgets('feed ativado mostra o link e as ações de revogar', (
    tester,
  ) async {
    final repo = _FakeCalendarFeedRepository(token: 'tok-abc');
    await tester.pumpWidget(_host(repo));

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.textContaining('token=tok-abc'), findsOneWidget);
    expect(find.text('Gerar novo link'), findsOneWidget);
    expect(find.text('Desativar'), findsOneWidget);

    await tester.tap(find.text('Gerar novo link'));
    await tester.pumpAndSettle();

    expect(repo.resetCalls, 1);
    expect(find.textContaining('token=tok-new'), findsOneWidget);
  });
}
