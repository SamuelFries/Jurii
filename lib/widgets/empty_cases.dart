import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class EmptyCases extends StatelessWidget {
  const EmptyCases({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 170,
              height: 170,
              decoration: const BoxDecoration(
                color: Color(0xFFF0F3F8),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.folder_open_outlined,
                size: 72,
                color: AppTheme.textSecondary,
              ),
            ),

            const SizedBox(height: 36),

            const Text(
              'Nenhum caso iniciado',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),

            const SizedBox(height: 16),

            const Text(
              'Quando você solicitar atendimento a um escritório, seus casos aparecerão aqui.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                height: 1.6,
                color: AppTheme.textSecondary,
              ),
            ),

            const SizedBox(height: 36),

            SizedBox(
              width: 260,
              height: 56,
              child: ElevatedButton(
                onPressed: () {},
                child: const Text(
                  'Encontrar Escritórios',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}