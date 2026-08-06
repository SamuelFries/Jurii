import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'jurii_motion.dart';

/// Barras de força da senha, usadas na recuperação por e-mail e na troca de
/// senha de dentro do app. Era privado de uma tela só; a segunda precisou do
/// mesmo indicador, e duplicar significaria as duas divergirem no primeiro
/// ajuste.
class PasswordStrengthHint extends StatelessWidget {
  final int strength;

  const PasswordStrengthHint({super.key, required this.strength});

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final label = switch (strength) {
      0 || 1 => 'Senha fraca',
      2 => 'Senha média',
      _ => 'Senha forte',
    };
    final color = switch (strength) {
      0 || 1 => colors.danger,
      2 => colors.warning,
      _ => colors.success,
    };

    return Row(
      children: [
        Expanded(
          child: _bar(context, active: strength >= 1, color: color),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _bar(context, active: strength >= 2, color: color),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _bar(context, active: strength >= 3, color: color),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _bar(
    BuildContext context, {
    required bool active,
    required Color color,
  }) {
    final colors = context.jColors;
    return AnimatedContainer(
      duration: JuriiMotion.fast,
      curve: JuriiMotion.ease,
      height: 5,
      decoration: BoxDecoration(
        color: active ? color : colors.divider,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}
