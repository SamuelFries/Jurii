import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'jurii_motion.dart';

class JuriiFormErrorBanner extends StatelessWidget {
  const JuriiFormErrorBanner({super.key, required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final visible = message != null && message!.trim().isNotEmpty;

    return AnimatedSize(
      duration: JuriiMotion.standard,
      curve: JuriiMotion.ease,
      alignment: Alignment.topCenter,
      child: visible
          ? Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TweenAnimationBuilder<double>(
                key: ValueKey(message),
                tween: Tween(begin: 0, end: 1),
                duration: JuriiMotion.fast,
                curve: JuriiMotion.ease,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, 6 * (1 - value)),
                      child: child,
                    ),
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.dangerSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.dangerBorder),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: AppTheme.danger,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          message!,
                          textAlign: TextAlign.left,
                          style: const TextStyle(
                            color: AppTheme.danger,
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }
}

class JuriiFormProgressCard extends StatelessWidget {
  const JuriiFormProgressCard({
    super.key,
    required this.completedSteps,
    required this.totalSteps,
    required this.title,
    required this.subtitle,
    this.accentColor = AppTheme.primary,
    this.surfaceColor = AppTheme.lightBlue,
    this.borderColor = AppTheme.lightBlueBorder,
  });

  final int completedSteps;
  final int totalSteps;
  final String title;
  final String subtitle;
  final Color accentColor;
  final Color surfaceColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final safeTotal = totalSteps <= 0 ? 1 : totalSteps;
    final safeCompleted = completedSteps.clamp(0, safeTotal).toInt();
    final progress = safeCompleted / safeTotal;

    return AnimatedContainer(
      duration: JuriiMotion.fast,
      curve: JuriiMotion.ease,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.card.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  progress >= 1
                      ? Icons.verified_outlined
                      : Icons.pending_actions_outlined,
                  color: accentColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$safeCompleted/$safeTotal',
                style: TextStyle(
                  color: accentColor,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    Container(
                      height: 7,
                      width: double.infinity,
                      color: AppTheme.card.withValues(alpha: 0.72),
                    ),
                    AnimatedContainer(
                      duration: JuriiMotion.standard,
                      curve: JuriiMotion.ease,
                      height: 7,
                      width: constraints.maxWidth * progress,
                      color: accentColor,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
