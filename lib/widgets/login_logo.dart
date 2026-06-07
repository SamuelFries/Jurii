import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class LoginLogo extends StatelessWidget {
  const LoginLogo({
    super.key,
    this.subtitle = 'Conectando você aos melhores\nespecialistas jurídicos.',
  });

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        RichText(
          text: const TextSpan(
            children: [
              TextSpan(
                text: 'Jurii',
                style: TextStyle(
                  fontSize: 46,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
              ),
              TextSpan(
                text: '•',
                style: TextStyle(
                  fontSize: 46,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.accent,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 16,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}
