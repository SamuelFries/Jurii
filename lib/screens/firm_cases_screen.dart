import 'package:flutter/material.dart';

import '../data/mock/mock_firm_workspace.dart';
import '../models/firm_case_overview.dart';
import '../theme/app_theme.dart';

class FirmCasesScreen extends StatelessWidget {
  const FirmCasesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Casos',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Visão geral dos casos por cliente e advogado responsável.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
          ),
          const SizedBox(height: 20),
          for (var index = 0; index < mockFirmCases.length; index++) ...[
            _FirmCaseCard(overview: mockFirmCases[index]),
            if (index < mockFirmCases.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _FirmCaseCard extends StatelessWidget {
  const _FirmCaseCard({required this.overview});

  final FirmCaseOverview overview;

  @override
  Widget build(BuildContext context) {
    final statusColor = overview.urgent ? AppTheme.danger : AppTheme.primary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        border: Border.all(
          color: overview.urgent
              ? AppTheme.danger.withValues(alpha: 0.35)
              : AppTheme.officePurpleBorder,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: overview.urgent
                  ? AppTheme.danger.withValues(alpha: 0.10)
                  : AppTheme.officePurpleSurface,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Center(
              child: Text(
                overview.clientInitials,
                style: TextStyle(
                  color: overview.urgent
                      ? AppTheme.danger
                      : AppTheme.officePurple,
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        overview.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        overview.area,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${overview.clientName} · ${overview.assignedLawyer}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      overview.urgent
                          ? Icons.warning_amber_outlined
                          : Icons.task_alt_outlined,
                      color: statusColor,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${overview.statusLabel}: ${overview.nextStep}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: statusColor, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
        ],
      ),
    );
  }
}
