import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jurii/theme/app_theme.dart';
import 'package:jurii/theme/theme_controller.dart';
import 'package:jurii/widgets/theme_mode_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    // Volta o singleton ao default para não vazar estado entre testes.
    SharedPreferences.setMockInitialValues({});
    await ThemeController.instance.setMode(ThemeMode.system);
  });

  test('sem preferência salva, load mantém o modo system', () async {
    await ThemeController.instance.load();
    expect(ThemeController.instance.mode, ThemeMode.system);
  });

  test('setMode persiste e load restaura a escolha', () async {
    await ThemeController.instance.setMode(ThemeMode.dark);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('jurii.theme_mode'), 'dark');

    // Simula novo boot: volta ao default e restaura do storage.
    ThemeController.instance.value = ThemeMode.system;
    await ThemeController.instance.load();
    expect(ThemeController.instance.mode, ThemeMode.dark);
  });

  test('valor corrompido no storage cai para system', () async {
    SharedPreferences.setMockInitialValues({'jurii.theme_mode': 'roxo'});
    ThemeController.instance.value = ThemeMode.light;
    await ThemeController.instance.load();
    expect(ThemeController.instance.mode, ThemeMode.system);
  });

  testWidgets('sheet de aparência troca o tema ao tocar em Escuro', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showThemeModeSheet(context),
                child: const Text('Aparência'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Aparência'));
    await tester.pumpAndSettle();

    expect(find.text('Automático'), findsOneWidget);
    expect(find.text('Claro'), findsOneWidget);

    await tester.tap(find.text('Escuro'));
    await tester.pumpAndSettle();

    expect(ThemeController.instance.mode, ThemeMode.dark);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('jurii.theme_mode'), 'dark');
  });

  testWidgets('telas constroem no tema escuro sem erros de extension', (
    tester,
  ) async {
    // Sanity: a AppColors.dark resolve via context.jColors num app dark.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: Text(
                'dark ok',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('dark ok'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
