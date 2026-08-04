import 'package:flutter/material.dart';

import '../models/chat_message.dart';

/// Tique de confirmação da própria mensagem: um risco (enviada), dois riscos
/// (entregue) e dois riscos coloridos (visualizada).
///
/// As cores vêm de fora porque o mesmo tique aparece em dois fundos bem
/// diferentes — o balão, que muda com o tema, e o véu escuro sobre a foto, que
/// não muda. Um par fixo aqui dentro ficaria ilegível num dos dois.
class MessageStatusCheck extends StatelessWidget {
  const MessageStatusCheck({
    super.key,
    required this.status,
    required this.pendingColor,
    required this.readColor,
    this.size = 14,
  });

  final MessageDeliveryStatus status;

  /// Cor de "enviada" e "entregue" — os dois estados que ainda não são notícia.
  final Color pendingColor;

  /// Cor de "visualizada", a única que precisa saltar aos olhos.
  final Color readColor;

  final double size;

  @override
  Widget build(BuildContext context) {
    final isRead = status == MessageDeliveryStatus.read;

    return Semantics(
      // Sem rótulo, um leitor de tela anuncia "ícone" — a informação inteira
      // do tique se perde para quem não enxerga a diferença entre um risco e
      // dois.
      label: switch (status) {
        MessageDeliveryStatus.sent => 'Enviada',
        MessageDeliveryStatus.delivered => 'Entregue',
        MessageDeliveryStatus.read => 'Visualizada',
      },
      child: Icon(
        status == MessageDeliveryStatus.sent ? Icons.done : Icons.done_all,
        size: size,
        color: isRead ? readColor : pendingColor,
      ),
    );
  }
}
