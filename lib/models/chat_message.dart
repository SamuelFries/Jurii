import 'chat_attachment.dart';
import 'lawyer_recommendation.dart';

enum MessageAuthor { me, other, system }

class ChatMessage {
  final String id;
  final String conversationKey;
  final MessageAuthor author;
  final String text;
  final String time;
  final bool read;
  final Map<String, dynamic> metadata;
  final ChatAttachment? attachment;

  const ChatMessage({
    required this.id,
    required this.conversationKey,
    required this.author,
    required this.text,
    required this.time,
    this.read = true,
    this.metadata = const {},
    this.attachment,
  });

  ChatMessage copyWith({
    String? id,
    String? conversationKey,
    MessageAuthor? author,
    String? text,
    String? time,
    bool? read,
    Map<String, dynamic>? metadata,
    ChatAttachment? attachment,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      conversationKey: conversationKey ?? this.conversationKey,
      author: author ?? this.author,
      text: text ?? this.text,
      time: time ?? this.time,
      read: read ?? this.read,
      metadata: metadata ?? this.metadata,
      attachment: attachment ?? this.attachment,
    );
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
