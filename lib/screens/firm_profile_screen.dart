import 'package:flutter/material.dart';

import '../models/firm_workspace.dart';
import '../models/lawyer_status.dart';
import '../models/user_profile.dart';
import '../theme/app_theme.dart';
import '../widgets/profile_menu_item.dart';
import '../widgets/profile_menu_section.dart';

class FirmProfileScreen extends StatelessWidget {
  const FirmProfileScreen({
    super.key,
    required this.user,
    this.workspace,
    required this.onSwitchToClient,
    this.onSwitchToLawyer,
    required this.onLogout,
    this.onDeleteAccount,
  });

  final UserProfile user;
  final FirmWorkspace? workspace;
  final VoidCallback onSwitchToClient;
  final VoidCallback? onSwitchToLawyer;
  final VoidCallback onLogout;
  final Future<void> Function()? onDeleteAccount;

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

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Em preparação — disponível em breve.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final workspaceName = workspace?.firm.name ?? 'Escritório';

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Escritório',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Gerencie configurações e acesso da área administrativa.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.officePurple,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppTheme.card.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.apartment_outlined,
                    color: AppTheme.card,
                  ),
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
                        style: const TextStyle(
                          color: AppTheme.card,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Responsável: ${user.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.card,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ProfileMenuSection(
            title: 'GESTÃO',
            items: [
              ProfileMenuItem(
                icon: Icons.apartment_outlined,
                iconColor: AppTheme.officePurple,
                label: 'Dados do escritório',
                subtitle: 'CNPJ, endereço e áreas atendidas',
                onTap: () => _showComingSoon(context),
              ),
              ProfileMenuItem(
                icon: Icons.group_outlined,
                iconColor: AppTheme.officePurple,
                label: 'Permissões da equipe',
                subtitle: 'Dono, admins, secretárias e advogados',
                onTap: () => _showComingSoon(context),
              ),
              ProfileMenuItem(
                icon: Icons.schedule_outlined,
                iconColor: AppTheme.officePurple,
                label: 'Horários de atendimento',
                subtitle: 'Disponibilidade do escritório',
                onTap: () => _showComingSoon(context),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ProfileMenuSection(
            title: 'SEGURANÇA',
            items: [
              ProfileMenuItem(
                icon: Icons.delete_outline,
                iconColor: AppTheme.danger,
                label: 'Excluir conta',
                subtitle: 'Desative seu acesso e remova dados privados',
                onTap: onDeleteAccount == null
                    ? null
                    : () => _confirmDeleteAccount(context),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: OutlinedButton.icon(
              onPressed: onSwitchToClient,
              icon: const Icon(Icons.person_outline),
              label: const Text('Voltar ao modo cliente'),
            ),
          ),
          if (user.lawyerStatus == LawyerStatus.approved &&
              onSwitchToLawyer != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: onSwitchToLawyer,
                icon: const Icon(Icons.balance_outlined),
                label: const Text('Voltar ao modo profissional'),
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: TextButton.icon(
              onPressed: onLogout,
              icon: const Icon(Icons.logout, color: AppTheme.danger),
              label: const Text(
                'Sair da conta',
                style: TextStyle(
                  color: AppTheme.danger,
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
