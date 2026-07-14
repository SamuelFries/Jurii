import 'package:flutter/material.dart';

import '../models/professional_review.dart';
import '../repositories/review_repository.dart';
import '../theme/app_colors.dart';
import 'jurii_motion.dart';

/// Linha de estrelas (somente leitura) para uma nota.
class ReviewStars extends StatelessWidget {
  const ReviewStars({
    super.key,
    required this.rating,
    this.size = 16,
    this.color,
  });

  final double rating;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final star = color ?? colors.accent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final filled = rating >= index + 1;
        final half = !filled && rating > index;
        return Icon(
          filled
              ? Icons.star_rounded
              : half
              ? Icons.star_half_rounded
              : Icons.star_outline_rounded,
          size: size,
          color: filled || half ? star : colors.muted,
        );
      }),
    );
  }
}

/// Painel de avaliações de um profissional: lista as avaliações e, para quem
/// pode avaliar (já conversou), oferece o botão de dar/editar a nota.
class ReviewsPanel extends StatefulWidget {
  const ReviewsPanel({
    super.key,
    required this.target,
    required this.targetId,
    this.repository = const ReviewRepository(),
    this.accentColor,
  });

  final ReviewTarget target;
  final String targetId;
  final ReviewRepository repository;
  final Color? accentColor;

  @override
  State<ReviewsPanel> createState() => _ReviewsPanelState();
}

class _ReviewsPanelState extends State<ReviewsPanel> {
  bool _loading = true;
  bool _failed = false;
  List<ProfessionalReview> _reviews = const [];
  ReviewEligibility _eligibility = ReviewEligibility.none;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.repository.fetchReviews(
          target: widget.target,
          targetId: widget.targetId,
        ),
        widget.repository.fetchEligibility(
          target: widget.target,
          targetId: widget.targetId,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _reviews = results[0] as List<ProfessionalReview>;
        _eligibility = results[1] as ReviewEligibility;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _openReviewSheet() async {
    final result = await showModalBottomSheet<_ReviewDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReviewSheet(
        accentColor: widget.accentColor,
        initialRating: _eligibility.myRating ?? 0,
        initialComment: _eligibility.myComment ?? '',
        canDelete: _eligibility.hasReviewed,
      ),
    );
    if (result == null) return;

    try {
      if (result.delete) {
        await widget.repository.deleteReview(
          target: widget.target,
          targetId: widget.targetId,
        );
      } else {
        await widget.repository.submitReview(
          target: widget.target,
          targetId: widget.targetId,
          rating: result.rating,
          comment: result.comment,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.delete ? 'Avaliação removida.' : 'Avaliação enviada.',
          ),
        ),
      );
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível salvar sua avaliação. Tente de novo.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final accent = widget.accentColor ?? colors.accent;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.lightBlueBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Avaliações',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (!_loading && _reviews.isNotEmpty)
                Text(
                  '${_reviews.length}',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            _LoadingRows(color: colors.lightBlue)
          else if (_failed)
            Text(
              'Não foi possível carregar as avaliações.',
              style: TextStyle(color: colors.textSecondary),
            )
          else ...[
            if (_eligibility.canReview) ...[
              _RateButton(
                accent: accent,
                label: _eligibility.hasReviewed
                    ? 'Editar sua avaliação'
                    : 'Avaliar profissional',
                onTap: _openReviewSheet,
              ),
              const SizedBox(height: 14),
            ] else ...[
              // Explica a ausência do botão e, de quebra, sinaliza que as notas
              // vêm de clientes reais.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    size: 16,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Só clientes com um caso aceito podem avaliar.',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            if (_reviews.isEmpty)
              Text(
                _eligibility.canReview
                    ? 'Seja o primeiro a avaliar.'
                    : 'Ainda não há avaliações.',
                style: TextStyle(color: colors.textSecondary, height: 1.4),
              )
            else
              for (var i = 0; i < _reviews.length; i++)
                JuriiStaggeredItem(
                  index: i,
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: i == _reviews.length - 1 ? 0 : 14,
                    ),
                    child: _ReviewCard(review: _reviews[i], accent: accent),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

class _RateButton extends StatelessWidget {
  const _RateButton({
    required this.accent,
    required this.label,
    required this.onTap,
  });

  final Color accent;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.star_rounded, color: accent, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(color: accent, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review, required this.accent});

  final ProfessionalReview review;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: review.isMine
            ? accent.withValues(alpha: 0.06)
            : colors.lightBlue,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: review.isMine
              ? accent.withValues(alpha: 0.30)
              : colors.lightBlueBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.card,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.lightBlueBorder),
                ),
                child: Center(
                  child: Text(
                    review.reviewerInitials,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            review.isMine ? 'Você' : review.reviewerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (review.createdAt != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            _formatDate(review.createdAt!),
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    ReviewStars(
                      rating: review.rating.toDouble(),
                      size: 15,
                      color: accent,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (review.comment != null) ...[
            const SizedBox(height: 10),
            Text(
              review.comment!,
              style: TextStyle(
                color: colors.textSecondary,
                height: 1.4,
                fontSize: 14,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatDate(DateTime date) {
    final d = date.toLocal();
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }
}

class _LoadingRows extends StatelessWidget {
  const _LoadingRows({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        2,
        (i) => Container(
          margin: EdgeInsets.only(bottom: i == 1 ? 0 : 12),
          height: 64,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

/// Resultado do sheet de avaliação.
class _ReviewDraft {
  const _ReviewDraft({this.rating = 0, this.comment, this.delete = false});
  final int rating;
  final String? comment;
  final bool delete;
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({
    required this.initialRating,
    required this.initialComment,
    required this.canDelete,
    this.accentColor,
  });

  final int initialRating;
  final String initialComment;
  final bool canDelete;
  final Color? accentColor;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  late int _rating = widget.initialRating;
  late final TextEditingController _comment = TextEditingController(
    text: widget.initialComment,
  );

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final accent = widget.accentColor ?? colors.accent;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.divider,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                widget.canDelete ? 'Editar avaliação' : 'Avaliar',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Sua nota ajuda outros clientes a escolher.',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(5, (index) {
                    final value = index + 1;
                    final active = _rating >= value;
                    return IconButton(
                      onPressed: () => setState(() => _rating = value),
                      iconSize: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        active
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: active ? accent : colors.muted,
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _comment,
                maxLines: 4,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Conte como foi o atendimento (opcional)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: accent),
                onPressed: _rating == 0
                    ? null
                    : () => Navigator.of(context).pop(
                        _ReviewDraft(
                          rating: _rating,
                          comment: _comment.text.trim().isEmpty
                              ? null
                              : _comment.text.trim(),
                        ),
                      ),
                child: Text(widget.canDelete ? 'Salvar' : 'Enviar avaliação'),
              ),
              if (widget.canDelete)
                TextButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(const _ReviewDraft(delete: true)),
                  child: Text(
                    'Remover minha avaliação',
                    style: TextStyle(color: colors.danger),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
