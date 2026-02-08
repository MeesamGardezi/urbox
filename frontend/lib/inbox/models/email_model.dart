class Email {
  final String id;
  final String messageId;
  final String threadId;
  final String accountName;
  final String accountType;
  final String subject;
  final String from;
  final String to;
  final DateTime date;
  final String text;
  final String html;
  bool isRead;
  final String snippet;
  final List<String> labels;
  final List<Attachment> attachments;

  Email({
    required this.id,
    required this.messageId,
    required this.threadId,
    required this.accountName,
    required this.accountType,
    required this.subject,
    required this.from,
    required this.to,
    required this.date,
    required this.text,
    required this.html,
    required this.isRead,
    required this.snippet,
    this.labels = const [],
    this.attachments = const [],
  });

  factory Email.fromJson(Map<String, dynamic> json) {
    return Email(
      id: json['id'] ?? '',
      messageId: json['messageId'] ?? '',
      threadId: json['threadId'] ?? '',
      accountName: json['accountName'] ?? '',
      accountType: json['accountType'] ?? '',
      subject: json['subject'] ?? '(No Subject)',
      from: json['from'] ?? 'Unknown',
      to: json['to'] ?? '',
      date: DateTime.tryParse(json['date'] ?? '') ?? DateTime.now(),
      text: json['text'] ?? '',
      html: json['html'] ?? '',
      isRead: json['isRead'] ?? false,
      snippet: json['snippet'] ?? '',
      labels: json['labels'] != null ? List<String>.from(json['labels']) : [],
      attachments: json['attachments'] != null
          ? (json['attachments'] as List)
                .map((x) => Attachment.fromJson(x))
                .toList()
          : [],
    );
  }

  /// Check if email belongs to a specific Gmail category
  bool hasCategory(String category) {
    return labels.any(
      (label) => label.toUpperCase().contains(category.toUpperCase()),
    );
  }

  /// Get the primary category for this email (for Gmail)
  String? get primaryCategory {
    const categories = [
      'CATEGORY_PERSONAL',
      'CATEGORY_SOCIAL',
      'CATEGORY_PROMOTIONS',
      'CATEGORY_UPDATES',
      'CATEGORY_FORUMS',
    ];
    for (var category in categories) {
      if (labels.contains(category)) {
        return category.replaceFirst('CATEGORY_', '');
      }
    }
    return null;
  }
}

class Attachment {
  final String filename;
  final String contentType;
  final int size;

  Attachment({
    required this.filename,
    required this.contentType,
    required this.size,
  });

  factory Attachment.fromJson(Map<String, dynamic> json) {
    return Attachment(
      filename: json['filename'] ?? 'Unnamed',
      contentType: json['contentType'] ?? 'application/octet-stream',
      size: json['size'] ?? 0,
    );
  }
}
