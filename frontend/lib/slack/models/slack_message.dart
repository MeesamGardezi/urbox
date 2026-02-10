class SlackMessage {
  final String id;
  final String originalId;
  final String body;
  final DateTime timestamp;
  final String senderName;
  final String channelName;
  final String channelId;
  final String? accountName;
  final String teamId;
  final bool hasMedia;
  final String? mediaUrl;

  SlackMessage({
    required this.id,
    required this.originalId,
    required this.body,
    required this.timestamp,
    required this.senderName,
    required this.channelName,
    required this.channelId,
    this.accountName,
    required this.teamId,
    this.hasMedia = false,
    this.mediaUrl,
  });

  factory SlackMessage.fromJson(Map<String, dynamic> json) {
    return SlackMessage(
      id: json['id'] ?? '',
      originalId: json['originalId'] ?? '',
      body: json['body'] ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
      senderName: json['senderName'] ?? 'Unknown',
      channelName: json['channelName'] ?? '',
      channelId: json['channelId'] ?? '',
      accountName: json['accountName'],
      teamId: json['teamId'] ?? '',
      hasMedia: json['hasMedia'] == true,
      mediaUrl: json['mediaUrl'],
    );
  }
}
