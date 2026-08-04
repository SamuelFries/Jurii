import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Estado de erro de carregamento com retry. Falha de rede nunca pode virar
/// estado vazio ("você não tem nada") — quando o fetch da tela falhar e não
/// houver dado anterior para manter, é este widget que aparece.
class JuriiErrorState extends StatelessWidget {
  const JuriiErrorState({
    super.key,
    required this.title,
    this.message = 'Verifique sua conexão e tente novamente.',
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 40, color: colors.textSecondary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
