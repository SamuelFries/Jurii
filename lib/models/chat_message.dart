enum MessageAuthor { me, other, system }

class ChatMessage {
  final String id;
  final String conversationKey;
  final MessageAuthor author;
  final String text;
  final String time;
  final bool read;
  final Map<String, dynamic> metadata;

  const ChatMessage({
    required this.id,
    required this.conversationKey,
    required this.author,
    required this.text,
    required this.time,
    this.read = true,
    this.metadata = const {},
  });

  String? get caseRequestId => metadata['case_request_id'] as String?;

  String? get caseRequestStatus => metadata['request_status'] as String?;

  String? get caseRequestTitle => metadata['title'] as String?;

  String? get caseRequestArea => metadata['area'] as String?;

  bool get isCaseRequest {
    return metadata['type'] == 'case_request' && caseRequestId != null;
  }

  bool get isPendingCaseRequest {
    return isCaseRequest && caseRequestStatus == 'pending';
  }
}
