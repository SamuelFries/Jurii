import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SocialLoginButtons extends StatelessWidget {
  const SocialLoginButtons({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Divider(
                color: Colors.grey.shade300,
              ),
            ),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'ou continue com',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                ),
              ),
            ),

            Expanded(
              child: Divider(
                color: Colors.grey.shade300,
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // GOOGLE
        SizedBox(
          width: double.infinity,
          height: 56,
          child: OutlinedButton(
            onPressed: () {},
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/google_logo.png',
                  width: 20,
                  height: 20,
                ),

                const SizedBox(width: 12),

                const Text(
                  'Continuar com Google',
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // APPLE
        SizedBox(
          width: double.infinity,
          height: 56,
          child: OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.apple),
            label: const Text(
              'Continuar com Apple',
            ),
          ),
        ),

        const SizedBox(height: 32),

        const Text(
          'Ainda não possui conta?',
          style: TextStyle(
            color: AppTheme.textSecondary,
          ),
        ),

        const SizedBox(height: 16),

        SizedBox(
          width: double.infinity,
          height: 56,
          child: OutlinedButton(
            onPressed: () {},
            style: OutlinedButton.styleFrom(
              side: const BorderSide(
                color: AppTheme.accent,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              'Criar conta',
              style: TextStyle(
                color: AppTheme.accent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),

        const SizedBox(height: 24),

        const Text(
          'Ao continuar você concorda com nossos\nTermos de Uso e Política de Privacidade.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}