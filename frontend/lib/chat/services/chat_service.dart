import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/config/app_config.dart';
import '../models/chat_group.dart';
import '../models/chat_message.dart';

class ChatService {
  static const String _baseUrl = AppConfig.chatEndpoint;

  // Helper to get headers with token
  static Future<Map<String, String>> _getHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }
    final token = await user.getIdToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // Create group
  static Future<ChatGroup> createGroup(String name, String? description) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$_baseUrl/groups'),
        headers: headers,
        body: json.encode({'name': name, 'description': description}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return ChatGroup.fromJson(data['group']);
        }
      }

      final error = json.decode(response.body)['error'];
      throw Exception(error ?? 'Failed to create group');
    } catch (e) {
      rethrow;
    }
  }

  // Get groups
  static Future<List<ChatGroup>> getGroups() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$_baseUrl/groups'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final List<dynamic> groupsJson = data['groups'] ?? [];
          return groupsJson.map((json) => ChatGroup.fromJson(json)).toList();
        }
      }

      throw Exception('Failed to load groups');
    } catch (e) {
      rethrow;
    }
  }

  // Send message
  static Future<ChatMessage> sendMessage(
    String groupId,
    String content, {
    String type = 'text',
  }) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$_baseUrl/messages'),
        headers: headers,
        body: json.encode({
          'groupId': groupId,
          'content': content,
          'type': type,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return ChatMessage.fromJson(data['message']);
        }
      }

      throw Exception('Failed to send message');
    } catch (e) {
      rethrow;
    }
  }

  // Get messages
  static Future<List<ChatMessage>> getMessages(
    String groupId, {
    int limit = 50,
  }) async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$_baseUrl/messages/$groupId?limit=$limit'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final List<dynamic> messagesJson = data['messages'] ?? [];
          return messagesJson
              .map((json) => ChatMessage.fromJson(json))
              .toList();
        }
      }

      throw Exception('Failed to load messages');
    } catch (e) {
      rethrow;
    }
  }
}
