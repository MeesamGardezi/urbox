/// WhatsApp Message Model
class WhatsAppMessage {
  final String id;
  final String userId;
  final String companyId;
  final String groupId;
  final String groupName;
  final String senderName;
  final String senderNumber;
  final String body;
  final bool hasMedia;
  final String? mediaType;
  final bool isFromMe;
  final DateTime timestamp;
  final DateTime createdAt;

  WhatsAppMessage({
    required this.id,
    required this.userId,
    required this.companyId,
    required this.groupId,
    required this.groupName,
    required this.senderName,
    required this.senderNumber,
    required this.body,
    required this.hasMedia,
    this.mediaType,
    this.isFromMe = false,
    required this.timestamp,
    required this.createdAt,
  });

  factory WhatsAppMessage.fromJson(Map<String, dynamic> json) {
    return WhatsAppMessage(
      id: json['id'] as String,
      userId: json['userId'] as String,
      companyId: json['companyId'] as String,
      groupId: json['groupId'] as String,
      groupName: json['groupName'] as String,
      senderName: json['senderName'] as String,
      senderNumber: json['senderNumber'] as String,
      body: json['body'] as String,
      hasMedia: json['hasMedia'] as bool,
      mediaType: json['mediaType'] as String?,
      isFromMe: json['isFromMe'] as bool? ?? false,
      timestamp: DateTime.parse(json['timestamp'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'companyId': companyId,
      'groupId': groupId,
      'groupName': groupName,
      'senderName': senderName,
      'senderNumber': senderNumber,
      'body': body,
      'hasMedia': hasMedia,
      'mediaType': mediaType,
      'isFromMe': isFromMe,
      'timestamp': timestamp.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  WhatsAppMessage copyWith({
    String? id,
    String? userId,
    String? companyId,
    String? groupId,
    String? groupName,
    String? senderName,
    String? senderNumber,
    String? body,
    bool? hasMedia,
    String? mediaType,
    bool? isFromMe,
    DateTime? timestamp,
    DateTime? createdAt,
  }) {
    return WhatsAppMessage(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      companyId: companyId ?? this.companyId,
      groupId: groupId ?? this.groupId,
      groupName: groupName ?? this.groupName,
      senderName: senderName ?? this.senderName,
      senderNumber: senderNumber ?? this.senderNumber,
      body: body ?? this.body,
      hasMedia: hasMedia ?? this.hasMedia,
      mediaType: mediaType ?? this.mediaType,
      isFromMe: isFromMe ?? this.isFromMe,
      timestamp: timestamp ?? this.timestamp,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// WhatsApp Group Model
class WhatsAppGroup {
  final String id;
  final String name;
  final int? participantCount;
  final bool isMonitored;

  WhatsAppGroup({
    required this.id,
    required this.name,
    this.participantCount,
    this.isMonitored = false,
  });

  factory WhatsAppGroup.fromJson(Map<String, dynamic> json) {
    return WhatsAppGroup(
      id: json['id'] as String,
      name: json['name'] as String,
      participantCount: json['participantCount'] as int?,
      isMonitored: json['isMonitored'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'participantCount': participantCount,
      'isMonitored': isMonitored,
    };
  }

  WhatsAppGroup copyWith({
    String? id,
    String? name,
    int? participantCount,
    bool? isMonitored,
  }) {
    return WhatsAppGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      participantCount: participantCount ?? this.participantCount,
      isMonitored: isMonitored ?? this.isMonitored,
    );
  }
}
