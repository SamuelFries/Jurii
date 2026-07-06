import 'package:flutter/material.dart';

import '../data/legal_documents.dart';
import '../screens/legal_document_screen.dart';
import '../theme/app_theme.dart';

class LegalAgreementNotice extends StatelessWidget {
  const LegalAgreementNotice({super.key, required this.prefix});

  final String prefix;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          prefix,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.muted,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 2),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 2,
          children: [
            _LegalTextButton(
              label: 'Termos de Uso',
              type: LegalDocumentType.termsOfUse,
            ),
            const Text(
              'e',
              style: TextStyle(fontSize: 12, color: AppTheme.muted),
            ),
            _LegalTextButton(
              label: 'Política de Privacidade',
              type: LegalDocumentType.privacyPolicy,
            ),
          ],
        ),
      ],
    );
  }
}

class _LegalTextButton extends StatelessWidget {
  const _LegalTextButton({required this.label, required this.type});

  final String label;
  final LegalDocumentType type;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => _openLegalDocument(context, type),
      style: TextButton.styleFrom(
        foregroundColor: AppTheme.primary,
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
      child: Text(label),
    );
  }
}

void _openLegalDocument(BuildContext context, LegalDocumentType type) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => LegalDocumentScreen(type: type)));
}
