import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class CasesScreen extends StatelessWidget {
  const CasesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Futuramente virá da API
    final cases = [];

    return SafeArea(
      child: cases.isEmpty
          ? const _EmptyCasesState()
          : const SizedBox(),
    );
  }
}

class _EmptyCasesState extends StatelessWidget {
  const _EmptyCasesState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Meus Casos',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),

          const SizedBox(height: 8),

          const Text(
            '', //subtitulo aqui
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 16,
            ),
          ),

          const Spacer(),

          Center(
            child: Column(
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF1F8),
                    borderRadius: BorderRadius.circular(48),
                  ),
                  child: const Icon(
                    Icons.folder_open_outlined,
                    size: 42,
                    color: AppTheme.textSecondary,
                  ),
                ),

                const SizedBox(height: 24),

                const Text(
                  'Nenhum caso iniciado',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),

                const SizedBox(height: 12),

                const Text(
                  'Quando você solicitar atendimento a um escritório, seus casos aparecerão aqui.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 15,
                  ),
                ),

                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: () {
                    // depois vamos navegar para Home
                  },
                  child: const Text(
                    'Encontrar Escritórios',
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),
        ],
      ),
    );
  }
}