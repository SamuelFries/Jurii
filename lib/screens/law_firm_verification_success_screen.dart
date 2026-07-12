import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class LawFirmVerificationSuccessScreen extends StatelessWidget {
  const LawFirmVerificationSuccessScreen({super.key});

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
                  color: colors.officePurpleSurface,
                  borderRadius: BorderRadius.circular(48),
                ),
                child: Icon(Icons.check, color: colors.officePurple, size: 48),
              ),
              const SizedBox(height: 28),
              Text(
                'Cadastro enviado',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Recebemos os dados do escritório e vamos analisar a documentação enviada.',
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
                  color: colors.officePurpleSurface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: colors.officePurpleBorder),
                ),
                child: Row(
                  children: [
                    Icon(Icons.schedule_outlined, color: colors.officePurple),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Prazo estimado: até 3 dias úteis',
                        style: TextStyle(
                          color: colors.officePurpleText,
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
