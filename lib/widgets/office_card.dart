import 'package:flutter/material.dart';

class OfficeCard extends StatelessWidget {
  final String initials;
  final String officeName;
  final double rating;
  final String distance;
  final String specialty;
  final int reviews;
  final String avatarType;
  final VoidCallback? onTap;

  const OfficeCard({
    super.key,
    required this.initials,
    required this.officeName,
    required this.rating,
    required this.distance,
    required this.specialty,
    required this.reviews,
    required this.avatarType,
    this.onTap,
  });

  Color get avatarColor {
    switch (avatarType) {
      case 'gold':
        return const Color(0xFFB8972A);

      case 'blue':
        return const Color(0xFF1A3A6B);

      default:
        return const Color(0xFF0A1C3B);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: avatarColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
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
                    officeName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color(0xFF0A1C3B),
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    '⭐ $rating ($reviews) • $distance',
                    style: const TextStyle(
                      color: Color(0xFF6B7A99),
                    ),
                  ),

                  const SizedBox(height: 6),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF1F8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      specialty,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF1A3A6B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            ElevatedButton(
              onPressed: onTap,
              child: const Text('Perfil'),
            ),
          ],
        ),
      ),
    );
  }
}