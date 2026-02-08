import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../core/models/team_member.dart';

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
