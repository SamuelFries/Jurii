import 'package:flutter/material.dart';

import '../data/legal_documents.dart';
import '../theme/app_colors.dart';

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, required this.type});

  final LegalDocumentType type;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final document = legalDocumentFor(type);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: Text(document.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            _DocumentHeader(document: document),
            const SizedBox(height: 18),
            for (final section in document.sections) ...[
              _DocumentSectionView(section: section),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}

class _DocumentHeader extends StatelessWidget {
  const _DocumentHeader({required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.lightBlueBorder),
        boxShadow: [
          BoxShadow(
            color: colors.softShadow,
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              document.updatedAt,
              style: TextStyle(
                color: colors.accent,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              document.summary,
              style: TextStyle(
                color: colors.textPrimary,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentSectionView extends StatelessWidget {
  const _DocumentSectionView({required this.section});

  final LegalDocumentSection section;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              section.title,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            for (final paragraph in section.body) ...[
              Text(
                paragraph,
                style: TextStyle(
                  color: colors.textSecondary,
                  height: 1.55,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (paragraph != section.body.last) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}
