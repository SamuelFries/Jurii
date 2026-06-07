import 'package:flutter/material.dart';

import '../screens/login_screen.dart';
import '../theme/app_theme.dart';

class RegisterSocialButtons extends StatelessWidget {
  const RegisterSocialButtons({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                height: 1,
                color: Colors.black12,
              ),
            ),

            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 12,
              ),
              child: Text(
                'ou cadastre-se com',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),

            Expanded(
              child: Container(
                height: 1,
                color: Colors.black12,
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        _googleButton(),

        const SizedBox(height: 12),

        _socialButton(
          icon: Icons.apple,
          text: 'Continuar com Apple',
        ),

        const SizedBox(height: 32),

        const Text(
          'Já possui uma conta?',
          style: TextStyle(
            color: AppTheme.textSecondary,
          ),
        ),

        const SizedBox(height: 12),

        SizedBox(
          width: double.infinity,
          height: 56,
          child: OutlinedButton(
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => const LoginScreen(),
                ),
              );
            },
            style: OutlinedButton.styleFrom(
              side: const BorderSide(
                color: AppTheme.accent,
              ),
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              'Entrar',
              style: TextStyle(
                color: AppTheme.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),

        const SizedBox(height: 28),

        const Text(
          'Ao criar sua conta você concorda com nossos\nTermos de Uso e Política de Privacidade.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFFB8C0D4),
            height: 1.6,
          ),
        ),
      ],
    );
  }

  Widget _googleButton() {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140A1C3B),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: OutlinedButton(
        onPressed: () {},
        style: OutlinedButton.styleFrom(
          side: const BorderSide(
            color: Color(0x110A1C3B),
          ),
        ),
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
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _socialButton({
    required IconData icon,
    required String text,
  }) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140A1C3B),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: OutlinedButton.icon(
        onPressed: () {},
        icon: Icon(
          icon,
          color: AppTheme.textPrimary,
        ),
        label: Text(
          text,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(
            color: Color(0x110A1C3B),
          ),
        ),
      ),
    );
  }
}
