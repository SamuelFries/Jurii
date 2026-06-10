enum MessageAuthor { me, other, system }

class ChatMessage {
  final String id;
  final String conversationKey;
  final MessageAuthor author;
  final String text;
  final String time;
  final bool read;

  const ChatMessage({
    required this.id,
    required this.conversationKey,
    required this.author,
    required this.text,
    required this.time,
    this.read = true,
  });
}
