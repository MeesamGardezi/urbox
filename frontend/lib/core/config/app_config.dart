/// Application Configuration
///
/// Centralized configuration for API endpoints and app settings
class AppConfig {
  // ============================================================================
  // API CONFIGURATION
  // ============================================================================

  /// Base URL for the backend API
  static const String apiBaseUrl = 'https://api.urbox.ai';
  // static const String apiBaseUrl = 'http://localhost:3000';

  /// API Endpoints
  static const String authEndpoint = '$apiBaseUrl/api/auth';
  static const String teamEndpoint = '$apiBaseUrl/api/team';
  static const String subscriptionEndpoint = '$apiBaseUrl/api/subscription';
  static const String paymentEndpoint = '$apiBaseUrl/api/payment';
  static const String whatsappEndpoint = '$apiBaseUrl/api/whatsapp';

  /// Custom Inbox API Endpoints
  static const String customInboxEndpoint = '$apiBaseUrl/api/custom-inbox';

  /// Email API Endpoints
  static const String emailEndpoint = '$apiBaseUrl/api/email';

  /// Google OAuth URL
  static String googleAuthUrl(String companyId, String userId) =>
      '$emailEndpoint/auth/google?companyId=$companyId&userId=$userId';

  /// Microsoft OAuth URL
  static String microsoftAuthUrl(String companyId, String userId) =>
      '$emailEndpoint/auth/microsoft?companyId=$companyId&userId=$userId';

  /// IMAP Add Account endpoint
  static String get imapAddEndpoint => '$emailEndpoint/imap/add';

  /// IMAP Test Connection endpoint
  static String get imapTestEndpoint => '$emailEndpoint/imap/test';

  static String get slackEndpoint => '$apiBaseUrl/api/slack';
  static String get slackAccountsEndpoint => '$slackEndpoint/accounts';

  static String slackAuthUrl(String companyId, String userId) =>
      '$slackEndpoint/auth?companyId=$companyId&userId=$userId';

  /// List/Delete Accounts endpoint
  static String get emailAccountsEndpoint => '$emailEndpoint/accounts';

  /// Assignments endpoint
  static const String assignmentsEndpoint = '$apiBaseUrl/api/assignments';

  /// Chat endpoint
  static const String chatEndpoint = '$apiBaseUrl/api/chat';

  // ============================================================================
  // WHATSAPP API ENDPOINTS
  // ============================================================================

  /// WhatsApp session status
  static String whatsappStatus(String userId) =>
      '$whatsappEndpoint/status?userId=$userId';

  /// WhatsApp QR code
  static String whatsappQr(String userId) =>
      '$whatsappEndpoint/qr?userId=$userId';

  /// WhatsApp connect
  static String get whatsappConnect => '$whatsappEndpoint/connect';

  /// WhatsApp disconnect
  static String get whatsappDisconnect => '$whatsappEndpoint/disconnect';

  /// WhatsApp cancel pending connection
  static String get whatsappCancel => '$whatsappEndpoint/cancel';

  /// WhatsApp groups
  static String whatsappGroups(String userId) =>
      '$whatsappEndpoint/groups?userId=$userId';

  /// WhatsApp monitored groups
  static String whatsappMonitored(String userId) =>
      '$whatsappEndpoint/monitored?userId=$userId';

  /// WhatsApp monitor toggle
  static String get whatsappMonitor => '$whatsappEndpoint/monitor';

  /// WhatsApp messages
  static String whatsappMessages({
    String? userId,
    String? companyId,
    String? groupId,
    int limit = 50,
    String? startAfter,
    String? searchQuery,
  }) {
    var url = '$whatsappEndpoint/messages?limit=$limit';
    if (userId != null) url += '&userId=$userId';
    if (companyId != null) url += '&companyId=$companyId';
    if (groupId != null) url += '&groupId=$groupId';
    if (startAfter != null) url += '&startAfter=$startAfter';
    if (searchQuery != null && searchQuery.isNotEmpty)
      url += '&searchQuery=$searchQuery';
    return url;
  }

  /// WhatsApp message count
  static String whatsappMessageCount({required String userId, String? since}) {
    var url = '$whatsappEndpoint/messages/count?userId=$userId';
    if (since != null) url += '&since=$since';
    return url;
  }

  // ============================================================================
  // STORAGE API ENDPOINTS
  // ============================================================================

  /// Storage base endpoint
  static const String storageEndpoint = '$apiBaseUrl/api/storage';

  /// List files endpoint
  static String get storageListEndpoint => '$storageEndpoint/list';

  /// Upload file endpoint
  static String get storageUploadEndpoint => '$storageEndpoint/upload';

  /// Create folder endpoint
  static String get storageFolderEndpoint => '$storageEndpoint/folder';

  /// Download file endpoint (key will be appended)
  static String storageDownloadEndpoint(String key) =>
      '$storageEndpoint/download/$key';

  /// Delete file endpoint (key will be appended)
  static String storageDeleteEndpoint(String key) =>
      '$storageEndpoint/delete/$key';

  /// Delete folder endpoint (name will be appended)
  static String storageDeleteFolderEndpoint(String name) =>
      '$storageEndpoint/folder/$name';

  /// Presigned upload URL endpoint
  static String get storagePresignedUploadEndpoint =>
      '$storageEndpoint/presigned/upload';

  /// Presigned download URL endpoint (key will be appended)
  static String storagePresignedDownloadEndpoint(String key) =>
      '$storageEndpoint/presigned/download/$key';

  /// Rename file/folder endpoint
  static String get storageRenameEndpoint => '$storageEndpoint/rename';

  /// Move file/folder endpoint
  static String get storageMoveEndpoint => '$storageEndpoint/move';

  /// List all folders endpoint (for move dialog)
  static String get storageFoldersEndpoint => '$storageEndpoint/folders';

  // ============================================================================
  // APP SETTINGS
  // ============================================================================

  static const String appName = 'URBox';
  static const String appVersion = '1.0.0';

  // Production URLs (update when deploying)
  static const String productionApiUrl = 'https://api.yourdomain.com';
  static const String productionAppUrl = 'https://yourdomain.com';

  // Environment check
  static bool get isProduction => apiBaseUrl.contains('https');
  static bool get isDevelopment => !isProduction;
}
