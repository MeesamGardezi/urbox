enum MessageType { text, image, file }

class AssignmentMessage {
  final String id;
  final String assignmentId;
  final String senderId;
  final String senderName;
  final String content;
  final MessageType type;
  final String? fileUrl;
  final String? fileName;
  final DateTime timestamp;

  AssignmentMessage({
    required this.id,
    required this.assignmentId,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.type,
    this.fileUrl,
    this.fileName,
    required this.timestamp,
  });

  factory AssignmentMessage.fromJson(Map<String, dynamic> json) {
    return AssignmentMessage(
      id: json['id'] ?? '',
      assignmentId: json['assignmentId'] ?? '',
      senderId: json['senderId'] ?? '',
      senderName: json['senderName'] ?? 'Unknown',
      content: json['content'] ?? '',
      type: _parseType(json['type']),
      fileUrl: json['fileUrl'],
      fileName: json['fileName'],
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'assignmentId': assignmentId,
      'senderId': senderId,
      'senderName': senderName,
      'content': content,
      'type': type.name,
      'fileUrl': fileUrl,
      'fileName': fileName,
      // Timestamp handled by server mostly, but can send if needed
    };
  }

  static MessageType _parseType(String? type) {
    if (type == 'image') return MessageType.image;
    if (type == 'file') return MessageType.file;
    return MessageType.text;
  }
}
