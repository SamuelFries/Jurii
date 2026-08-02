import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/conversation.dart';
import 'package:jurii/models/report_reason.dart';
import 'package:jurii/screens/chat_screen.dart';
import 'package:jurii/theme/app_theme.dart';

const _demoConversation = Conversation(
  initials: 'EN',
  officeName: 'Escritório Novo',
  specialty: 'Direito Trabalhista',
  lastMessage: '',
  time: 'Agora',
  unreadCount: 0,
);

void main() {
  test('razões de denúncia espelham a whitelist do servidor', () {
    // A RPC report_conversation recusa qualquer valor fora desta lista
    // (migration 20260801120000). Se um lado mudar sem o outro, este teste
    // aponta o drift antes do usuário.
    expect(
      ReportReason.values.map((reason) => reason.databaseValue).toList(),
      ['conteudo_abusivo', 'golpe_ou_fraude', 'falsa_identidade', 'spam', 'outro'],
    );

    for (final reason in ReportReason.values) {
      expect(reason.label, isNotEmpty);
    }
  });

  testWidgets('conversa demo (sem id) não expõe denúncia/bloqueio', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const ChatScreen(conversation: _demoConversation, isLawyer: true),
      ),
    );
    await tester.pumpAndSettle();

    // Denunciar/bloquear só fazem sentido em conversa real no servidor.
    expect(find.byTooltip('Opções da conversa'), findsNothing);
  });
}
