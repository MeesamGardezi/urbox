import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/config/app_config.dart';
import '../../core/models/custom_inbox.dart';

class CustomInboxService {
  static const String _baseUrl = AppConfig.customInboxEndpoint;

  /// Get all custom inboxes for a company
  static Future<List<CustomInbox>> getInboxes(String companyId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/company/$companyId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        return jsonList.map((json) => CustomInbox.fromJson(json)).toList();
      }

      throw Exception('Failed to load inboxes');
    } catch (e) {
      rethrow;
    }
  }

  /// Create a new custom inbox
  static Future<CustomInbox> createInbox({
    required String name,
    required String companyId,
    required List<String> accountIds,
    List<String> whatsappGroupIds = const [],
    List<String> slackChannelIds = const [],
    Map<String, List<String>> accountFilters = const {},
    int color = 0xFF6366F1,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'name': name,
          'companyId': companyId,
          'accountIds': accountIds,
          'whatsappGroupIds': whatsappGroupIds,
          'slackChannelIds': slackChannelIds,
          'accountFilters': accountFilters,
          'color': color,
        }),
      );

      if (response.statusCode == 201) {
        return CustomInbox.fromJson(json.decode(response.body));
      }

      throw Exception('Failed to create inbox');
    } catch (e) {
      rethrow;
    }
  }

  /// Update an existing custom inbox
  static Future<void> updateInbox(CustomInbox inbox) async {
    try {
      final response = await http.put(
        Uri.parse('$_baseUrl/${inbox.id}'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'name': inbox.name,
          'accountIds': inbox.accountIds,
          'whatsappGroupIds': inbox.whatsappGroupIds,
          'slackChannelIds': inbox.slackChannelIds,
          'accountFilters': inbox.accountFilters,
          'color': inbox.color,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to update inbox');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Delete a custom inbox
  static Future<void> deleteInbox(String inboxId) async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/$inboxId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to delete inbox');
      }
    } catch (e) {
      rethrow;
    }
  }
}
