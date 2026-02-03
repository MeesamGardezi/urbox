import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/config/app_config.dart';

/// Payment API Service
///
/// Handles Stripe payment and subscription management
class PaymentService {
  static const String _baseUrl = '${AppConfig.paymentEndpoint}';

  /// Create Stripe checkout session for Pro subscription
  /// Returns checkout URL
  static Future<String?> createCheckoutSession({
    required String companyId,
    String? successUrl,
    String? cancelUrl,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/create-checkout-session'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'companyId': companyId,
          'successUrl': successUrl,
          'cancelUrl': cancelUrl,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['url'] != null) {
        return data['url'];
      }

      return null;
    } catch (e) {
      print('[Payment] Checkout error: $e');
      return null;
    }
  }

  /// Create Stripe customer portal session
  /// Returns portal URL
  static Future<String?> createPortalSession({
    required String companyId,
    String? returnUrl,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/create-portal-session'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'companyId': companyId, 'returnUrl': returnUrl}),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['url'] != null) {
        return data['url'];
      }

      return null;
    } catch (e) {
      print('[Payment] Portal error: $e');
      return null;
    }
  }

  /// Manually sync subscription status (useful for dev/testing)
  static Future<Map<String, dynamic>> syncSubscription(String companyId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/sync-subscription'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'companyId': companyId}),
      );

      return json.decode(response.body);
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }
}
