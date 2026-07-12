import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class LawyerVerificationSuccessScreen extends StatelessWidget {
  const LawyerVerificationSuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Scaffold(
      backgroundColor: colors.background,
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
                  color: colors.successSurface,
                  borderRadius: BorderRadius.circular(48),
                ),
                child: Icon(Icons.check, color: colors.success, size: 48),
              ),

              const SizedBox(height: 28),

              Text(
                'Solicitação enviada',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),

              const SizedBox(height: 16),

              Text(
                'Sua documentação foi recebida e já está em análise.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textSecondary,
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
                  color: colors.warningSurface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: colors.warningBorder),
                ),
                child: Row(
                  children: [
                    Icon(Icons.schedule_outlined, color: colors.accent),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Prazo estimado: até 2 dias úteis',
                        style: TextStyle(
                          color: colors.textPrimary,
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
