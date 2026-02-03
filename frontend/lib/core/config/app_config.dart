/// Application Configuration
///
/// Centralized configuration for API endpoints and app settings
class AppConfig {
  // API Configuration
  static const String apiBaseUrl = 'http://localhost:3004';

  // API Endpoints
  static const String authEndpoint = '$apiBaseUrl/api/auth';
  static const String teamEndpoint = '$apiBaseUrl/api/team';
  static const String subscriptionEndpoint = '$apiBaseUrl/api/subscription';
  static const String paymentEndpoint = '$apiBaseUrl/api/payment';

  // App Settings
  static const String appName = 'Shared Mailbox';
  static const String appVersion = '1.0.0';

  // Production URLs (update when deploying)
  static const String productionApiUrl = 'https://api.yourdomain.com';
  static const String productionAppUrl = 'https://yourdomain.com';

  // Environment check
  static bool get isProduction => apiBaseUrl.contains('https');
  static bool get isDevelopment => !isProduction;
}
