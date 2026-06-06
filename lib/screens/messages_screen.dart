import 'package:flutter/material.dart';

class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Futuramente virá da API
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
            'Conversas',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0A1C3B),
            ),
          ),

          const SizedBox(height: 8),

          const Text(
            '', //subtitulo aqui
            style: TextStyle(
              color: Color(0xFF6B7A99),
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
                    color: Color(0xFFEEF1F8),
                    borderRadius: BorderRadius.circular(48),
                  ),
                  child: const Icon(
                    Icons.chat_bubble_outline,
                    size: 42,
                    color: Color(0xFF6B7A99),
                  ),
                ),

                const SizedBox(height: 24),

                const Text(
                  'Nenhuma conversa iniciada',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0A1C3B),
                  ),
                ),

                const SizedBox(height: 12),

                const Text(
                  'Quando você solicitar atendimento a um escritório, suas conversas aparecerão aqui.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF6B7A99),
                    fontSize: 15,
                  ),
                ),

                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: () {
                    // depois vamos redirecionar para Home
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