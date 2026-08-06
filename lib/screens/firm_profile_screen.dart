import 'package:flutter/material.dart';

import '../models/firm_role.dart';
import '../models/firm_workspace.dart';
import '../models/app_mode.dart';
import '../models/law_firm.dart';
import '../models/lawyer_status.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import '../widgets/profile_menu_item.dart';
import '../widgets/jurii_motion.dart';
import '../widgets/mode_switcher_sheet.dart';
import '../widgets/profile_menu_section.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/theme_mode_sheet.dart';
import 'edit_firm_profile_screen.dart';
import 'professional_bio_screen.dart';
import 'professional_reach_screen.dart';

class FirmProfileScreen extends StatelessWidget {
  const FirmProfileScreen({
    super.key,
    required this.user,
    this.workspace,
    required this.onSwitchToClient,
    this.onSwitchToLawyer,
    required this.onLogout,
    this.onDeleteAccount,
    this.onRefreshWorkspace,
  });

  final UserProfile user;
  final FirmWorkspace? workspace;
  final VoidCallback onSwitchToClient;
  final VoidCallback? onSwitchToLawyer;
  final VoidCallback onLogout;

  /// Recarrega o workspace depois de editar o cadastro. Sem isto o cabeçalho
  /// segue com o nome e o logo antigos até a próxima abertura do app.
  final VoidCallback? onRefreshWorkspace;
  final Future<void> Function()? onDeleteAccount;

