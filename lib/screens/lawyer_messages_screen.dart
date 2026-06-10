import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class LawyerMessagesScreen extends StatelessWidget {
  const LawyerMessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO: substituir por dados reais da API
    final conversations = [];

    return SafeArea(
      child: conversations.isEmpty
          ? const _EmptyMessagesState()
          : const SizedBox(),
    );
  }
}

class _EmptyMessagesState extends StatelessWidget {
  const _EmptyMessagesState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Mensagens',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
              decoration: TextDecoration.none,
            ),
          ),

          const SizedBox(height: 8),

          const Text(''), 

          const Spacer(),

          Center(
            child: Column(
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppTheme.lightBlue,
                    borderRadius: BorderRadius.circular(48),
                  ),
                  child: const Icon(
                    Icons.chat_bubble_outline,
                    size: 42,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Nenhuma mensagem recebida',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Quando clientes entrarem em contato, as conversas aparecerão aqui.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 15,
                    decoration: TextDecoration.none,
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