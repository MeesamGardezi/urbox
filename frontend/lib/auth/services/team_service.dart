import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/config/app_config.dart';
import '../../core/models/team_member.dart';

/// Team Management API Service
///
/// Handles team invitations and member management
class TeamService {
  static const String _baseUrl = AppConfig.teamEndpoint;

  /// Send invitation to join team
  /// Returns: {success, inviteToken, emailSent, message}
  static Future<Map<String, dynamic>> sendInvitation({
    required String email,
    required String companyId,
    required String invitedBy,
    List<String> assignedInboxIds = const [],
  }) async {
    try {
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

      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }

  /// Get invitation details by token
  /// Returns: {email, companyName, inviterName, assignedInboxIds, expiresAt}
  static Future<Map<String, dynamic>> getInvitation(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/invite/$token'),
        headers: {'Content-Type': 'application/json'},
      );

      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }

  /// Check if an email has a pending invite
  /// Returns: {hasPendingInvite, companyName, inviterName, token}
  static Future<Map<String, dynamic>> checkPendingInvite(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/check-invite'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email.toLowerCase().trim()}),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {'hasPendingInvite': false, 'error': 'Failed to check invite'};
      }
    } catch (e) {
      // Return false instead of error to avoid disrupting signup flow
      return {'hasPendingInvite': false};
    }
  }

  /// Accept invitation and create account
  /// Returns: {success, customToken, userId, message}
  static Future<Map<String, dynamic>> acceptInvitation({
    required String token,
    required String password,
    required String displayName,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/accept-invite'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'token': token,
          'password': password,
          'displayName': displayName,
        }),
      );

      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }

  /// Update member inbox assignments
  static Future<Map<String, dynamic>> updateMemberInboxes({
    required String memberId,
    required List<String> inboxIds,
  }) async {
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

  /// Resend invitation email
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

  /// Remove a team member
  static Future<Map<String, dynamic>> removeMember(String memberId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/remove-member'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'memberId': memberId}),
      );

      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }

  /// Disable a team member
  static Future<Map<String, dynamic>> disableMember(String memberId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/disable-member'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'memberId': memberId}),
      );

      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }

  /// Enable a team member
  static Future<Map<String, dynamic>> enableMember(String memberId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/enable-member'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'memberId': memberId}),
      );

      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }

  /// Cancel a pending invitation
  static Future<Map<String, dynamic>> cancelInvite(String inviteId) async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/cancel-invite/$inviteId'),
        headers: {'Content-Type': 'application/json'},
      );

      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }

  /// Get team member details
  static Future<TeamMember> getMember(String uid) async {
    // Using Auth service endpoint as Team service doesn't have a direct member lookup
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.authEndpoint}/user/$uid'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['user'] != null) {
          return TeamMember.fromMap(data['user']);
        }
      }
      throw Exception('Failed to load member');
    } catch (e) {
      throw Exception('Error fetching member: $e');
    }
  }

  /// Get all team members for a company
  /// Returns a Stream to match usage in AddAssignmentDialog
  static Stream<List<TeamMember>> getTeamMembers(String companyId) async* {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/members/$companyId'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final List list = data['members'];
          yield list.map((m) => TeamMember.fromMap(m)).toList();
        } else {
          yield [];
        }
      } else {
        yield [];
      }
    } catch (e) {
      yield [];
    }
  }
}