  /// Apresentação é peça comercial do escritório: mesmo público que decide
  /// sobre a organização. Secretária não edita.
  bool get _canEditDescription {
    final roles = workspace?.effectiveCurrentUserRoles ?? const [];
    return roles.contains(FirmRole.owner) || roles.contains(FirmRole.admin);
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final colors = context.jColors;

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
                'Essa ação desativa sua conta Jurii. Se você for responsável por um escritório, a gestão será transferida para o membro elegível de maior hierarquia.',
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
                    backgroundColor: colors.danger,
                    foregroundColor: colors.card,
                  ),
                  icon: isDeleting
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.card,
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

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Em preparação — disponível em breve.')),
    );
  }

  List<ModeOption> get _modeOptions => buildModeOptions(
    onClient: onSwitchToClient,
    onLawyer: onSwitchToLawyer,
    onFirm: null,
    hasLawyerMode: user.lawyerStatus == LawyerStatus.approved,
    hasFirmMode: true,
  );

  /// Abre a edição do cadastro. O lápis do cabeçalho e o item de menu chamam
  /// este mesmo caminho — dois botões para a mesma tela não podem divergir no
  /// que fazem ao voltar.
  Future<void> _openEdit(BuildContext context) async {
    final firm = workspace?.firm;
    if (firm == null) return;

    final atualizado = await Navigator.of(context).push<LawFirm>(
      MaterialPageRoute(builder: (_) => EditFirmProfileScreen(firm: firm)),
    );
    // Sem recarregar, o cabeçalho continuaria com o nome e o logo antigos até
    // a próxima abertura do app.
    if (atualizado != null) onRefreshWorkspace?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final workspaceName = workspace?.firm.name ?? 'Escritório';
    // Mesmo portão do item de menu: quem não pode editar não ganha um lápis
    // que abriria uma tela recusada pelo servidor.
    final podeEditar = workspace != null && _canEditDescription;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Escritório',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Gerencie configurações e acesso da área administrativa.',
            style: TextStyle(color: colors.textSecondary, fontSize: 16),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: colors.officePurple,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                ProfileAvatar(
                  imageUrl: workspace?.firm.avatarUrl,
                  initials: workspace?.firm.initials ?? 'JE',
                  size: 52,
                  backgroundColor: colors.card.withValues(alpha: 0.16),
                  foregroundColor: colors.card,
                  borderRadius: BorderRadius.circular(14),
                  fontSize: 17,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        workspaceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.card,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Responsável: ${user.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.card,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                // O mesmo lápis do cabeçalho dos outros dois fluxos, no mesmo
                // canto: quem edita o próprio perfil no modo cliente ou
                // profissional procura aqui por reflexo.
                if (podeEditar)
                  IconButton(
                    key: const Key('firm_profile_edit_button'),
                    tooltip: 'Editar dados do escritório',
                    onPressed: () => _openEdit(context),
                    constraints: const BoxConstraints.tightFor(
                      width: 36,
                      height: 36,
                    ),
                    padding: EdgeInsets.zero,
                    style: IconButton.styleFrom(
                      backgroundColor: colors.card.withValues(alpha: 0.15),
                      foregroundColor: colors.card,
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Mesmo lugar e mesma aparência dos outros dois fluxos: logo abaixo
          // do cabeçalho. Antes ficava no rodapé, DEPOIS de "excluir conta" —
          // a ação frequente embaixo da destrutiva.
          if (shouldShowModeSwitcher(_modeOptions))
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _SwitchAreaCard(
                subtitle: 'Você está em ${AppMode.firm.label}',
                onTap: () => showModeSwitcher(
                  context,
                  current: AppMode.firm,
                  options: _modeOptions,
                  lawFirmId: workspace?.firm.id,
                ),
              ),
            ),
          ProfileMenuSection(
            title: 'GESTÃO',
            items: [
              // Mesmo portão da apresentação e do painel: quem fala pelo
              // escritório. O servidor repete a checagem.
              if (podeEditar)
                ProfileMenuItem(
                  icon: Icons.apartment_outlined,
                  iconColor: colors.officePurple,
                  label: 'Dados do escritório',
                  subtitle: 'Logo, contato, endereço e áreas atendidas',
                  onTap: () => _openEdit(context),
                ),
              // Só owner/admin: o servidor aplica o mesmo gate
              // (is_active_law_firm_manager), este if apenas não oferece o
              // que seria recusado.
              if (workspace != null && _canEditDescription)
                ProfileMenuItem(
                  icon: Icons.badge_outlined,
                  iconColor: colors.officePurple,
                  label: 'Apresentação',
                  subtitle: 'O texto que aparece no perfil do escritório',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ProfessionalBioScreen.lawFirm(
                          lawFirmId: workspace!.firm.id,
                          initialText: workspace!.firm.description,
                        ),
                      ),
                    );
                  },
                ),
              // Mesmo portão da apresentação: quem fala pelo escritório vê o
              // número do escritório. O servidor repete a checagem.
              if (workspace != null && _canEditDescription)
                ProfileMenuItem(
                  icon: Icons.insights_outlined,
                  iconColor: colors.officePurple,
                  label: 'Seu alcance',
                  subtitle: 'Quantas pessoas viram, abriram e conversaram',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ProfessionalReachScreen.lawFirm(
                          lawFirmId: workspace!.firm.id,
                        ),
                      ),
                    );
                  },
                ),
              ProfileMenuItem(
                icon: Icons.group_outlined,
                iconColor: colors.officePurple,
                label: 'Permissões da equipe',
                subtitle: 'Sócios, admins, secretárias e advogados',
                onTap: () => _showComingSoon(context),
              ),
              ProfileMenuItem(
                icon: Icons.schedule_outlined,
                iconColor: colors.officePurple,
                label: 'Horários de atendimento',
                subtitle: 'Disponibilidade do escritório',
                onTap: () => _showComingSoon(context),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: ThemeController.instance,
            builder: (context, themeMode, _) {
              return ProfileMenuSection(
                title: 'PREFERÊNCIAS',
                items: [
                  ProfileMenuItem(
                    icon: Icons.dark_mode_outlined,
                    iconColor: colors.primary,
                    label: 'Aparência',
                    subtitle: 'Tema: ${themeModeLabel(themeMode)}',
                    onTap: () => showThemeModeSheet(context),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          ProfileMenuSection(
            title: 'SEGURANÇA',
            items: [
              ProfileMenuItem(
                icon: Icons.delete_outline,
                iconColor: colors.danger,
                label: 'Excluir conta',
                subtitle: 'Desative seu acesso e remova dados privados',
                onTap: onDeleteAccount == null
                    ? null
                    : () => _confirmDeleteAccount(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: TextButton.icon(
              onPressed: onLogout,
              icon: Icon(Icons.logout, color: colors.danger),
              label: Text(
                'Sair da conta',
                style: TextStyle(
                  color: colors.danger,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cartão de trocar de área do fluxo de escritório — o mesmo formato que o
/// perfil de cliente e de profissional usam, para a ação parecer a mesma nos
/// três lugares.
class _SwitchAreaCard extends StatelessWidget {
  const _SwitchAreaCard({required this.subtitle, required this.onTap});

  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return JuriiPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      semanticLabel: 'Trocar de área',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.officePurpleBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: colors.officePurpleSurface,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(Icons.swap_horiz, color: colors.officePurple),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Trocar de área',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: colors.muted),
          ],
        ),
      ),
    );
  }
}
