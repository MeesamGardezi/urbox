class ChatMessage {
  final String id;
  final String groupId;
  final String senderId;
  final String senderName;
  final String content;
  final String type; // 'text', 'image', etc.
  final DateTime createdAt;
  final List<ChatAttachment> attachments;
  final List<ChatReaction> reactions;

  ChatMessage({
    required this.id,
    required this.groupId,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.type,
    required this.createdAt,
    this.attachments = const [],
    this.reactions = const [],
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] ?? '',
      groupId: json['groupId'] ?? '',
      senderId: json['senderId'] ?? '',
      senderName: json['senderName'] ?? 'Unknown',
      content: json['content'] ?? '',
      type: json['type'] ?? 'text',
      createdAt: json['createdAt'] != null
          ? (json['createdAt'] is String
                ? DateTime.tryParse(json['createdAt']) ?? DateTime.now()
                : (json['createdAt'] as dynamic).toDate())
          : DateTime.now(),
      attachments:
          (json['attachments'] as List<dynamic>?)
              ?.map((e) => ChatAttachment.fromJson(e))
              .toList() ??
          [],
      reactions:
          (json['reactions'] as List<dynamic>?)
              ?.map((e) => ChatReaction.fromJson(e))
              .toList() ??
          [],
    );
  }
}

class ChatAttachment {
  final String name;
  final String url;
  final String key;
  final String type;
  final int size;

  ChatAttachment({
    required this.name,
    required this.url,
    required this.key,
    required this.type,
    required this.size,
  });

  factory ChatAttachment.fromJson(Map<String, dynamic> json) {
    return ChatAttachment(
      name: json['name'] ?? '',
      url: json['url'] ?? '',
      key: json['key'] ?? '',
      type: json['type'] ?? '',
      size: json['size'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {'name': name, 'url': url, 'key': key, 'type': type, 'size': size};
  }
}

class ChatReaction {
  final String userId;
  final String userName;
  final String reaction;
  final DateTime timestamp;

  ChatReaction({
    required this.userId,
    required this.userName,
    required this.reaction,
    required this.timestamp,
  });

  factory ChatReaction.fromJson(Map<String, dynamic> json) {
    return ChatReaction(
      userId: json['userId'] ?? '',
      userName: json['userName'] ?? '',
      reaction: json['reaction'] ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp']) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
