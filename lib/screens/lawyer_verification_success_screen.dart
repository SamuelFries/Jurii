import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class LawyerVerificationSuccessScreen extends StatelessWidget {
  const LawyerVerificationSuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),

              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F4EC),
                  borderRadius: BorderRadius.circular(48),
                ),
                child: const Icon(
                  Icons.check,
                  color: Color(0xFF2D7A4F),
                  size: 48,
                ),
              ),

              const SizedBox(height: 24),

              const Text(
                'Documentação enviada',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),

              const SizedBox(height: 12),

              const Text(
                'Recebemos sua documentação.\nNossa equipe irá analisar seus dados e validar seu cadastro profissional.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 16),

              const Text(
                'Você receberá uma notificação quando a análise for concluída.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                ),
              ),

              const Spacer(),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.popUntil(
                      context,
                      (route) => route.isFirst,
                    );
                  },
                  child: const Text(
                    'Voltar ao perfil',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}