import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/config/app_config.dart';
import '../models/whatsapp_model.dart';

/// WhatsApp Service
///
/// Handles all WhatsApp API calls with smart caching
/// No real-time subscriptions - poll on demand only
class WhatsAppService {
  // Cache
  final Map<String, List<WhatsAppMessage>> _messagesCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  final Map<String, WhatsAppSessionStatus> _statusCache = {};

  // Cache duration (30 seconds)
  static const Duration _cacheDuration = Duration(seconds: 30);

  /// Get WhatsApp connection status
  Future<WhatsAppSessionStatus> getStatus(String userId) async {
    // Check cache first
    final cached = _statusCache[userId];
    if (cached != null) {
      final cacheAge = DateTime.now().difference(cached.lastUpdated);
      if (cacheAge < _cacheDuration) {
        return cached;
      }
    }

    try {
      final response = await http
          .get(Uri.parse(AppConfig.whatsappStatus(userId)))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Handle both old and new response formats
        final statusData = data['data'] ?? data;

        final status = WhatsAppSessionStatus.fromJson(statusData);

        // Update cache
        _statusCache[userId] = status;

        return status;
      }

      throw Exception('Failed to get status: ${response.statusCode}');
    } catch (e) {
      print('[WhatsAppService] Error getting status: $e');
      rethrow;
    }
  }

  /// Get QR code for scanning
  Future<String?> getQrCode(String userId) async {
    try {
      final response = await http
          .get(Uri.parse(AppConfig.whatsappQr(userId)))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Handle error response
        if (data['success'] == false) {
          print('[WhatsAppService] QR code not available: ${data['error']}');
          return null;
        }

        return data['qrCode'] as String?;
      }

      return null;
    } catch (e) {
      print('[WhatsAppService] Error getting QR code: $e');
      return null;
    }
  }

  /// Start WhatsApp session
  Future<Map<String, dynamic>> connect(String userId, String companyId) async {
    try {
      final response = await http
          .post(
            Uri.parse(AppConfig.whatsappConnect),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'userId': userId, 'companyId': companyId}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Clear status cache to force refresh
        _statusCache.remove(userId);

        return {
          'success': data['success'] == true,
          'message': data['message'] ?? 'Connection started',
          'error': data['error'],
        };
      }

      return {
        'success': false,
        'error': 'Server returned ${response.statusCode}',
      };
    } catch (e) {
      print('[WhatsAppService] Error connecting: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Disconnect WhatsApp session
  Future<bool> disconnect(String userId, {bool deleteAuth = true}) async {
    try {
      final response = await http
          .post(
            Uri.parse(AppConfig.whatsappDisconnect),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'userId': userId, 'deleteAuth': deleteAuth}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Clear cache on disconnect
        _statusCache.remove(userId);
        _messagesCache.remove(userId);
        _cacheTimestamps.remove(userId);

        return data['success'] == true;
      }

      return false;
    } catch (e) {
      print('[WhatsAppService] Error disconnecting: $e');
      return false;
    }
  }

  /// Cancel a pending WhatsApp connection
  /// This is used during QR code scanning phase
  Future<bool> cancelConnection(String userId) async {
    try {
      final response = await http
          .post(
            Uri.parse(AppConfig.whatsappCancel),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'userId': userId}),
          )
          .timeout(const Duration(seconds: 10));

      // Clear cache
      _statusCache.remove(userId);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }

      return false;
    } catch (e) {
      print('[WhatsAppService] Error cancelling connection: $e');
      return false;
    }
  }

  /// Get available WhatsApp groups
  Future<List<WhatsAppGroup>> getGroups(String userId) async {
    try {
      final response = await http
          .get(Uri.parse(AppConfig.whatsappGroups(userId)))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == false) {
          throw Exception(data['error'] ?? 'Failed to get groups');
        }

        final groupsJson = data['groups'] as List;
        return groupsJson.map((json) => WhatsAppGroup.fromJson(json)).toList();
      }

      throw Exception('Failed to get groups: ${response.statusCode}');
    } catch (e) {
      print('[WhatsAppService] Error getting groups: $e');
      return [];
    }
  }

  /// Get monitored groups
  Future<List<WhatsAppGroup>> getMonitoredGroups(String userId) async {
    try {
      final response = await http
          .get(Uri.parse(AppConfig.whatsappMonitored(userId)))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == false) {
          print(
            '[WhatsAppService] Error getting monitored groups: ${data['error']}',
          );
          return [];
        }

        final groupsJson = data['groups'] as List;
        return groupsJson
            .map(
              (json) => WhatsAppGroup.fromJson({
                'id': json['groupId'],
                'name': json['groupName'],
                'isMonitored': json['isMonitoring'] ?? true,
              }),
            )
            .toList();
      }

      return [];
    } catch (e) {
      print('[WhatsAppService] Error getting monitored groups: $e');
      return [];
    }
  }

  /// Toggle group monitoring
  Future<bool> toggleMonitoring({
    required String userId,
    required String companyId,
    required String groupId,
    required String groupName,
    required bool isMonitoring,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(AppConfig.whatsappMonitor),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userId': userId,
              'companyId': companyId,
              'groupId': groupId,
              'groupName': groupName,
              'isMonitoring': isMonitoring,
            }),
          )
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      print('[WhatsAppService] Error toggling monitoring: $e');
      return false;
    }
  }

  /// Get messages with caching
  /// Returns { 'messages': List<WhatsAppMessage>, 'hasMore': bool, 'lastDocId': String? }
  Future<Map<String, dynamic>> getMessages({
    String? userId,
    String? companyId,
    String? groupId,
    String? searchQuery,
    int limit = 50,
    String? startAfter,
    bool forceRefresh = false,
  }) async {
    final cacheKey =
        '${userId ?? companyId ?? 'unknown'}_${groupId ?? 'all'}_${searchQuery ?? ''}';

    // Check cache if not forcing refresh and no pagination (startAfter is null)
    if (!forceRefresh && startAfter == null) {
      final cached = _messagesCache[cacheKey];
      final cacheTime = _cacheTimestamps[cacheKey];

      if (cached != null && cacheTime != null) {
        final cacheAge = DateTime.now().difference(cacheTime);
        if (cacheAge < _cacheDuration) {
          print(
            '[WhatsAppService] Returning cached messages (age: ${cacheAge.inSeconds}s)',
          );
          // Note: Cached version doesn't store hasMore/lastDocId, assuming false/null for cache hits
          // or we could change cache structure. For now, let's just make network call if we need pagination.
          // But to be safe, if we return from cache, we might lose pagination context.
          // Let's only cache the initial load.
          return {
            'messages': cached,
            'hasMore': false, // We don't know from simple list cache
            'lastDocId': null,
          };
        }
      }
    }

    try {
      final response = await http
          .get(
            Uri.parse(
              AppConfig.whatsappMessages(
                userId: userId,
                companyId: companyId,
                groupId: groupId,
                limit: limit,
                startAfter: startAfter,
                searchQuery: searchQuery,
              ),
            ),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == false) {
          throw Exception(data['error'] ?? 'Failed to get messages');
        }

        final messagesJson = data['messages'] as List;
        final messages = messagesJson
            .map((json) => WhatsAppMessage.fromJson(json))
            .toList();

        // Update cache only for initial load
        if (startAfter == null) {
          _messagesCache[cacheKey] = messages;
          _cacheTimestamps[cacheKey] = DateTime.now();
        }

        print('[WhatsAppService] Fetched ${messages.length} messages');
        return {
          'messages': messages,
          'hasMore': data['hasMore'] ?? false,
          'lastDocId': data['lastDocId'],
        };
      }

      throw Exception('Failed to get messages: ${response.statusCode}');
    } catch (e) {
      print('[WhatsAppService] Error getting messages: $e');

      // Return cached data on error if available and it's an initial load
      if (startAfter == null && _messagesCache.containsKey(cacheKey)) {
        return {
          'messages': _messagesCache[cacheKey] ?? [],
          'hasMore': false,
          'lastDocId': null,
        };
      }

      // Otherwise rethrow or return empty
      return {
        'messages': <WhatsAppMessage>[],
        'hasMore': false,
        'lastDocId': null,
      };
    }
  }

  /// Get unread message count
  Future<int> getMessageCount({required String userId, String? since}) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              AppConfig.whatsappMessageCount(userId: userId, since: since),
            ),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == false) {
          return 0;
        }

        return data['count'] as int? ?? 0;
      }

      return 0;
    } catch (e) {
      print('[WhatsAppService] Error getting message count: $e');
      return 0;
    }
  }

  /// Clear cache for a user
  void clearCache(String userId) {
    _statusCache.remove(userId);
    _messagesCache.removeWhere((key, _) => key.startsWith(userId));
    _cacheTimestamps.removeWhere((key, _) => key.startsWith(userId));
  }

  /// Clear all caches
  void clearAllCache() {
    _statusCache.clear();
    _messagesCache.clear();
    _cacheTimestamps.clear();
  }
}

