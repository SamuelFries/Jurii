import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'jurii_motion.dart';

class JuriiFormErrorBanner extends StatelessWidget {
  const JuriiFormErrorBanner({super.key, required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
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
                    color: colors.dangerSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colors.dangerBorder),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline, color: colors.danger, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          message!,
                          textAlign: TextAlign.left,
                          style: TextStyle(
                            color: colors.danger,
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
    this.accentColor,
    this.surfaceColor,
    this.borderColor,
  });

  final int completedSteps;
  final int totalSteps;
  final String title;
  final String subtitle;

  /// Cores opcionais; quando nulas, seguem a paleta do tema ativo.
  final Color? accentColor;
  final Color? surfaceColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final accent = accentColor ?? colors.primary;
    final safeTotal = totalSteps <= 0 ? 1 : totalSteps;
    final safeCompleted = completedSteps.clamp(0, safeTotal).toInt();
    final progress = safeCompleted / safeTotal;

    return AnimatedContainer(
      duration: JuriiMotion.fast,
      curve: JuriiMotion.ease,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceColor ?? colors.lightBlue,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor ?? colors.lightBlueBorder),
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
                  color: colors.card.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  progress >= 1
                      ? Icons.verified_outlined
                      : Icons.pending_actions_outlined,
                  color: accent,
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
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$safeCompleted/$safeTotal',
                style: TextStyle(color: accent, fontWeight: FontWeight.w900),
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
                      color: colors.card.withValues(alpha: 0.72),
                    ),
                    AnimatedContainer(
                      duration: JuriiMotion.standard,
                      curve: JuriiMotion.ease,
                      height: 7,
                      width: constraints.maxWidth * progress,
                      color: accent,
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

class JuriiLoadingButton extends StatelessWidget {
  const JuriiLoadingButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.height = 56,
    this.shadow = true,
    this.backgroundColor,
    this.foregroundColor,
    this.borderRadius = 16,
    this.textStyle = const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final double height;
  final bool shadow;
  final Color? backgroundColor;

  /// Quando nula, segue a paleta do tema ativo (texto sobre o primário).
  final Color? foregroundColor;
  final double borderRadius;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final effectiveBackground = backgroundColor ?? colors.primary;
    final effectiveForeground = foregroundColor ?? colors.card;

    return AnimatedContainer(
      duration: JuriiMotion.fast,
      curve: JuriiMotion.ease,
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: effectiveBackground.withValues(alpha: 0.20),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ]
            : const [],
      ),
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: backgroundColor == null
            ? null
            : ElevatedButton.styleFrom(
                backgroundColor: backgroundColor,
                foregroundColor: effectiveForeground,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(borderRadius),
                ),
              ),
        child: AnimatedSwitcher(
          duration: JuriiMotion.fast,
          switchInCurve: JuriiMotion.ease,
          switchOutCurve: JuriiMotion.exitEase,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            );
          },
          child: isLoading
              ? SizedBox(
                  key: const ValueKey('loading'),
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: effectiveForeground,
                  ),
                )
              : Text(label, key: ValueKey('label_$label'), style: textStyle),
        ),
      ),
    );
  }
}

class JuriiModalSheetScaffold extends StatelessWidget {
  const JuriiModalSheetScaffold({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(24, 12, 24, 24),
    this.backgroundColor,
    this.borderRadius = 28,
  });

  final Widget child;
  final EdgeInsets padding;

  /// Quando nula, segue a paleta do tema ativo.
  final Color? backgroundColor;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor ?? colors.background,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(borderRadius),
          ),
        ),
        padding: padding,
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
              const SizedBox(height: 22),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// Cabeçalho numerado de etapa para formulários longos (Dados, Áreas,
/// Documentos). O número vira check animado quando a etapa é concluída,
/// reforçando o progresso mostrado no [JuriiFormProgressCard].
class JuriiFormSectionHeader extends StatelessWidget {
  const JuriiFormSectionHeader({
    super.key,
    required this.stepNumber,
    required this.title,
    required this.isComplete,
    this.accentColor,
  });

  final int stepNumber;
  final String title;
  final bool isComplete;

  /// Quando nula, segue a paleta do tema ativo.
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final disabled = JuriiMotion.disabled(context);

    return Row(
      children: [
        AnimatedContainer(
          duration: disabled ? Duration.zero : JuriiMotion.fast,
          curve: JuriiMotion.ease,
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: isComplete ? colors.success : colors.lightBlue,
            shape: BoxShape.circle,
            border: Border.all(
              color: isComplete ? colors.success : colors.lightBlueBorder,
            ),
          ),
          child: Center(
            child: isComplete
                ? Icon(Icons.check, size: 15, color: colors.card)
                : Text(
                    '$stepNumber',
                    style: TextStyle(
                      color: accentColor ?? colors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
