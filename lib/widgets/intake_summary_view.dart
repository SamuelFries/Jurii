import 'package:flutter/material.dart';

import '../models/intake_summary.dart';
import '../theme/app_colors.dart';

/// Renderiza o [IntakeSummary] da triagem em cards, para o cliente revisar antes
/// de procurar um profissional. Usa a paleta semântica (`context.jColors`), então
/// já acompanha o tema claro/escuro.
class IntakeSummaryView extends StatelessWidget {
  const IntakeSummaryView({super.key, required this.summary});

  final IntakeSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Resumo da sua triagem',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Confira o que a assistente organizou. Isto ajuda o profissional a '
          'entender e avaliar seu caso mais rápido.',
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),
        _UrgencyBanner(urgency: summary.urgency, reason: summary.urgencyReason),
        const SizedBox(height: 12),
        _CategoriesCard(categories: summary.suggestedCategories),
        const SizedBox(height: 12),
        _SectionCard(
          icon: Icons.description_outlined,
          title: 'Resumo do caso',
          child: Text(
            summary.caseSummary,
            style: TextStyle(color: colors.textPrimary, height: 1.4),
          ),
        ),
        if (summary.keyPoints.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SectionCard(
            icon: Icons.push_pin_outlined,
            title: 'Pontos importantes',
            child: _BulletList(items: summary.keyPoints),
          ),
        ],
        if (summary.recommendedDocuments.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SectionCard(
            icon: Icons.folder_open_outlined,
            title: 'Documentos para reunir',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final document in summary.recommendedDocuments)
                  _DocumentRow(document: document),
              ],
            ),
          ),
        ],
        if (summary.pendingQuestions.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SectionCard(
            icon: Icons.help_outline,
            title: 'Perguntas que o advogado pode fazer',
            child: _BulletList(
              items: [
                for (final question in summary.pendingQuestions) question.text,
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _UrgencyBanner extends StatelessWidget {
  const _UrgencyBanner({required this.urgency, required this.reason});

  final UrgencyLevel urgency;
  final String reason;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final (Color accent, Color surface) = switch (urgency) {
      UrgencyLevel.low => (colors.success, colors.successSurface),
      UrgencyLevel.medium => (colors.warning, colors.warningSurface),
      UrgencyLevel.high => (colors.warning, colors.warningSurface),
      UrgencyLevel.critical => (colors.danger, colors.dangerSurface),
    };
    final icon = switch (urgency) {
      UrgencyLevel.low => Icons.check_circle_outline,
      UrgencyLevel.medium => Icons.info_outline,
      UrgencyLevel.high => Icons.priority_high,
      UrgencyLevel.critical => Icons.warning_amber_rounded,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Urgência: ${urgency.label}',
                  style: TextStyle(color: accent, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  reason,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoriesCard extends StatelessWidget {
  const _CategoriesCard({required this.categories});

  final List<SuggestedLegalCategory> categories;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return _SectionCard(
      icon: Icons.balance_outlined,
      title: 'Área provável',
      child: categories.isEmpty
          ? Text(
              'Não identificamos uma área específica pelo relato. Um '
              'profissional poderá avaliar seu caso mesmo assim.',
              style: TextStyle(color: colors.textSecondary, height: 1.4),
            )
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in categories)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: colors.lightBlue,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: colors.lightBlueBorder),
                    ),
                    child: Text(
                      '${category.practiceArea} · ${(category.confidence * 100).round()}%',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.lightBlueBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _BulletList extends StatelessWidget {
  const _BulletList({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: colors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item,
                    style: TextStyle(color: colors.textPrimary, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({required this.document});

  final RecommendedDocument document;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline, size: 18, color: colors.success),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  document.title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (document.reason.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    document.reason,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
