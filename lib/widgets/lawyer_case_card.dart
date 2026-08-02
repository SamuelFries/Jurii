import 'package:flutter/material.dart';

import '../models/lawyer_case.dart';
import '../theme/app_colors.dart';
import 'jurii_list_card.dart';

class LawyerCaseCard extends StatelessWidget {
  final LawyerCase lawyerCase;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;

  const LawyerCaseCard({
    super.key,
    required this.lawyerCase,
    this.onTap,
    this.onEdit,
  });

  Color _statusColor(AppColors colors) => switch (lawyerCase.status) {
    LawyerCaseStatus.newMessage => colors.primary,
    LawyerCaseStatus.deadline => colors.danger,
    LawyerCaseStatus.updated => colors.textSecondary,
    LawyerCaseStatus.closed => colors.success,
  };

  IconData get _statusIcon => switch (lawyerCase.status) {
    LawyerCaseStatus.newMessage => Icons.mail_outline,
    LawyerCaseStatus.deadline => Icons.access_time,
    LawyerCaseStatus.updated => Icons.access_time,
    LawyerCaseStatus.closed => Icons.check_circle_outline,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return JuriiListCard(
      onTap: onTap,
      semanticLabel: lawyerCase.title,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.lightBlue,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                lawyerCase.clientInitials,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colors.primary,
                  fontSize: 14,
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
                        lawyerCase.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      flex: 0,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 92),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.lightBlue,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            lawyerCase.area,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              color: colors.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  lawyerCase.clientName,
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(_statusIcon, size: 12, color: _statusColor(colors)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        lawyerCase.lastUpdate,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: _statusColor(colors),
                        ),
                      ),
                    ),
                    // Prazo registrado sem número de processo: lembrete
                    // neutro (não é erro; o andamento só liga com o número).
                    // Teto de largura + ellipsis, como o chip de área acima:
                    // sem isso o Row estoura em 320dp.
                    if (lawyerCase.needsCnjNumber) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        flex: 0,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 108),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colors.lightBlue,
                              border: Border.all(
                                color: colors.lightBlueBorder,
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'Sem nº do processo',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onEdit,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: colors.lightBlue,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.edit_outlined, size: 16, color: colors.primary),
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right, color: colors.textSecondary),
        ],
      ),
    );
  }
}
