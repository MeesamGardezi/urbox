import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/app_config.dart';

/// Represents a team member in the company
class TeamMember {
  final String id;
  final String email;
  final String? displayName;
  final String companyId;
  final String role; // 'owner' or 'member'
  final List<String> assignedInboxIds; // Inbox IDs this member can access
  final String status; // 'pending', 'active', 'disabled'
  final String? invitedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  TeamMember({
    required this.id,
    required this.email,
    this.displayName,
    required this.companyId,
    required this.role,
    this.assignedInboxIds = const [],
    this.status = 'active',
    this.invitedBy,
    this.createdAt,
    this.updatedAt,
  });

  /// Check if user is an owner
  bool get isOwner => role == 'owner';

  /// Check if user is a team member
  bool get isMember => role == 'member';

  /// Check if the member has been activated
  bool get isActive => status == 'active';

  /// Check if the member is pending invite
  bool get isPending => status == 'pending';

  /// Get display name or email
  String get name => displayName ?? email;

  factory TeamMember.fromJson(Map<String, dynamic> json) {
    return TeamMember(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      displayName: json['displayName'],
      companyId: json['companyId'] ?? '',
      role: json['role'] ?? 'member',
      assignedInboxIds: List<String>.from(json['assignedInboxIds'] ?? []),
      status: json['status'] ?? 'active',
      invitedBy: json['invitedBy'],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'displayName': displayName,
      'companyId': companyId,
      'role': role,
      'assignedInboxIds': assignedInboxIds,
      'status': status,
      'invitedBy': invitedBy,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  TeamMember copyWith({
    String? id,
    String? email,
    String? displayName,
    String? companyId,
    String? role,
    List<String>? assignedInboxIds,
    String? status,
    String? invitedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TeamMember(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      companyId: companyId ?? this.companyId,
      role: role ?? this.role,
      assignedInboxIds: assignedInboxIds ?? this.assignedInboxIds,
      status: status ?? this.status,
      invitedBy: invitedBy ?? this.invitedBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
