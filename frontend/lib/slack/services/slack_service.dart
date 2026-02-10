import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/config/app_config.dart';

class SlackService {
  String get _rootUrl => '${AppConfig.apiBaseUrl}/api/slack';

  Future<List<dynamic>> getSlackAccounts({
    String? companyId,
    String? userId,
  }) async {
    try {
      var url = '$_rootUrl/accounts';
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
        throw Exception(
          'Failed to load slack accounts: ${response.statusCode}',
        );
      }
    } catch (e) {
      throw Exception('Failed to load slack accounts: $e');
    }
  }

  Future<void> deleteAccount(String id) async {
    try {
      final response = await http.delete(Uri.parse('$_rootUrl/accounts/$id'));

      if (response.statusCode != 200) {
        throw Exception('Failed to delete account: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to delete account: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getChannels(String accountId) async {
    try {
      final response = await http.get(
        Uri.parse('$_rootUrl/channels?accountId=$accountId'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['channels']);
      } else {
        throw Exception('Failed to load channels: ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to load channels: $e');
    }
  }

  Future<void> saveTrackedChannels(
    String accountId,
    List<Map<String, dynamic>> channels,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$_rootUrl/channels/track'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'accountId': accountId, 'channels': channels}),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to save tracked channels: ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to save tracked channels: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getMessages({
    required String companyId,
    int limit = 20,
    String? before,
  }) async {
    try {
      var url = '$_rootUrl/messages?companyId=$companyId&limit=$limit';
      if (before != null) {
        url += '&before=$before';
      }

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['messages']);
      } else {
        throw Exception('Failed to load messages: ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to load messages: $e');
    }
  }
}
