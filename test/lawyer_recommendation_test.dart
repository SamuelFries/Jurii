import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/chat_message.dart';
import 'package:jurii/models/lawyer_profile_summary.dart';
import 'package:jurii/models/lawyer_recommendation.dart';
import 'package:jurii/repositories/lawyer_profile_repository.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:jurii/widgets/lawyer_recommendation_card.dart';
import 'package:jurii/widgets/recommend_lawyer_sheet.dart';

class _FakeLawyerProfileRepository extends LawyerProfileRepository {
  const _FakeLawyerProfileRepository({required this.lawyers});

  final List<LawyerProfileSummary> lawyers;

  @override
  Future<List<LawyerProfileSummary>> fetchLawFirmLawyers(
    String lawFirmId,
  ) async => lawyers;
}

const _laura = LawyerProfileSummary(
  id: 'lawyer-1',
  name: 'Laura Advogada',
  initials: 'LA',
  oabNumber: '123456',
  oabState: 'SP',
  primaryArea: 'Direito Trabalhista',
  practiceAreas: ['Direito Trabalhista'],
  bio: '',
  rating: 0,
  reviews: 0,
  avatarType: 'navy',
);

const _recommendation = LawyerRecommendation(
  lawyerId: 'lawyer-1',
  name: 'Laura Advogada',
  initials: 'LA',
  oabLabel: 'OAB/SP 123456',
  primaryArea: 'Direito Trabalhista',
);

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  group('LawyerRecommendation.fromMetadata', () {
    test('parseia a metadata da mensagem', () {
      final recommendation = LawyerRecommendation.fromMetadata({
        'type': 'lawyer_recommendation',
        'lawyer_id': 'lawyer-1',
        'lawyer_name': 'Laura Advogada',
        'lawyer_initials': 'LA',
        'oab_label': 'OAB/SP 123456',
        'primary_area': 'Direito Trabalhista',
        'avatar_url': 'https://cdn.jurii.test/laura.png',
      });

      expect(recommendation, isNotNull);
      expect(recommendation!.lawyerId, 'lawyer-1');
      expect(recommendation.name, 'Laura Advogada');
      expect(recommendation.oabLabel, 'OAB/SP 123456');
      expect(recommendation.photoUrl, 'https://cdn.jurii.test/laura.png');
    });

    test('sem foto e sem iniciais, deriva iniciais do nome', () {
      final recommendation = LawyerRecommendation.fromMetadata({
        'type': 'lawyer_recommendation',
        'lawyer_id': 'lawyer-1',
        'lawyer_name': 'Bruno Advogado',
        'lawyer_initials': '  ',
      });

      expect(recommendation!.initials, 'BA');
      expect(recommendation.photoUrl, isNull);
    });

    test('outro tipo de mensagem não vira sugestão', () {
      expect(
        LawyerRecommendation.fromMetadata({
          'type': 'case_request',
          'case_request_id': 'req-1',
        }),
        isNull,
      );
    });

    test('sem lawyer_id não vira sugestão (card não teria o que abrir)', () {
      expect(
        LawyerRecommendation.fromMetadata({
          'type': 'lawyer_recommendation',
          'lawyer_name': 'Laura Advogada',
        }),
        isNull,
      );
    });
  });

  test(
    'ChatMessage expõe a sugestão sem confundir com solicitação de caso',
    () {
      const message = ChatMessage(
        id: 'm1',
        conversationKey: 'c1',
        author: MessageAuthor.system,
        text: 'Advogado sugerido: Laura Advogada',
        time: '10:00',
        metadata: {
          'type': 'lawyer_recommendation',
          'lawyer_id': 'lawyer-1',
          'lawyer_name': 'Laura Advogada',
          'oab_label': 'OAB/SP 123456',
        },
      );

      expect(message.lawyerRecommendation?.lawyerId, 'lawyer-1');
      expect(message.isCaseRequest, isFalse);
    },
  );

  testWidgets('cliente vê o perfil do advogado e o botão de mensagem', (
    tester,
  ) async {
    var tapped = 0;

    await tester.pumpWidget(
      _wrap(
        LawyerRecommendationCard(
          recommendation: _recommendation,
          time: '10:00',
          canMessage: true,
          onMessage: () => tapped++,
        ),
      ),
    );

    expect(find.text('Sugestão do escritório'), findsOneWidget);
    expect(find.text('Laura Advogada'), findsOneWidget);
    expect(find.text('OAB/SP 123456'), findsOneWidget);
    expect(find.text('Direito Trabalhista'), findsOneWidget);
    expect(find.text('LA'), findsOneWidget);

    await tester.tap(find.text('Enviar mensagem'));
    expect(tapped, 1);
  });

  testWidgets('do lado do escritório o card não tem botão de mensagem', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const LawyerRecommendationCard(
          recommendation: _recommendation,
          time: '10:00',
        ),
      ),
    );

    expect(find.text('Laura Advogada'), findsOneWidget);
    expect(find.text('Enviar mensagem'), findsNothing);
  });

  testWidgets('folha lista os advogados e devolve o escolhido', (tester) async {
    String? picked;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  picked = await showRecommendLawyerSheet(
                    context,
                    lawFirmId: 'firm-1',
                    repository: const _FakeLawyerProfileRepository(
                      lawyers: [_laura],
                    ),
                  );
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Laura Advogada'), findsOneWidget);
    expect(find.text('OAB/SP 123456 · Direito Trabalhista'), findsOneWidget);

    // Sem escolher ninguém, o envio fica travado.
    await tester.tap(find.text('Enviar sugestão'));
    await tester.pumpAndSettle();
    expect(picked, isNull);
    expect(find.text('Laura Advogada'), findsOneWidget);

    await tester.tap(find.text('Laura Advogada'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar sugestão'));
    await tester.pumpAndSettle();

    expect(picked, 'lawyer-1');
  });

  testWidgets('escritório sem advogados aprovados vê o estado vazio', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const SizedBox(
          height: 600,
          child: RecommendLawyerSheet(
            lawFirmId: 'firm-1',
            repository: _FakeLawyerProfileRepository(lawyers: []),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nenhum advogado para sugerir'), findsOneWidget);
    expect(find.text('Enviar sugestão'), findsNothing);
  });
}
