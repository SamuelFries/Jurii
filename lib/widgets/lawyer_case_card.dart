import 'package:flutter/material.dart';
import '../models/lawyer_case.dart';
import '../theme/app_theme.dart';

class LawyerCaseCard extends StatelessWidget {
  final LawyerCase lawyerCase;
  final VoidCallback? onTap;

  const LawyerCaseCard({
    super.key,
    required this.lawyerCase,
    this.onTap,
  });

  Color get _statusColor => switch (lawyerCase.status) {
    LawyerCaseStatus.newMessage => AppTheme.primary,
    LawyerCaseStatus.deadline => Colors.redAccent,
    LawyerCaseStatus.updated => AppTheme.textSecondary,
  };

  IconData get _statusIcon => switch (lawyerCase.status) {
    LawyerCaseStatus.newMessage => Icons.mail_outline,
    LawyerCaseStatus.deadline => Icons.access_time,
    LawyerCaseStatus.updated => Icons.access_time,
  };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
                      Text(
                        lawyerCase.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
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
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w500,
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
                      Text(
                        lawyerCase.lastUpdate,
                        style: TextStyle(
                          fontSize: 12,
                          color: _statusColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}