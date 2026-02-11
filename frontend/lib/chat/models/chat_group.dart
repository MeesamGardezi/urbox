class ChatGroup {
  final String id;
  final String name;
  final String? description;
  final String companyId;
  final String createdBy;
  final DateTime createdAt;
  final String type; // 'public', 'private', etc.
  final DateTime? updatedAt;
  final Map<String, dynamic>? lastMessage;
  final List<String> members;

  ChatGroup({
    required this.id,
    required this.name,
    this.description,
    required this.companyId,
    required this.createdBy,
    required this.createdAt,
    required this.type,
    this.updatedAt,
    this.lastMessage,
    this.members = const [],
  });

  factory ChatGroup.fromJson(Map<String, dynamic> json) {
    return ChatGroup(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      companyId: json['companyId'] ?? '',
      createdBy: json['createdBy'] ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt']) ?? DateTime.now()
          : DateTime.now(),
      type: json['type'] ?? 'public',
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'])
          : null,
      lastMessage: json['lastMessage'],
      members: List<String>.from(json['members'] ?? []),
    );
  }
}
