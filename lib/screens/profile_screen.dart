import 'package:flutter/material.dart';

import '../models/firm_workspace.dart';
import '../models/law_firm_verification.dart';
import '../models/law_firm_verification_status.dart';
import '../models/lawyer_verification.dart';
import '../models/user_profile.dart';
import '../data/legal_documents.dart';
import 'law_firm_verification_screen.dart';
import 'lawyer_verification_screen.dart';
import 'legal_document_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/law_firm_mode_card.dart';
import '../widgets/profile_header_card.dart';
import '../widgets/profile_menu_section.dart';
import '../widgets/profile_menu_item.dart';
import '../widgets/professional_mode_card.dart';
import '../models/lawyer_status.dart';

class ProfileScreen extends StatelessWidget {
  final UserProfile user;
  final LawyerVerification? lawyerVerification;
  final LawFirmVerification? lawFirmVerification;
  final FirmWorkspace? firmWorkspace;
  final VoidCallback? onSwitchToLawyer;
  final VoidCallback? onSwitchToClient;
  final ValueChanged<LawyerVerification>? onVerificationSubmitted;
  final Future<void> Function()? onRefreshLawyerVerification;
  final ValueChanged<LawFirmVerification>? onLawFirmVerificationSubmitted;
  final VoidCallback? onOpenLawFirmArea;
  final Future<void> Function()? onRefreshLawFirmVerification;
  final VoidCallback? onOpenMessages;
  final VoidCallback? onOpenCases;
  final VoidCallback? onOpenAgenda;
  final VoidCallback? onLogout;
  final Future<void> Function()? onDeleteAccount;

  const ProfileScreen({
    super.key,
    required this.user,
    this.lawyerVerification,
    this.lawFirmVerification,
    this.firmWorkspace,
    this.onSwitchToLawyer,
    this.onSwitchToClient,
    this.onVerificationSubmitted,
    this.onRefreshLawyerVerification,
    this.onLawFirmVerificationSubmitted,
    this.onOpenLawFirmArea,
    this.onRefreshLawFirmVerification,
    this.onOpenMessages,
    this.onOpenCases,
    this.onOpenAgenda,
    this.onLogout,
    this.onDeleteAccount,
  });

  Future<void> _openSecuritySettings(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(
                    color: AppTheme.softShadow,
                    blurRadius: 24,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppTheme.warningSurface,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.lock_outline,
                          color: AppTheme.warning,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Segurança',
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Gerencie ações sensíveis da sua conta.',
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.dangerSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.dangerBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Excluir conta',
                          style: TextStyle(
                            color: AppTheme.danger,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Seu acesso será encerrado e o perfil profissional será removido. Conversas, casos e documentos compartilhados continuam preservados para os demais participantes.',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: onDeleteAccount == null
                                ? null
                                : () {
                                    Navigator.of(sheetContext).pop();
                                    _confirmDeleteAccount(context);
                                  },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.danger,
                              side: const BorderSide(
                                color: AppTheme.dangerBorder,
                              ),
                            ),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Excluir minha conta'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _openLegalDocument(BuildContext context, LegalDocumentType type) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => LegalDocumentScreen(type: type)));
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        var isDeleting = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Excluir conta?'),
              content: const Text(
                'Essa ação desativa sua conta Jurii, remove seu acesso profissional e encerra sua sessão. O histórico compartilhado com outros usuários será mantido.',
              ),
              actions: [
                TextButton(
                  onPressed: isDeleting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  onPressed: isDeleting
                      ? null
                      : () async {
                          setDialogState(() => isDeleting = true);
                          try {
                            await onDeleteAccount?.call();
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                          } catch (_) {
                            if (!dialogContext.mounted) return;
                            setDialogState(() => isDeleting = false);
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Não foi possível excluir a conta. Tente novamente.',
                                ),
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.danger,
                    foregroundColor: AppTheme.card,
                  ),
                  icon: isDeleting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.card,
                          ),
                        )
                      : const Icon(Icons.delete_outline),
                  label: Text(isDeleting ? 'Excluindo...' : 'Excluir conta'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLawyerMode = onSwitchToClient != null;
    final canOpenLawFirmArea =
        isLawyerMode &&
        firmWorkspace?.fromSupabase == true &&
        onOpenLawFirmArea != null;

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Perfil',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                  decoration: TextDecoration.none,
                ),
              ),
              const Text(
                'Gerencie sua conta e acompanhe suas informações.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                  decoration: TextDecoration.none,
                ),
              ),

