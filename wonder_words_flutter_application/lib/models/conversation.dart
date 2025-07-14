class Conversation {
  final String id;
  final DateTime createdAt;
  final String preview;
  final int messageCount;

  Conversation({
    required this.id,
    required this.createdAt,
    required this.preview,
    required this.messageCount,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'].toString(),
      createdAt: DateTime.parse(json['created_at']),
      preview: json['preview'],
      messageCount: json['message_count'],
    );
  }
}

class Message {
  final String id;
  final SenderType senderType;
  final String content;
  final DateTime createdAt;
  final int code;

  Message({
    required this.id,
    required this.senderType,
    required this.content,
    required this.createdAt,
    required this.code,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'].toString(),
      senderType: SenderType.values.firstWhere(
        (e) => e.toString() == 'SenderType.${json['sender_type']}',
        orElse: () => SenderType.USER,
      ),
      content: json['content'],
      createdAt: DateTime.parse(json['created_at']),
      code: json['code'],
    );
  }
}

enum SenderType {
  USER,
  MODEL,
}
