import 'package:flutter/material.dart';

import '../data/mock/mock_firm_workspace.dart';
import '../models/user_profile.dart';
import '../theme/app_theme.dart';
import '../widgets/profile_menu_item.dart';
import '../widgets/profile_menu_section.dart';

class FirmProfileScreen extends StatelessWidget {
  const FirmProfileScreen({
    super.key,
    required this.user,
    required this.onSwitchToClient,
    required this.onLogout,
  });

  final UserProfile user;
  final VoidCallback onSwitchToClient;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
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
                      const Text(
                        mockFirmWorkspaceName,
                        style: TextStyle(
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
                onTap: () {},
              ),
              ProfileMenuItem(
                icon: Icons.group_outlined,
                iconColor: AppTheme.officePurple,
                label: 'Permissões da equipe',
                subtitle: 'Dono, admins, secretárias e advogados',
                onTap: () {},
              ),
              ProfileMenuItem(
                icon: Icons.schedule_outlined,
                iconColor: AppTheme.officePurple,
                label: 'Horários de atendimento',
                subtitle: 'Disponibilidade do escritório',
                onTap: () {},
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
