import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// "Ver mais" das listas de descoberta. Largura cheia, spinner no lugar do
/// rótulo enquanto a página carrega (e desabilitado — toque duplo não pode
/// disparar duas páginas).
class DiscoveryLoadMoreButton extends StatelessWidget {
  const DiscoveryLoadMoreButton({
    super.key,
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  final String label;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        child: isLoading
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.jColors.primary,
                ),
              )
            : Text(label),
      ),
    );
  }
}
