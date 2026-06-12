import 'package:flutter/material.dart';

import '../models/law_firm_verification.dart';
import '../models/user_profile.dart';
import '../theme/app_theme.dart';
import 'law_firm_verification_form_screen.dart';

class LawFirmVerificationScreen extends StatelessWidget {
  const LawFirmVerificationScreen({
    super.key,
    required this.user,
    this.onVerificationSubmitted,
  });

  final UserProfile user;
  final ValueChanged<LawFirmVerification>? onVerificationSubmitted;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(
                    Icons.arrow_back_ios_new,
                    color: AppTheme.textPrimary,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Cadastre seu\nEscritório',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                  height: 1.15,
                  fontFamily: 'Serif',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Valide os dados do escritório para receber leads qualificados e preparar a gestão da sua equipe.',
                style: TextStyle(
                  fontSize: 16,
                  color: AppTheme.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              _infoPanel(
                title: 'O que o escritório poderá fazer',
                children: const [
                  _InfoLine('Receber leads voltados para escritórios'),
                  _InfoLine('Convidar advogados e equipe administrativa'),
                  _InfoLine('Acompanhar casos por advogado'),
                  _InfoLine('Visualizar dashboards de desempenho'),
                ],
              ),
              const SizedBox(height: 20),
              _infoPanel(
                title: 'O que será necessário',
                children: const [
                  _RequirementLine(Icons.apartment_outlined, 'CNPJ válido'),
                  _RequirementLine(
                    Icons.assignment_outlined,
                    'Contrato social ou documento equivalente',
                  ),
                  _RequirementLine(
                    Icons.location_on_outlined,
                    'Comprovante de endereço',
                  ),
                  _RequirementLine(
                    Icons.badge_outlined,
                    'Documento do responsável legal',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppTheme.officePurpleSurface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppTheme.officePurpleBorder),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppTheme.officePurple,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.verified_user_outlined,
                        color: AppTheme.card,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'A aprovação do escritório é independente da verificação por OAB. O responsável pode ser dono, administrador ou secretário.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.6,
                          color: AppTheme.officePurpleText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LawFirmVerificationFormScreen(
                          user: user,
                          onVerificationSubmitted: onVerificationSubmitted,
                        ),
                      ),
                    );
                  },
                  child: const Text(
                    'Começar cadastro',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Voltar ao perfil',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _infoPanel({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: AppTheme.softShadow,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, color: AppTheme.success, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RequirementLine extends StatelessWidget {
  const _RequirementLine(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.officePurpleSurface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppTheme.officePurple, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
