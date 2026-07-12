import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'jurii_motion.dart';

class JuriiEmptyState extends StatelessWidget {
  const JuriiEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.accentColor,
    this.surfaceColor,
    this.borderColor,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Cores opcionais; quando nulas, seguem a paleta do tema ativo.
  final Color? accentColor;
  final Color? surfaceColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final accent = accentColor ?? colors.primary;
    final surface = surfaceColor ?? colors.lightBlue;
    final border = borderColor ?? colors.lightBlueBorder;

    return JuriiStaggeredItem(
      index: 0,
      beginOffset: const Offset(0, 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.hasBoundedHeight && constraints.maxHeight < 420;
          final iconBoxSize = compact ? 64.0 : 96.0;
          final iconSize = compact ? 28.0 : 42.0;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.92, end: 1),
                    duration: JuriiMotion.slow,
                    curve: JuriiMotion.ease,
                    builder: (context, scale, child) {
                      return Transform.scale(scale: scale, child: child);
                    },
                    child: Container(
                      width: iconBoxSize,
                      height: iconBoxSize,
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(iconBoxSize / 2),
                        border: Border.all(color: border),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.08),
                            blurRadius: compact ? 18 : 24,
                            offset: Offset(0, compact ? 8 : 12),
                          ),
                        ],
                      ),
                      child: Icon(icon, size: iconSize, color: accent),
                    ),
                  ),
                  SizedBox(height: compact ? 12 : 24),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: compact ? 19 : 22,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  SizedBox(height: compact ? 6 : 12),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: compact ? 13 : 15,
                      height: 1.35,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  if (actionLabel != null) ...[
                    SizedBox(height: compact ? 12 : 24),
                    ElevatedButton(
                      onPressed: onAction,
                      child: Text(actionLabel!),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
