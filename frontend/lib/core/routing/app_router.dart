import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../auth/screens/auth_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/plans_screen.dart';
import '../screens/settings_screen.dart';

/// App Router Configuration
///
/// DashboardScreen IS the app shell with sidebar.
/// All authenticated routes render inside it via ShellRoute.
class AppRouter {
  static final _rootNavigatorKey = GlobalKey<NavigatorState>();
  static final _shellNavigatorKey = GlobalKey<NavigatorState>();

  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/auth',
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final user = FirebaseAuth.instance.currentUser;
      final isLoggedIn = user != null;
      final isOnAuthPage = state.matchedLocation.startsWith('/auth');

      if (!isLoggedIn && !isOnAuthPage) {
        return '/auth';
      }

      if (isLoggedIn && isOnAuthPage) {
        return '/dashboard';
      }

      return null;
    },
    routes: [
      // Authentication Route (outside shell)
      GoRoute(
        path: '/auth',
        name: 'auth',
        builder: (context, state) {
          final inviteToken = state.uri.queryParameters['invite'];
          return AuthScreen(inviteToken: inviteToken);
        },
      ),

      // Legacy routes
      GoRoute(path: '/login', redirect: (context, state) => '/auth'),
      GoRoute(path: '/signup', redirect: (context, state) => '/auth'),
      GoRoute(
        path: '/accept-invite/:token',
        redirect: (context, state) {
          final token = state.pathParameters['token'];
          return '/auth?invite=$token';
        },
      ),

      // Shell Route - DashboardScreen wraps everything
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) {
          return DashboardScreen(child: child);
        },
        routes: [
          GoRoute(path: '/', redirect: (context, state) => '/dashboard'),

          // Dashboard home (shows default dashboard content)
          GoRoute(
            path: '/dashboard',
            name: 'dashboard',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SizedBox.shrink(), // Dashboard renders its own content
            ),
          ),

          // Inbox
          GoRoute(
            path: '/inbox',
            name: 'inbox',
            pageBuilder: (context, state) => NoTransitionPage(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        size: 64,
                        color: Theme.of(
                          context,
                        ).iconTheme.color?.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Inbox',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Coming Soon',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Sent
          GoRoute(
            path: '/sent',
            name: 'sent',
            pageBuilder: (context, state) => NoTransitionPage(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.send_outlined,
                        size: 64,
                        color: Theme.of(
                          context,
                        ).iconTheme.color?.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Sent',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Coming Soon',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Email Accounts
          GoRoute(
            path: '/accounts',
            name: 'accounts',
            pageBuilder: (context, state) => NoTransitionPage(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.email_outlined,
                        size: 64,
                        color: Theme.of(
                          context,
                        ).iconTheme.color?.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Email Accounts',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Coming Soon',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Custom Inboxes
          GoRoute(
            path: '/custom-inboxes',
            name: 'customInboxes',
            pageBuilder: (context, state) => NoTransitionPage(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.folder_outlined,
                        size: 64,
                        color: Theme.of(
                          context,
                        ).iconTheme.color?.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Custom Inboxes',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Coming Soon',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Plans & Billing
          GoRoute(
            path: '/plans',
            name: 'plans',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: PlansScreen()),
          ),

          // Settings
          GoRoute(
            path: '/settings',
            name: 'settings',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: SettingsScreen()),
          ),
        ],
      ),
    ],
    errorPageBuilder: (context, state) => MaterialPage(
      key: state.pageKey,
      child: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 80, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Page Not Found',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                state.matchedLocation,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => context.go('/dashboard'),
                child: const Text('Go Home'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
