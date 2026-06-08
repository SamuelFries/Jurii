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

              const SizedBox(height: 28),

              const Text(
                'Solicitação enviada',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),

              const SizedBox(height: 16),

              const Text(
                'Sua documentação foi recebida e já está em análise.',
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
                  color: const Color(0xFFFEF9EB),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFFF0E5C0),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.schedule_outlined,
                      color: AppTheme.accent,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Prazo estimado: até 2 dias úteis',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
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
                    Navigator.popUntil(
                      context,
                      (route) => route.isFirst,
                    );
                  },
                  child: const Text(
                    'Entendi',
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