              const SizedBox(height: 24),

              ProfileHeaderCard(
                name: isLawyerMode ? 'Dr. ${user.name}' : user.name,
                email: user.email,
                initials: user.initials,
                memberSince: isLawyerMode
                    ? user.oabNumber ?? 'Perfil profissional'
                    : user.memberSince,
                onEditTap: () {},
              ),

              const SizedBox(height: 16),

              if (isLawyerMode)
                _SwitchModeCard(
                  title: 'Voltar ao Modo Cliente',
                  subtitle: 'Acesse a área do cliente',
                  icon: Icons.person_outline,
                  color: AppTheme.primary,
                  onTap: onSwitchToClient ?? () {},
                )
              else
                ProfessionalModeCard(
                  lawyerStatus: user.lawyerStatus,
                  onTap: () {
                    switch (user.lawyerStatus) {
                      case LawyerStatus.client:
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LawyerVerificationScreen(
                              user: user,
                              onVerificationSubmitted: onVerificationSubmitted,
                            ),
                          ),
                        );
                        break;
                      case LawyerStatus.pending:
                        onRefreshLawyerVerification?.call();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Sua verificação profissional está em análise.',
                            ),
                          ),
                        );
                        break;
                      case LawyerStatus.approved:
                        onSwitchToLawyer?.call();
                        break;
                    }
                  },
                ),

              if (!isLawyerMode &&
                  lawFirmVerification != null &&
                  lawFirmVerification!.status !=
                      LawFirmVerificationStatus.rejected) ...[
                const SizedBox(height: 12),
                LawFirmModeCard(
                  verification: lawFirmVerification!,
                  onTap: () {
                    switch (lawFirmVerification!.status) {
                      case LawFirmVerificationStatus.pending:
                        onRefreshLawFirmVerification?.call();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'O cadastro do escritório está em análise.',
                            ),
                          ),
                        );
                        break;
                      case LawFirmVerificationStatus.approved:
                        if (onOpenLawFirmArea != null) {
                          onOpenLawFirmArea?.call();
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'A área do escritório será liberada na próxima etapa.',
                              ),
                            ),
                          );
                        }
                        break;
                      case LawFirmVerificationStatus.rejected:
                        break;
                    }
                  },
                ),
              ],

              if (!isLawyerMode &&
                  user.lawyerStatus == LawyerStatus.pending &&
                  lawyerVerification != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.warningSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.warningBorder),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.schedule_outlined,
                        color: AppTheme.warning,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Solicitação enviada para ${lawyerVerification!.practiceArea}. OAB/${lawyerVerification!.oabState} ${lawyerVerification!.oabNumber} em análise.',
                          style: const TextStyle(
                            color: AppTheme.warningText,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              if (isLawyerMode) ...[
                ProfileMenuSection(
                  title: 'ÁREA PROFISSIONAL',
                  items: [
                    if (canOpenLawFirmArea)
                      ProfileMenuItem(
                        icon: Icons.apartment_outlined,
                        iconColor: AppTheme.officePurple,
                        label: 'Área do Escritório',
                        subtitle: 'Acesse ${firmWorkspace!.firm.name}',
                        onTap: onOpenLawFirmArea,
                      ),
                    ProfileMenuItem(
                      icon: Icons.badge_outlined,
                      iconColor: AppTheme.accent,
                      label: 'Perfil Profissional',
                      subtitle: 'Revise sua bio e áreas de atuação',
                      onTap: () {},
                    ),
                    ProfileMenuItem(
                      icon: Icons.schedule_outlined,
                      iconColor: AppTheme.accent,
                      label: 'Disponibilidade',
                      subtitle: 'Gerencie seus horários de atendimento',
                      onTap: onOpenAgenda,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],

              ProfileMenuSection(
                title: 'MINHA CONTA',
                items: [
                  ProfileMenuItem(
                    icon: Icons.person_outline,
                    iconColor: AppTheme.textSecondary,
                    label: 'Dados Pessoais',
                    subtitle: 'Atualize suas informações',
                    onTap: () {},
                  ),
                  ProfileMenuItem(
                    icon: Icons.lock_outline,
                    iconColor: AppTheme.warning,
                    label: 'Segurança',
                    subtitle: 'Senha e configurações de acesso',
                    onTap: () => _openSecuritySettings(context),
                  ),
                  ProfileMenuItem(
                    icon: Icons.description_outlined,
                    iconColor: AppTheme.textSecondary,
                    label: 'Meus Documentos',
                    subtitle: 'Visualize documentos enviados',
                    onTap: () {},
                  ),
                ],
              ),

              const SizedBox(height: 24),

              ProfileMenuSection(
                title: 'ATENDIMENTO',
                items: [
                  ProfileMenuItem(
                    icon: Icons.chat_bubble_outline,
                    iconColor: AppTheme.textSecondary,
                    label: 'Conversas',
                    subtitle: isLawyerMode
                        ? 'Conversas com seus clientes'
                        : 'Acesse suas conversas com escritórios',
                    onTap: onOpenMessages,
                  ),
                  ProfileMenuItem(
                    icon: Icons.folder_outlined,
                    iconColor: AppTheme.accent,
                    label: isLawyerMode ? 'Casos dos Clientes' : 'Meus Casos',
                    subtitle: isLawyerMode
                        ? 'Gerencie os casos dos seus clientes'
                        : 'Acompanhe seus atendimentos',
                    onTap: onOpenCases,
                  ),
                  ProfileMenuItem(
                    icon: Icons.calendar_month_outlined,
                    iconColor: AppTheme.textSecondary,
                    label: 'Reuniões',
                    subtitle: 'Visualize reuniões agendadas',
                    onTap: onOpenAgenda,
                  ),
                ],
              ),

              const SizedBox(height: 24),

              ProfileMenuSection(
                title: 'PLATAFORMA',
                items: [
                  if (!isLawyerMode &&
                      (lawFirmVerification == null ||
                          lawFirmVerification!.status ==
                              LawFirmVerificationStatus.rejected))
                    ProfileMenuItem(
                      icon: Icons.apartment_outlined,
                      iconColor: AppTheme.officePurple,
                      label:
                          lawFirmVerification?.status ==
                              LawFirmVerificationStatus.rejected
                          ? 'Reenviar cadastro do escritório'
                          : 'Cadastrar escritório',
                      subtitle:
                          lawFirmVerification?.status ==
                              LawFirmVerificationStatus.rejected
                          ? 'Revise os dados e envie uma nova solicitação'
                          : 'Valide CNPJ, documentos e responsável legal',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LawFirmVerificationScreen(
                              user: user,
                              onVerificationSubmitted:
                                  onLawFirmVerificationSubmitted,
                            ),
                          ),
                        );
                      },
                    ),
                  ProfileMenuItem(
                    icon: Icons.help_outline,
                    iconColor: AppTheme.primary,
                    label: 'Central de Ajuda',
                    onTap: () {},
                  ),
                  ProfileMenuItem(
                    icon: Icons.phone_outlined,
                    iconColor: AppTheme.primary,
                    label: 'Suporte',
                    onTap: () {},
                  ),
                  ProfileMenuItem(
                    icon: Icons.article_outlined,
                    iconColor: AppTheme.accent,
                    label: 'Termos de Uso',
                    onTap: () => _openLegalDocument(
                      context,
                      LegalDocumentType.termsOfUse,
                    ),
                  ),
                  ProfileMenuItem(
                    icon: Icons.lock_outline,
                    iconColor: AppTheme.accent,
                    label: 'Política de Privacidade',
                    onTap: () => _openLegalDocument(
                      context,
                      LegalDocumentType.privacyPolicy,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.lightBlueBorder),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextButton.icon(
                  onPressed: onLogout,
                  icon: const Icon(Icons.logout, color: AppTheme.danger),
                  label: const Text(
                    'Sair da Conta',
                    style: TextStyle(
                      color: AppTheme.danger,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Center(
                child: Text(
                  'Jurii · Versão 1.0.0',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwitchModeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _SwitchModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.24),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.card.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppTheme.card.withValues(alpha: 0.45),
                  ),
                ),
                child: Icon(icon, color: AppTheme.card, size: 24),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppTheme.card,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppTheme.card,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.card.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.chevron_right,
                  color: AppTheme.card,
                  size: 26,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
