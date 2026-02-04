import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/services/theme_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize Theme Service BEFORE app starts
  await ThemeService().initialize();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();

    // Listen to auth state changes and re-initialize theme
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user != null) {
        // User logged in - reload theme from their preferences
        ThemeService().initialize();
      } else {
        // User logged out - reset to light mode
        ThemeService().toggleTheme(false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Show loading screen while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return ValueListenableBuilder<ThemeMode>(
            valueListenable: ThemeService().themeMode,
            builder: (context, themeMode, _) {
              return MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                themeMode: themeMode,
                home: const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                ),
              );
            },
          );
        }

        // Build app with router
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: ThemeService().themeMode,
          builder: (context, themeMode, _) {
            return MaterialApp.router(
              title: 'Shared Mailbox',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: themeMode,
              routerConfig: AppRouter.router,
            );
          },
        );
      },
    );
  }
}
