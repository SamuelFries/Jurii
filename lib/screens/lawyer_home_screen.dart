import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/attention_today_section.dart';
import '../widgets/lawyer_cases_section.dart';
import '../widgets/lawyer_contacts_section.dart';

class LawyerHomeScreen extends StatelessWidget {
  const LawyerHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Olá, Dr. João',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'Acompanhe seus atendimentos e atividades profissionais.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                  decoration: TextDecoration.none,
                ),
              ),

              const SizedBox(height: 40),

              const AttentionTodaySection(),

              const SizedBox(height: 40),

              const LawyerCasesSection(),

              const SizedBox(height: 40),

              const LawyerContactsSection(),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}