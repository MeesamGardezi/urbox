import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../../core/config/app_config.dart';
import '../models/chat_group.dart';
import '../models/chat_message.dart';

class ChatService {
  static const String _baseUrl = AppConfig.chatEndpoint;
  static IO.Socket? _socket;

  // Stream controllers for real-time updates
  static final _messageController = StreamController<ChatMessage>.broadcast();
  static final _reactionController =
      StreamController<Map<String, dynamic>>.broadcast();

  static Stream<ChatMessage> get messageStream => _messageController.stream;
  static Stream<Map<String, dynamic>> get reactionStream =>
      _reactionController.stream;

  // Initialize Socket.IO
  static void initSocket() {
    if (_socket != null && _socket!.connected) return;

    // Use the backend URL (assumed to be the same host just different port/path)
    // Adjust if necessary based on AppConfig.apiBaseUrl
    final socketUrl = AppConfig.apiBaseUrl;

    _socket = IO.io(
      socketUrl,
      IO.OptionBuilder()
          .setTransports(['websocket']) // for Flutter or Dart VM
          .enableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) {
      print('Socket connected');
    });

    _socket!.onDisconnect((_) => print('Socket disconnected'));

    _socket!.on('new_message', (data) {
      try {
        if (data != null) {
          final message = ChatMessage.fromJson(data);
          _messageController.add(message);
        }
      } catch (e) {
        print('Error parsing new message: $e');
      }
    });

    _socket!.on('reaction_update', (data) {
      if (data != null) {
        _reactionController.add(Map<String, dynamic>.from(data));
      }
    });
  }

  static void joinGroup(String groupId) {
    _socket?.emit('join_group', groupId);
  }

  static void leaveGroup(String groupId) {
    _socket?.emit('leave_group', groupId);
  }

  static void dispose() {
    _socket?.disconnect();
    _socket = null;
    _messageController.close();
    _reactionController.close();
  }

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

  // Get single group
  static Future<ChatGroup> getGroup(String groupId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$_baseUrl/groups/$groupId'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return ChatGroup.fromJson(data['group']);
        }
      }

      throw Exception('Failed to load group');
    } catch (e) {
      rethrow;
    }
  }

  // Upload attachment
  static Future<ChatAttachment> uploadAttachment(
    PlatformFile file,
    String groupId,
  ) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');
      final token = await user.getIdToken();

      final uri = Uri.parse('$_baseUrl/messages/upload');
      final request = http.MultipartRequest('POST', uri);

      request.headers['Authorization'] = 'Bearer $token';
      request.fields['groupId'] = groupId;

      if (file.bytes != null) {
        // Web or memory
        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            file.bytes!,
            filename: file.name,
          ),
        );
      } else if (file.path != null) {
        // Mobile/Desktop with path
        request.files.add(
          await http.MultipartFile.fromPath(
            'file',
            file.path!,
            filename: file.name,
          ),
        );
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return ChatAttachment.fromJson(data['attachment']);
        }
      }
      throw Exception('Failed to upload attachment: ${response.body}');
    } catch (e) {
      throw Exception('Failed to upload attachment: $e');
    }
  }

  // Send message
  static Future<ChatMessage> sendMessage(
    String groupId,
    String content, {
    String type = 'text',
    List<ChatAttachment> attachments = const [],
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
          'attachments': attachments.map((e) => e.toJson()).toList(),
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return ChatMessage.fromJson(data['message']);
        }
      }

      throw Exception('Failed to send message: ${response.body}');
    } catch (e) {
      rethrow;
    }
  }

  // Send reaction
  static Future<void> sendReaction(String messageId, String reaction) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$_baseUrl/messages/$messageId/reactions'),
        headers: headers,
        body: json.encode({'reaction': reaction}),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to send reaction');
      }
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

  // Add members to group
  static Future<void> addMembers(String groupId, List<String> memberIds) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$_baseUrl/groups/$groupId/members'),
        headers: headers,
        body: json.encode({'memberIds': memberIds}),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to add members');
      }
    } catch (e) {
      rethrow;
    }
  }

  // Remove member from group
  static Future<void> removeMember(String groupId, String userId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.delete(
        Uri.parse('$_baseUrl/groups/$groupId/members/$userId'),
        headers: headers,
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to remove member');
      }
    } catch (e) {
      rethrow;
    }
  }
}
