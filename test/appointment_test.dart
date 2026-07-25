import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/appointment.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:jurii/widgets/appointment_form_sheet.dart';

Appointment _appointment({DateTime? startsAt, DateTime? endsAt}) {
  return Appointment(
    id: 'a1',
    role: AppointmentRole.lawyer,
    title: 'Audiência trabalhista',
    counterpartName: 'Ana Pereira',
    area: 'Trabalhista',
    dateLabel: 'Hoje',
    timeLabel: '14:00',
    location: 'Fórum',
    status: AppointmentStatus.confirmed,
    startsAt: startsAt,
    endsAt: endsAt,
  );
}

Widget _host(
  void Function(AppointmentDraft?) onResult, {
  Appointment? existing,
  DateTime Function()? nowProvider,
}) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              onResult(
                await showAppointmentFormSheet(
                  context,
                  existing: existing,
                  nowProvider: nowProvider,
                ),
              );
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('Appointment.isEditable', () {
    test('editável só com horários reais (linha do backend)', () {
      final now = DateTime.now();
      expect(
        _appointment(
          startsAt: now,
          endsAt: now.add(const Duration(hours: 1)),
        ).isEditable,
        isTrue,
      );
    });

    test('mock sem horários não é editável', () {
      expect(_appointment().isEditable, isFalse);
    });
  });

  testWidgets('título vazio bloqueia a criação', (tester) async {
    AppointmentDraft? result;
    var called = false;

    await tester.pumpWidget(
      _host((r) {
        result = r;
        called = true;
      }),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Criar compromisso'));
    await tester.pumpAndSettle();

    expect(find.text('Informe um título'), findsOneWidget);
    // A folha continua aberta; nada foi devolvido.
    expect(called, isFalse);
    expect(result, isNull);
  });

  testWidgets('com título válido devolve o rascunho', (tester) async {
    AppointmentDraft? result;
    final fixedNow = DateTime(2026, 7, 24, 10, 30);

    await tester.pumpWidget(
      _host((r) => result = r, nowProvider: () => fixedNow),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField).first,
      'Audiência trabalhista',
    );
    await tester.tap(find.text('Criar compromisso'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.title, 'Audiência trabalhista');
    // Default: fim é depois do início.
    expect(result!.endsAt.isAfter(result!.startsAt), isTrue);
  });

  testWidgets('virada do dia mantém uma hora de duração', (tester) async {
    AppointmentDraft? result;
    final fixedNow = DateTime(2026, 7, 24, 22, 50);

    await tester.pumpWidget(
      _host((r) => result = r, nowProvider: () => fixedNow),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.textContaining('(+1 dia)'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'Plantão noturno');
    await tester.tap(find.text('Criar compromisso'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.startsAt, DateTime(2026, 7, 24, 23));
    expect(result!.endsAt, DateTime(2026, 7, 25));
    expect(
      result!.endsAt.difference(result!.startsAt),
      const Duration(hours: 1),
    );
  });

  testWidgets('edição pré-preenche os campos existentes', (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      _host(
        (_) {},
        existing: _appointment(
          startsAt: DateTime(now.year, now.month, now.day, 14),
          endsAt: DateTime(now.year, now.month, now.day, 15),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Editar compromisso'), findsOneWidget);
    expect(find.text('Audiência trabalhista'), findsOneWidget);
    expect(find.text('Ana Pereira'), findsOneWidget);
    expect(find.text('Fórum'), findsOneWidget);
    expect(find.text('Salvar'), findsOneWidget);
  });

  testWidgets('edição preserva término no dia seguinte', (tester) async {
    AppointmentDraft? result;
    final startsAt = DateTime(2026, 7, 24, 23, 30);
    final endsAt = DateTime(2026, 7, 25, 0, 30);

    await tester.pumpWidget(
      _host(
        (value) => result = value,
        existing: _appointment(startsAt: startsAt, endsAt: endsAt),
        nowProvider: () => DateTime(2026, 7, 24, 12),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.textContaining('(+1 dia)'), findsOneWidget);

    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.startsAt, startsAt);
    expect(result!.endsAt, endsAt);
  });
}
