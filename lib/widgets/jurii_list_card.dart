import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'jurii_motion.dart';

class JuriiListCard extends StatelessWidget {
  const JuriiListCard({
    super.key,
    required this.child,
    this.onTap,
    this.semanticLabel,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 16,
    this.backgroundColor = AppTheme.card,
    this.borderColor = AppTheme.lightBlueBorder,
    this.pressedScale = 0.985,
    this.shadowColor = AppTheme.softShadow,
    this.shadowBlur = 12,
    this.shadowOffset = const Offset(0, 6),
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color backgroundColor;
  final Color borderColor;
  final double pressedScale;
  final Color shadowColor;
  final double shadowBlur;
  final Offset shadowOffset;

  @override
  Widget build(BuildContext context) {
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
          color: backgroundColor,
          borderRadius: radius,
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: shadowColor,
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
