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

/// Service for managing team members - all via backend API
class TeamMemberService {
  static const String _baseUrl = AppConfig.teamEndpoint;

  /// Get all team members for a company
  static Future<List<TeamMember>> getTeamMembers(String companyId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/members/$companyId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final List<dynamic> membersJson = data['members'] ?? [];
          return membersJson.map((json) => TeamMember.fromJson(json)).toList();
        }
      }

      throw Exception('Failed to load team members');
    } catch (e) {
      rethrow;
    }
  }

  /// Get all pending invitations for a company
  static Future<List<TeamMember>> getPendingInvites(String companyId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/pending-invites/$companyId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final List<dynamic> invitesJson = data['invites'] ?? [];
          return invitesJson.map((json) => TeamMember.fromJson(json)).toList();
        }
      }

      throw Exception('Failed to load pending invites');
    } catch (e) {
      rethrow;
    }
  }

  /// Get invite token for a pending invitation
  static Future<Map<String, dynamic>> getInviteToken(String inviteId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/invite-token/$inviteId'),
        headers: {'Content-Type': 'application/json'},
      );

      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }

  /// Invite a new team member (sends email invitation via API)
  /// Returns a Map with 'success', 'emailSent', 'token', and 'message'
  static Future<Map<String, dynamic>> inviteMember({
    required String email,
    required String companyId,
    required String invitedBy,
    List<String> assignedInboxIds = const [],
  }) async {
    try {
      // Call the backend API to send invite email
      final response = await http.post(
        Uri.parse('$_baseUrl/invite'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email,
          'companyId': companyId,
          'invitedBy': invitedBy,
          'assignedInboxIds': assignedInboxIds,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'emailSent': data['emailSent'] ?? false,
          'token': data['inviteToken'],
          'message': data['message'] ?? 'Invitation sent',
        };
      } else {
        throw Exception(data['error'] ?? 'Failed to send invitation');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Update a team member's assigned inboxes
  static Future<Map<String, dynamic>> updateAssignedInboxes(
    String memberId,
    List<String> inboxIds,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/update-member-inboxes'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'memberId': memberId, 'inboxIds': inboxIds}),
      );

      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }

  /// Disable a team member
  static Future<void> disableMember(String memberId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/disable-member'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'memberId': memberId}),
      );

      final data = json.decode(response.body);
      if (data['success'] != true) {
        throw Exception(data['error'] ?? 'Failed to disable member');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Re-enable a team member
  static Future<void> enableMember(String memberId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/enable-member'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'memberId': memberId}),
      );

      final data = json.decode(response.body);
      if (data['success'] != true) {
        throw Exception(data['error'] ?? 'Failed to enable member');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Delete a team member (only for non-owner members)
  static Future<void> removeMember(String memberId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/remove-member'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'memberId': memberId}),
      );

      final data = json.decode(response.body);
      if (data['success'] != true) {
        throw Exception(data['error'] ?? 'Failed to remove member');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Cancel a pending invitation
  static Future<void> cancelInvite(String inviteId) async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/cancel-invite/$inviteId'),
        headers: {'Content-Type': 'application/json'},
      );

      final data = json.decode(response.body);
      if (data['success'] != true) {
        throw Exception(data['error'] ?? 'Failed to cancel invite');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Resend an invitation email
  static Future<Map<String, dynamic>> resendInvite(String inviteId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/resend-invite'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'inviteId': inviteId}),
      );

      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }
}
