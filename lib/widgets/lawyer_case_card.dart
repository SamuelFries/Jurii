import 'package:flutter/material.dart';
import '../models/lawyer_case.dart';
import '../theme/app_theme.dart';
import 'jurii_motion.dart';

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

  Color get _statusColor => switch (lawyerCase.status) {
    LawyerCaseStatus.newMessage => AppTheme.primary,
    LawyerCaseStatus.deadline => AppTheme.danger,
    LawyerCaseStatus.updated => AppTheme.textSecondary,
  };

  IconData get _statusIcon => switch (lawyerCase.status) {
    LawyerCaseStatus.newMessage => Icons.mail_outline,
    LawyerCaseStatus.deadline => Icons.access_time,
    LawyerCaseStatus.updated => Icons.access_time,
  };

  @override
  Widget build(BuildContext context) {
    return JuriiPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      semanticLabel: lawyerCase.title,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.lightBlueBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.lightBlue,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  lawyerCase.clientInitials,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary,
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
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: AppTheme.textPrimary,
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
                              color: AppTheme.lightBlue,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              lawyerCase.area,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppTheme.primary,
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
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(_statusIcon, size: 12, color: _statusColor),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          lawyerCase.lastUpdate,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: _statusColor),
                        ),
                      ),
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
                  color: AppTheme.lightBlue,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: AppTheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}
