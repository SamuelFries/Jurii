import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/professional_review.dart';
import 'package:jurii/repositories/review_repository.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:jurii/widgets/reviews_panel.dart';

class _FakeReviewRepository extends ReviewRepository {
  const _FakeReviewRepository({
    required this.reviews,
    required this.eligibility,
  });

  final List<ProfessionalReview> reviews;
  final ReviewEligibility eligibility;

  @override
  Future<List<ProfessionalReview>> fetchReviews({
    required ReviewTarget target,
    required String targetId,
    int limit = 20,
  }) async => reviews;

  @override
  Future<ReviewEligibility> fetchEligibility({
    required ReviewTarget target,
    required String targetId,
  }) async => eligibility;
}

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  group('ProfessionalReview.fromRow', () {
    test('parseia linha completa', () {
      final review = ProfessionalReview.fromRow({
        'id': 'r1',
        'reviewer_name': 'Ana Souza',
        'reviewer_initials': 'AS',
        'rating': 4,
        'comment': 'Atendimento ótimo',
        'created_at': '2026-07-13T10:00:00Z',
        'is_mine': true,
      });
      expect(review.reviewerName, 'Ana Souza');
      expect(review.rating, 4);
      expect(review.comment, 'Atendimento ótimo');
      expect(review.isMine, isTrue);
      expect(review.createdAt, isNotNull);
    });

    test('comentário vazio vira null e usa fallback de nome', () {
      final review = ProfessionalReview.fromRow({
        'id': 'r2',
        'reviewer_name': '  ',
        'reviewer_initials': '',
        'rating': 5,
        'comment': '   ',
        'created_at': null,
        'is_mine': false,
      });
      expect(review.comment, isNull);
      expect(review.reviewerName, 'Cliente Jurii');
      expect(review.reviewerInitials, 'C');
    });
  });

  group('ReviewEligibility.fromRow', () {
    test('sem review anterior', () {
      final e = ReviewEligibility.fromRow({
        'can_review': true,
        'my_rating': null,
        'my_comment': null,
      });
      expect(e.canReview, isTrue);
      expect(e.hasReviewed, isFalse);
    });

    test('com review anterior', () {
      final e = ReviewEligibility.fromRow({
        'can_review': true,
        'my_rating': 3,
        'my_comment': 'ok',
      });
      expect(e.hasReviewed, isTrue);
      expect(e.myRating, 3);
    });
  });

  testWidgets(
    'painel lista reviews e mostra botão de avaliar quando elegível',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ReviewsPanel(
            target: ReviewTarget.lawyer,
            targetId: 'lawyer-1',
            repository: _FakeReviewRepository(
              reviews: [
                ProfessionalReview(
                  id: 'r1',
                  reviewerName: 'Bruno Lima',
                  reviewerInitials: 'BL',
                  rating: 5,
                  comment: 'Excelente advogado',
                  createdAt: null,
                ),
              ],
              eligibility: ReviewEligibility(canReview: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Avaliar profissional'), findsOneWidget);
      expect(find.text('Bruno Lima'), findsOneWidget);
      expect(find.text('Excelente advogado'), findsOneWidget);
    },
  );

  testWidgets('sem elegibilidade e sem reviews mostra estado vazio', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const ReviewsPanel(
          target: ReviewTarget.lawFirm,
          targetId: 'firm-1',
          repository: _FakeReviewRepository(
            reviews: [],
            eligibility: ReviewEligibility.none,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ainda não há avaliações.'), findsOneWidget);
    expect(find.text('Avaliar profissional'), findsNothing);
  });
}
