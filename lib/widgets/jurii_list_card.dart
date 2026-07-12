import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'jurii_motion.dart';

class JuriiListCard extends StatelessWidget {
  const JuriiListCard({
    super.key,
    required this.child,
    this.onTap,
    this.semanticLabel,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 16,
    this.backgroundColor,
    this.borderColor,
    this.pressedScale = 0.985,
    this.shadowColor,
    this.shadowBlur = 12,
    this.shadowOffset = const Offset(0, 6),
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  /// Cores opcionais; quando nulas, seguem a paleta do tema ativo.
  final Color? backgroundColor;
  final Color? borderColor;
  final double pressedScale;
  final Color? shadowColor;
  final double shadowBlur;
  final Offset shadowOffset;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final radius = BorderRadius.circular(borderRadius);
    final disabled = JuriiMotion.disabled(context);

    return JuriiPressable(
      onTap: onTap,
      borderRadius: radius,
      pressedScale: pressedScale,
      semanticLabel: semanticLabel,
      clipBehavior: Clip.none,
      child: AnimatedContainer(
        duration: disabled ? Duration.zero : JuriiMotion.fast,
        curve: JuriiMotion.ease,
        padding: padding,
        decoration: BoxDecoration(
          color: backgroundColor ?? colors.card,
          borderRadius: radius,
          border: Border.all(color: borderColor ?? colors.lightBlueBorder),
          boxShadow: [
            BoxShadow(
              color: shadowColor ?? colors.softShadow,
              blurRadius: shadowBlur,
              offset: shadowOffset,
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}
