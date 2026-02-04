import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

/// Subscription API Service
///
/// Handles subscription and plan-related API calls
class SubscriptionService {
  static const String _baseUrl = AppConfig.subscriptionEndpoint;

  /// Get company plan details
  /// Returns: {success, plan, isFree, isProFree, subscriptionStatus, hasProAccess, canUpgrade, companyName}
  static Future<Map<String, dynamic>> getCompanyPlan(String companyId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/plan?companyId=$companyId'),
        headers: {'Content-Type': 'application/json'},
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, ...data};
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to get plan details',
        };
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }

  /// Check if company has Pro access
  /// Returns: {success, hasProAccess, plan, isProFree, subscriptionStatus}
  static Future<Map<String, dynamic>> checkAccess(String companyId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/check-access?companyId=$companyId'),
        headers: {'Content-Type': 'application/json'},
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, ...data};
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to check access',
        };
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }

  /// Check if company can access a specific feature
  /// Returns: {success, feature, hasAccess}
  static Future<Map<String, dynamic>> checkFeatureAccess(
    String companyId,
    String feature,
  ) async {
    try {
      final response = await http.get(
        Uri.parse(
          '$_baseUrl/feature-access?companyId=$companyId&feature=$feature',
        ),
        headers: {'Content-Type': 'application/json'},
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, ...data};
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to check feature access',
        };
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }

  /// Get inbox limit for company
  /// Returns: {success, limit, canCreateMore, currentCount}
  static Future<Map<String, dynamic>> getInboxLimit(String companyId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/inbox-limit?companyId=$companyId'),
        headers: {'Content-Type': 'application/json'},
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, ...data};
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to get inbox limit',
        };
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }
}
