import 'package:flutter/foundation.dart';

import 'chat_attachment.dart';
import 'lawyer_recommendation.dart';

enum MessageAuthor { me, other, system }

/// Até onde a mensagem chegou. Só aparece nas mensagens que EU enviei — saber
/// se o outro leu a própria mensagem não quer dizer nada.
enum MessageDeliveryStatus {
  /// O servidor tem a mensagem. Nada indica que o outro aparelho a viu.
  sent,

  /// O app de quem recebe carregou a lista de conversas depois dela existir.
  delivered,

  /// A conversa foi aberta por quem recebe.
  read;

  /// `read_at` implica `delivered_at` no banco, mas a ordem aqui também
  /// resolve o caso de uma linha antiga com só um dos dois preenchido.
  static MessageDeliveryStatus resolve({
    required bool delivered,
    required bool read,
  }) {
    if (read) return MessageDeliveryStatus.read;
    if (delivered) return MessageDeliveryStatus.delivered;
    return MessageDeliveryStatus.sent;
  }
}

class ChatMessage {
  final String id;
  final String conversationKey;
  final MessageAuthor author;
  final String text;
  final String time;
  final MessageDeliveryStatus status;
  final Map<String, dynamic> metadata;
  final ChatAttachment? attachment;

  const ChatMessage({
    required this.id,
    required this.conversationKey,
    required this.author,
    required this.text,
    required this.time,
    this.status = MessageDeliveryStatus.read,
    this.metadata = const {},
    this.attachment,
  });

  ChatMessage copyWith({
    String? id,
    String? conversationKey,
    MessageAuthor? author,
    String? text,
    String? time,
    MessageDeliveryStatus? status,
    Map<String, dynamic>? metadata,
    ChatAttachment? attachment,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      conversationKey: conversationKey ?? this.conversationKey,
      author: author ?? this.author,
      text: text ?? this.text,
      time: time ?? this.time,
      status: status ?? this.status,
      metadata: metadata ?? this.metadata,
      attachment: attachment ?? this.attachment,
    );
  }

  /// `true` quando trocar esta mensagem por [other] não mudaria um pixel.
  ///
  /// Existe por causa da confirmação de leitura: marcar uma conversa como
  /// vista gera UM evento de tempo real POR MENSAGEM, e todos voltam para a
  /// tela de quem acabou de ler. Só que o tique é desenhado apenas na própria
  /// mensagem — para as mensagens do outro, esses eventos não mudam nada, e
  /// redesenhar a lista inteira uma vez por evento é trabalho puro.
  bool rendersSameAs(ChatMessage other) {
    // O status só aparece na própria mensagem; na do outro ele é invisível.
    final statusIsVisible = author == MessageAuthor.me;

    return id == other.id &&
        author == other.author &&
        text == other.text &&
        time == other.time &&
        attachment?.id == other.attachment?.id &&
        (!statusIsVisible || status == other.status) &&
        mapEquals(metadata, other.metadata);
  }

  String? get caseRequestId => metadata['case_request_id'] as String?;

  String? get caseRequestStatus => metadata['request_status'] as String?;

  String? get caseRequestTitle => metadata['title'] as String?;

  String? get caseRequestArea => metadata['area'] as String?;

  bool get isCaseRequest {
    return metadata['type'] == 'case_request' && caseRequestId != null;
  }

  /// Sugestão de advogado enviada pelo escritório, quando a mensagem é uma.
  LawyerRecommendation? get lawyerRecommendation {
    return LawyerRecommendation.fromMetadata(metadata);
  }

  bool get hasAttachment {
    return attachment != null || metadata['type'] == 'chat_attachment';
  }

  bool get isPendingCaseRequest {
    return isCaseRequest && caseRequestStatus == 'pending';
  }
}
