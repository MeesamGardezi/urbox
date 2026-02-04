import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/config/app_config.dart';

/// Authentication API Service
///
/// Handles all authentication-related API calls
class AuthService {
  static const String _baseUrl = '${AppConfig.authEndpoint}';

  /// Sign up new user
  /// Returns: {success, customToken, userId, companyId, role, message}
  static Future<Map<String, dynamic>> signup({
    required String email,
    required String password,
    required String displayName,
    String? companyName, // Required if no invite exists
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/signup'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email,
          'password': password,
          'displayName': displayName,
          'companyName': companyName,
        }),
      );

      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }

  /// Login existing user
  /// Returns: {success, customToken, userId, companyId, role}
  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email, 'password': password}),
      );

      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }

  /// Update user profile
  static Future<Map<String, dynamic>> updateProfile({
    required String userId,
    String? displayName,
    String? phoneNumber,
    String? timezone,
    String? language,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/update-profile'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'userId': userId,
          'displayName': displayName,
          'phoneNumber': phoneNumber,
          'timezone': timezone,
          'language': language,
        }),
      );

      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }

  /// Get user profile by ID
  static Future<Map<String, dynamic>> getUserProfile(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/user/$userId'),
        headers: {'Content-Type': 'application/json'},
      );

      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }

  /// Update user preferences
  static Future<Map<String, dynamic>> updatePreferences({
    required String userId,
    Map<String, dynamic>? preferences,
    bool? emailNotifications,
    bool? pushNotifications,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/update-preferences'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'userId': userId,
          'preferences': preferences,
          'emailNotifications': emailNotifications,
          'pushNotifications': pushNotifications,
        }),
      );

      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }

  /// Delete account
  static Future<Map<String, dynamic>> deleteAccount(String userId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/delete-account'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'userId': userId}),
      );

      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }

  /// Change password
  static Future<Map<String, dynamic>> changePassword({
    required String userId,
    required String newPassword,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/change-password'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'userId': userId, 'newPassword': newPassword}),
      );

      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }
}
