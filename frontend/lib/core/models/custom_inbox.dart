class CustomInbox {
  final String id;
  final String name;
  final String companyId;
  final List<String> accountIds; // List of email account document IDs
  final List<String> whatsappGroupIds; // List of WhatsApp group IDs
  final List<String> slackChannelIds; // List of Slack channel IDs
  final Map<String, List<String>>
  accountFilters; // Map of accountId -> list of sender filters
  final int color; // Color value for the inbox icon
  final DateTime createdAt;
  final DateTime updatedAt;

  CustomInbox({
    required this.id,
    required this.name,
    required this.companyId,
    required this.accountIds,
    this.whatsappGroupIds = const [],
    this.slackChannelIds = const [],
    this.accountFilters = const {},
    this.color = 0xFF6366F1, // Default indigo
    required this.createdAt,
    required this.updatedAt,
  });

  factory CustomInbox.fromJson(Map<String, dynamic> json) {
    Map<String, List<String>> filters = {};
    if (json['accountFilters'] != null) {
      final filtersData = json['accountFilters'] as Map<String, dynamic>;
      filtersData.forEach((key, value) {
        filters[key] = List<String>.from(value as List);
      });
    }

    return CustomInbox(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      companyId: json['companyId'] ?? '',
      accountIds: List<String>.from(json['accountIds'] ?? []),
      whatsappGroupIds: List<String>.from(json['whatsappGroupIds'] ?? []),
      slackChannelIds: List<String>.from(json['slackChannelIds'] ?? []),
      accountFilters: filters,
      color: json['color'] ?? 0xFF6366F1,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'companyId': companyId,
      'accountIds': accountIds,
      'whatsappGroupIds': whatsappGroupIds,
      'slackChannelIds': slackChannelIds,
      'accountFilters': accountFilters,
      'color': color,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  CustomInbox copyWith({
    String? id,
    String? name,
    String? companyId,
    List<String>? accountIds,
    List<String>? whatsappGroupIds,
    List<String>? slackChannelIds,
    Map<String, List<String>>? accountFilters,
    int? color,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CustomInbox(
      id: id ?? this.id,
      name: name ?? this.name,
      companyId: companyId ?? this.companyId,
      accountIds: accountIds ?? this.accountIds,
      whatsappGroupIds: whatsappGroupIds ?? this.whatsappGroupIds,
      slackChannelIds: slackChannelIds ?? this.slackChannelIds,
      accountFilters: accountFilters ?? this.accountFilters,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
