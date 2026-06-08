import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class LawyerVerificationScreen extends StatelessWidget {
  const LawyerVerificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text(
          'Verificação profissional',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppTheme.lightGold,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppTheme.lightGoldBorder),
                ),
                child: const Icon(
                  Icons.verified_user_outlined,
                  color: AppTheme.accent,
                  size: 32,
                ),
              ),

              const SizedBox(height: 24),

              const Text(
                'Vamos validar seu cadastro na OAB',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 12),

              const Text(
                'Esta é a primeira etapa para ativar o modo profissional e atender clientes pela Jurii.',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),

              const Spacer(),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {},
                  child: const Text('Começar verificação'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
