/// Uma avaliação (nota + comentário) de um cliente sobre um profissional.
class ProfessionalReview {
  const ProfessionalReview({
    required this.id,
    required this.reviewerName,
    required this.reviewerInitials,
    required this.rating,
    required this.createdAt,
    this.comment,
    this.isMine = false,
  });

  final String id;
  final String reviewerName;
  final String reviewerInitials;
  final int rating;
  final String? comment;
  final DateTime? createdAt;
  final bool isMine;

  factory ProfessionalReview.fromRow(Map<String, dynamic> row) {
    return ProfessionalReview(
      id: row['id'] as String,
      reviewerName: (row['reviewer_name'] as String?)?.trim().isNotEmpty == true
          ? row['reviewer_name'] as String
          : 'Cliente Jurii',
      reviewerInitials:
          (row['reviewer_initials'] as String?)?.trim().isNotEmpty == true
          ? row['reviewer_initials'] as String
          : 'C',
      rating: (row['rating'] as num?)?.toInt() ?? 0,
      comment: (row['comment'] as String?)?.trim().isEmpty ?? true
          ? null
          : row['comment'] as String,
      createdAt: row['created_at'] is String
          ? DateTime.tryParse(row['created_at'] as String)
          : null,
      isMine: row['is_mine'] as bool? ?? false,
    );
  }
}

/// Se o cliente atual pode avaliar o profissional e, se já avaliou, a nota
/// atual (para pré-preencher a edição).
class ReviewEligibility {
  const ReviewEligibility({
    required this.canReview,
    this.myRating,
    this.myComment,
  });

  final bool canReview;
  final int? myRating;
  final String? myComment;

  bool get hasReviewed => myRating != null;

  static const none = ReviewEligibility(canReview: false);

  factory ReviewEligibility.fromRow(Map<String, dynamic> row) {
    return ReviewEligibility(
      canReview: row['can_review'] as bool? ?? false,
      myRating: (row['my_rating'] as num?)?.toInt(),
      myComment: (row['my_comment'] as String?)?.trim().isEmpty ?? true
          ? null
          : row['my_comment'] as String,
    );
  }
}
