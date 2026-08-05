import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/lawyer_profile_summary.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:jurii/widgets/lawyer_profile_card.dart';
import 'package:jurii/widgets/office_card.dart';

LawyerProfileSummary _lawyer({bool isFeatured = false}) {
  return LawyerProfileSummary(
    id: 'l1',
    name: 'Ana Advogada',
    initials: 'AA',
    oabNumber: '123456',
    oabState: 'SP',
    primaryArea: 'Direito Trabalhista',
    practiceAreas: const ['Direito Trabalhista'],
    bio: '',
    rating: 4.5,
    reviews: 3,
    avatarType: 'navy',
    isFeatured: isFeatured,
  );
}

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(body: child),
  );
}

void main() {
  test('isFeatured tem default false (mocks const seguem válidos)', () {
    expect(_lawyer().isFeatured, isFalse);
    const firmDefault = OfficeCard(
      initials: 'FU',
      officeName: 'Firm Um',
      rating: 4.0,
      distance: '1 km',
      specialty: 'Direito Civil',
      reviews: 2,
      avatarType: 'blue',
    );
    expect(firmDefault.isFeatured, isFalse);
  });

  testWidgets('card de advogado destacado mostra o selo', (tester) async {
    await tester.pumpWidget(
      _wrap(LawyerProfileCard(lawyer: _lawyer(isFeatured: true))),
    );
    expect(find.text('Patrocinado'), findsOneWidget);
  });

  testWidgets('card de advogado comum não mostra selo', (tester) async {
    await tester.pumpWidget(_wrap(LawyerProfileCard(lawyer: _lawyer())));
    expect(find.text('Patrocinado'), findsNothing);
  });

  testWidgets('card de escritório destacado mostra o selo', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const OfficeCard(
          initials: 'FD',
          officeName: 'Firm Dois',
          rating: 3.0,
          distance: '2 km',
          specialty: 'Direito Civil',
          reviews: 1,
          avatarType: 'blue',
          isFeatured: true,
        ),
      ),
    );
    expect(find.text('Patrocinado'), findsOneWidget);
  });

  testWidgets('nome longo + selo não estoura o layout', (tester) async {
    await tester.pumpWidget(
      _wrap(
        LawyerProfileCard(
          lawyer: LawyerProfileSummary(
            id: 'l2',
            name:
                'Advogado Com Nome Extremamente Comprido '
                'Que Precisa De Reticências Para Caber',
            initials: 'AC',
            oabNumber: '999999',
            oabState: 'SP',
            primaryArea: 'Direito Trabalhista',
            practiceAreas: const ['Direito Trabalhista'],
            bio: '',
            rating: 5.0,
            reviews: 10,
            avatarType: 'navy',
            isFeatured: true,
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Patrocinado'), findsOneWidget);
  });
}
