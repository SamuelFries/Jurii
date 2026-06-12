import 'package:flutter/material.dart';

import '../data/mock/mock_firm_workspace.dart';
import '../models/firm_role.dart';
import '../models/firm_team_member.dart';
import '../theme/app_theme.dart';

class FirmTeamScreen extends StatelessWidget {
  const FirmTeamScreen({super.key, this.teamMembers});

  final List<FirmTeamMember>? teamMembers;

  @override
  Widget build(BuildContext context) {
    final members = teamMembers ?? mockFirmTeamMembers;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Equipe',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Advogados e operação do escritório.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filled(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Convites serão conectados ao Supabase.'),
                    ),
                  );
                },
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.officePurple,
                  foregroundColor: AppTheme.card,
                ),
                icon: const Icon(Icons.person_add_alt_1),
                tooltip: 'Convidar membro',
              ),
            ],
          ),
          const SizedBox(height: 20),
          for (var index = 0; index < members.length; index++) ...[
            _TeamMemberCard(member: members[index]),
            if (index < members.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _TeamMemberCard extends StatelessWidget {
  const _TeamMemberCard({required this.member});

  final FirmTeamMember member;

  @override
  Widget build(BuildContext context) {
    final roleLabel = switch (member.role) {
      FirmRole.owner => 'Dono',
      FirmRole.admin => 'Admin',
      FirmRole.secretary => 'Secretaria',
      FirmRole.lawyer => 'Advogado',
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        border: Border.all(color: AppTheme.officePurpleBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: member.available
                  ? AppTheme.officePurple
                  : AppTheme.textSecondary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                member.initials,
                style: const TextStyle(
                  color: AppTheme.card,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$roleLabel · ${member.specialty}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _MiniBadge('${member.activeCases} casos'),
                    _MiniBadge('${member.responseHours}h resposta'),
                    _MiniBadge('★ ${member.rating}'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Perfil do membro em preparação.'),
                ),
              );
            },
            icon: const Icon(Icons.chevron_right),
            color: AppTheme.textSecondary,
            tooltip: 'Abrir membro',
          ),
        ],
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.officePurpleSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppTheme.officePurple,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
