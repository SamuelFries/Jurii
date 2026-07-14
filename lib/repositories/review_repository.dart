import '../models/professional_review.dart';
import '../services/supabase_config.dart';

/// Tipo de alvo de uma avaliação — igual à string usada nos RPCs do banco.
enum ReviewTarget {
  lawyer('lawyer'),
  lawFirm('law_firm');

  const ReviewTarget(this.value);
  final String value;
}

/// Acesso às avaliações de profissionais (advogado/escritório).
///
/// Escrita passa só pelos RPCs SECURITY DEFINER, que aplicam o gate (só avalia
/// quem já teve conversa com o profissional). Fora do Supabase (modo demo)
/// tudo vira no-op/vazio.
class ReviewRepository {
  const ReviewRepository();

  Future<List<ProfessionalReview>> fetchReviews({
    required ReviewTarget target,
    required String targetId,
    int limit = 20,
  }) async {
    if (!SupabaseConfig.isReady) return const [];

    final rows = await SupabaseConfig.client.rpc(
      'fetch_professional_reviews',
      params: {
        'target_type_value': target.value,
        'target_id_value': targetId,
        'limit_value': limit,
      },
    );

    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(ProfessionalReview.fromRow)
        .toList();
  }

  Future<ReviewEligibility> fetchEligibility({
    required ReviewTarget target,
    required String targetId,
  }) async {
    if (!SupabaseConfig.isReady) return ReviewEligibility.none;

    final rows = await SupabaseConfig.client.rpc(
      'fetch_review_eligibility',
      params: {'target_type_value': target.value, 'target_id_value': targetId},
    );

    final list = (rows as List<dynamic>).cast<Map<String, dynamic>>();
    if (list.isEmpty) return ReviewEligibility.none;
    return ReviewEligibility.fromRow(list.first);
  }

  Future<void> submitReview({
    required ReviewTarget target,
    required String targetId,
    required int rating,
    String? comment,
  }) async {
    if (!SupabaseConfig.isReady) return;

    await SupabaseConfig.client.rpc(
      'submit_professional_review',
      params: {
        'target_type_value': target.value,
        'target_id_value': targetId,
        'rating_value': rating,
        'comment_value': comment,
      },
    );
  }

  Future<void> deleteReview({
    required ReviewTarget target,
    required String targetId,
  }) async {
    if (!SupabaseConfig.isReady) return;

    await SupabaseConfig.client.rpc(
      'delete_professional_review',
      params: {'target_type_value': target.value, 'target_id_value': targetId},
    );
  }
}
