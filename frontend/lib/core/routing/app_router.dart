import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'go_router_refresh_stream.dart';
import '../../auth/screens/auth_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/plans_screen.dart';
import '../screens/settings_screen.dart';
import '../../whatsapp/screens/whatsapp_screen.dart';
import '../../storage/screens/storage_screen.dart';
import '../../team/screens/team_screen.dart';

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
    debugLogDiagnostics: true,
    refreshListenable: GoRouterRefreshStream(
      FirebaseAuth.instance.authStateChanges(),
    ),
    redirect: (context, state) {
      final user = FirebaseAuth.instance.currentUser;
      final isLoggedIn = user != null;
      final isAuthRoute = state.matchedLocation.startsWith('/auth');

      // Debug redirect logic (helps verify behavior)
      debugPrint(
        '[Router] Redirect check: path=${state.uri}, loggedIn=$isLoggedIn, authRoute=$isAuthRoute',
      );

      // 1. If not logged in and trying to access protected route -> Redirect to Auth
      if (!isLoggedIn) {
        if (isAuthRoute) return null; // Already on auth page

        final fromLocation = state.uri.toString();
        debugPrint(
          '[Router] Not logged in. Redirecting to auth with return url: $fromLocation',
        );
        return '/auth?redirect=${Uri.encodeComponent(fromLocation)}';
      }

      // 2. If logged in and on auth page -> Redirect to intended destination or dashboard
      if (isLoggedIn && isAuthRoute) {
        final redirect = state.uri.queryParameters['redirect'];

        if (redirect != null && redirect.isNotEmpty) {
          debugPrint(
            '[Router] Logged in on auth page. Redirecting to: $redirect',
          );
          return redirect;
        }

        debugPrint(
          '[Router] Logged in on auth page. Redirecting to /dashboard',
        );
        return '/dashboard';
      }

      return null; // No redirect needed
    },
    routes: [
      // Authentication Route (outside shell)
      GoRoute(
        path: '/auth',
        name: 'auth',
        builder: (context, state) {
          final inviteToken = state.uri.queryParameters['invite'];
          final redirectUrl = state.uri.queryParameters['redirect'];
          return AuthScreen(inviteToken: inviteToken, redirectUrl: redirectUrl);
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

          // Team Members
          GoRoute(
            path: '/team',
            name: 'team',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: TeamScreen()),
          ),

          // Settings
          GoRoute(
            path: '/settings',
            name: 'settings',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: SettingsScreen()),
          ),

          // WhatsApp Integration
          GoRoute(
            path: '/whatsapp',
            name: 'whatsapp',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: WhatsAppScreen()),
          ),

          // Storage
          GoRoute(
            path: '/storage',
            name: 'storage',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: StorageScreen()),
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
