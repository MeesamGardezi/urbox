class ChatMessage {
  final String id;
  final String groupId;
  final String senderId;
  final String senderName;
  final String content;
  final String type; // 'text', 'image', etc.
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.groupId,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.type,
    required this.createdAt,
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
          ? DateTime.tryParse(json['createdAt']) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
