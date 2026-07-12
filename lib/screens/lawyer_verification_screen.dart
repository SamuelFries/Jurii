import 'package:flutter/material.dart';

import '../models/lawyer_verification.dart';
import '../models/user_profile.dart';
import 'lawyer_verification_form_screen.dart';
import '../theme/app_colors.dart';

class LawyerVerificationScreen extends StatelessWidget {
  final UserProfile user;
  final ValueChanged<LawyerVerification>? onVerificationSubmitted;

  const LawyerVerificationScreen({
    super.key,
    required this.user,
    this.onVerificationSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Botão voltar
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.arrow_back_ios_new,
                    color: colors.textPrimary,
                    size: 18,
                  ),
                ),
              ),

              const SizedBox(height: 28),

              Text(
                'Ative seu Perfil\nProfissional',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                  height: 1.15,
                  fontFamily: 'Serif',
                ),
              ),

              const SizedBox(height: 12),

              Text(
                'Atenda clientes pela Jurii e faça parte da nossa rede de profissionais verificados.',
                style: TextStyle(
                  fontSize: 16,
                  color: colors.textSecondary,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 28),

              // BENEFÍCIOS
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: colors.softShadow,
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Benefícios',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),

                    const SizedBox(height: 18),

                    _benefit('Receba novos clientes', colors),
                    _benefit(
                      'Gerencie seus casos em um painel profissional',
                      colors,
                    ),
                    _benefit('Converse com clientes pela plataforma', colors),
                    _benefit('Faça parte de escritórios parceiros', colors),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // REQUISITOS
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: colors.softShadow,
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'O que será necessário',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),

                    const SizedBox(height: 18),

                    _requirement(
                      Icons.workspace_premium_outlined,
                      'Número da OAB',
                      colors,
                    ),

                    _requirement(
                      Icons.description_outlined,
                      'Documento de identificação',
                      colors,
                    ),

                    _requirement(
                      Icons.assignment_outlined,
                      'Comprovante de inscrição profissional',
                      colors,
                    ),

                    _requirement(
                      Icons.photo_camera_outlined,
                      'Foto para perfil profissional',
                      colors,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // CARD AMARELO
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: colors.warningSurface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: colors.warningBorder),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: colors.accent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.shield_outlined, color: colors.card),
                    ),

                    const SizedBox(width: 14),

                    Expanded(
                      child: Text(
                        'Sua documentação será analisada pela equipe da Jurii para garantir a autenticidade dos profissionais cadastrados.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.6,
                          color: colors.warningText,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // BOTÃO PRINCIPAL
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LawyerVerificationFormScreen(
                          user: user,
                          onVerificationSubmitted: onVerificationSubmitted,
                        ),
                      ),
                    );
                  },
                  child: const Text(
                    'Começar Verificação',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // BOTÃO SECUNDÁRIO
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text(
                    'Voltar ao modo cliente',
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

  static Widget _benefit(String text, AppColors colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: colors.successSurface,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check, size: 14, color: colors.success),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 15,
                color: colors.textPrimary,
                fontWeight: FontWeight.w500,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _requirement(IconData icon, String text, AppColors colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: colors.lightBlue,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: colors.textPrimary, size: 18),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 15,
                color: colors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
