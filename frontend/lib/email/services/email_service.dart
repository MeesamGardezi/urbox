import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/config/app_config.dart';

class EmailService {
  /// Test IMAP connection
  Future<Map<String, dynamic>> testImapConnection(
    String host,
    int port,
    String email,
    String password,
    bool useTls,
  ) async {
    try {
      final response = await http.post(
        Uri.parse(AppConfig.imapTestEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'host': host,
          'port': port,
          'email': email,
          'password': password,
          'tls': useTls,
        }),
      );

      final data = jsonDecode(response.body);
      return data;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Add IMAP account
  Future<Map<String, dynamic>> addImapAccount(
    String companyId,
    String userId,
    String name,
    String host,
    int port,
    String email,
    String password,
    bool useTls,
  ) async {
    try {
      final response = await http.post(
        Uri.parse(AppConfig.imapAddEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'companyId': companyId,
          'userId': userId,
          'name': name,
          'host': host,
          'port': port,
          'email': email,
          'password': password,
          'tls': useTls,
        }),
      );

      final data = jsonDecode(response.body);
      return data;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// List email accounts
  Future<List<dynamic>> getEmailAccounts({
    String? companyId,
    String? userId,
  }) async {
    try {
      var url = AppConfig.emailAccountsEndpoint;
      if (companyId != null) {
        url += '?companyId=$companyId';
      } else if (userId != null) {
        url += '?userId=$userId';
      } else {
        throw Exception('CompanyId or UserId required');
      }

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      } else {
        throw Exception('Failed to load accounts: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to load accounts: $e');
    }
  }

  /// Delete an email account
  Future<bool> deleteAccount(String accountId) async {
    try {
      final response = await http.delete(
        Uri.parse('${AppConfig.emailAccountsEndpoint}/$accountId'),
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Fetch emails
  Future<Map<String, dynamic>> fetchEmails(
    List<dynamic> accounts, {
    Map<String, dynamic>? offsets,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(AppConfig.emailEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'accounts': accounts, 'offsets': offsets ?? {}}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to load emails: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to fetch emails: $e');
    }
  }

  Future<void> markAsRead(
    String id,
    Map<String, dynamic> account,
    String? messageId,
    String? uid,
  ) async {
    try {
      // Assuming endpoint exists or I need to create it in backend
      // shared_mailbooox used AppConfig.emailReadEndpoint(id)
      await http.post(
        Uri.parse('${AppConfig.apiBaseUrl}/email/$id/read'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'account': account,
          'messageId': messageId,
          'uid': uid,
        }),
      );
    } catch (e) {
      // Silently fail read receipts
    }
  }
}
