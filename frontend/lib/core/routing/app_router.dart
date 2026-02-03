import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../auth/screens/auth_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/plans_screen.dart';
import '../screens/settings_screen.dart';

/// App Router Configuration
///
/// Handles all routing with authentication guards
class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/auth',
    redirect: (context, state) {
      final user = FirebaseAuth.instance.currentUser;
      final isLoggedIn = user != null;
      final isOnAuthPage = state.matchedLocation.startsWith('/auth');

      // Not logged in and not on auth page -> redirect to auth
      if (!isLoggedIn && !isOnAuthPage) {
        return '/auth';
      }

      // Logged in and on auth page -> redirect to dashboard
      if (isLoggedIn && isOnAuthPage) {
        return '/dashboard';
      }

      return null;
    },
    routes: [
      // Unified Authentication Route
      GoRoute(
        path: '/auth',
        name: 'auth',
        builder: (context, state) {
          // Check for invite token in query parameters
          final inviteToken = state.uri.queryParameters['invite'];
          return AuthScreen(inviteToken: inviteToken);
        },
      ),

      // Legacy routes for backward compatibility (redirect to unified auth)
      GoRoute(path: '/login', redirect: (context, state) => '/auth'),
      GoRoute(path: '/signup', redirect: (context, state) => '/auth'),
      GoRoute(
        path: '/accept-invite/:token',
        redirect: (context, state) {
          final token = state.pathParameters['token'];
          return '/auth?invite=$token';
        },
      ),

      // App Routes (requires authentication)
      GoRoute(
        path: '/dashboard',
        name: 'dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),

      GoRoute(
        path: '/plans',
        name: 'plans',
        builder: (context, state) => const PlansScreen(),
      ),

      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],

    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Page not found',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              state.uri.toString(),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/dashboard'),
              child: const Text('Go to Dashboard'),
            ),
          ],
        ),
      ),
    ),
  );
}
