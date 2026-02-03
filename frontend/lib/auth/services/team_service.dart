import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/config/app_config.dart';

/// Team Management API Service
///
/// Handles team invitations and member management
class TeamService {
  static const String _baseUrl = '${AppConfig.teamEndpoint}';

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
}
