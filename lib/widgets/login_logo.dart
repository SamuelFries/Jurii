import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class LoginLogo extends StatelessWidget {
  const LoginLogo({
    super.key,
    this.subtitle = 'Conectando você aos melhores\nespecialistas jurídicos.',
  });

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Column(
      children: [
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: 'Jurii',
                style: TextStyle(
                  fontSize: 46,
                  fontWeight: FontWeight.bold,
                  color: colors.primary,
                ),
              ),
              TextSpan(
                text: '•',
                style: TextStyle(
                  fontSize: 46,
                  fontWeight: FontWeight.bold,
                  color: colors.accent,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 16,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}
