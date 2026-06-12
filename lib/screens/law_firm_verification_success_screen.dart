import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class LawFirmVerificationSuccessScreen extends StatelessWidget {
  const LawFirmVerificationSuccessScreen({super.key});

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
                  color: AppTheme.officePurpleSurface,
                  borderRadius: BorderRadius.circular(48),
                ),
                child: const Icon(
                  Icons.check,
                  color: AppTheme.officePurple,
                  size: 48,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Cadastro enviado',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Recebemos os dados do escritório e vamos analisar a documentação enviada.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.officePurpleSurface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppTheme.officePurpleBorder),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.schedule_outlined, color: AppTheme.officePurple),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Prazo estimado: até 3 dias úteis',
                        style: TextStyle(
                          color: AppTheme.officePurpleText,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.popUntil(context, (route) => route.isFirst);
                  },
                  child: const Text('Voltar ao perfil'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