/// WhatsApp Session Status Model
class WhatsAppSessionStatus {
  final String
  status; // 'disconnected', 'initializing', 'qr_pending', 'authenticating', 'connected', 'error'
  final String? phone;
  final String? name;
  final String? qrCode;
  final String? error;
  final String? disconnectReason;
  final DateTime? connectedAt;
  final DateTime lastUpdated;

  WhatsAppSessionStatus({
    required this.status,
    this.phone,
    this.name,
    this.qrCode,
    this.error,
    this.disconnectReason,
    this.connectedAt,
    required this.lastUpdated,
  });

  factory WhatsAppSessionStatus.fromJson(Map<String, dynamic> json) {
    return WhatsAppSessionStatus(
      status: json['status'] as String? ?? 'disconnected',
      phone: json['phone'] as String?,
      name: json['name'] as String?,
      qrCode: json['qrCode'] as String?,
      error: json['error'] as String?,
      disconnectReason: json['disconnectReason'] as String?,
      connectedAt: json['connectedAt'] != null
          ? DateTime.parse(json['connectedAt'] as String)
          : null,
      lastUpdated: DateTime.now(),
    );
  }

  bool get isConnected => status == 'connected';
  bool get isConnecting =>
      status == 'initializing' ||
      status == 'qr_pending' ||
      status == 'authenticating';
  bool get isDisconnected => status == 'disconnected';
  bool get hasError => status == 'error';
  bool get needsQr => status == 'qr_pending';

  String get statusMessage {
    switch (status) {
      case 'connected':
        return 'Connected as ${name ?? phone ?? 'Unknown'}';
      case 'initializing':
        return 'Initializing WhatsApp connection...';
      case 'qr_pending':
        return 'Scan QR code with WhatsApp';
      case 'authenticating':
        return 'Authenticating...';
      case 'error':
        return error ?? 'Connection error';
      case 'disconnected':
        return disconnectReason ?? 'Disconnected';
      default:
        return status;
    }
  }
}
