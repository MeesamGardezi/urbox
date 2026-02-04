import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../auth/services/auth_service.dart';

class ThemeService {
  // Singleton pattern
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();

  /// ValueNotifier to hold the current theme mode
  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.light);

  /// Initialize theme from Firebase user preferences
  Future<void> initialize() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('[ThemeService] No user logged in, using light mode');
        return;
      }

      final response = await AuthService.getUserProfile(user.uid);

      if (response['success'] == true && response['user'] != null) {
        final userData = response['user'] as Map<String, dynamic>;
        final preferences = userData['preferences'] as Map<String, dynamic>?;
        final isDark = preferences?['darkMode'] == true;

        themeMode.value = isDark ? ThemeMode.dark : ThemeMode.light;
        debugPrint(
          '[ThemeService] Initialized from Firebase: ${themeMode.value}',
        );
      } else {
        debugPrint(
          '[ThemeService] Failed to load user profile: ${response['error']}',
        );
      }
    } catch (e) {
      debugPrint('[ThemeService] Error loading theme: $e');
    }
  }

  /// Toggle between light and dark mode
  /// Note: This only updates the UI. The backend sync happens in SettingsScreen via updatePreferences()
  void toggleTheme(bool isDark) {
    themeMode.value = isDark ? ThemeMode.dark : ThemeMode.light;
    debugPrint('[ThemeService] Theme toggled to: ${themeMode.value}');
  }

  /// Get current mode
  bool get isDarkMode => themeMode.value == ThemeMode.dark;
}
