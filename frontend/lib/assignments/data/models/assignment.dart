enum AssignmentStatus { pending, in_progress, completed }

class Assignment {
  final String id;
  final String title;
  final String description;
  final String assignedTo;
  final String assignedToName;
  final String assignedBy;
  final String assignedByName;
  final String companyId;
  final AssignmentStatus status;
  final DateTime? targetDate;
  final DateTime assignedDate;
  final DateTime updatedAt;

  Assignment({
    required this.id,
    required this.title,
    this.description = '',
    required this.assignedTo,
    required this.assignedToName,
    required this.assignedBy,
    required this.assignedByName,
    required this.companyId,
    this.status = AssignmentStatus.pending,
    this.targetDate,
    required this.assignedDate,
    required this.updatedAt,
  });

  factory Assignment.fromJson(Map<String, dynamic> json) {
    return Assignment(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      assignedTo: json['assignedTo'] ?? '',
      assignedToName: json['assignedToName'] ?? 'Member',
      assignedBy: json['assignedBy'] ?? '',
      assignedByName: json['assignedByName'] ?? 'Admin',
      companyId: json['companyId'] ?? '',
      status: _parseStatus(json['status']),
      targetDate: json['targetDate'] != null
          ? DateTime.parse(json['targetDate'])
          : null,
      assignedDate: json['assignedDate'] != null
          ? DateTime.parse(json['assignedDate'])
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'title': title,
      'description': description,
      'assignedTo': assignedTo,
      'assignedToName': assignedToName,
      'assignedBy': assignedBy,
      'assignedByName': assignedByName,
      'companyId': companyId,
      'status': status.name,
      'targetDate': targetDate?.toIso8601String(),
      'assignedDate': assignedDate.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static AssignmentStatus _parseStatus(String? status) {
    if (status == 'in_progress') return AssignmentStatus.in_progress;
    if (status == 'completed') return AssignmentStatus.completed;
    return AssignmentStatus.pending;
  }

  String get statusDisplay {
    switch (status) {
      case AssignmentStatus.pending:
        return 'Pending';
      case AssignmentStatus.in_progress:
        return 'In Works';
      case AssignmentStatus.completed:
        return 'Completed';
    }
  }
}
