# Dark Mode Theme Persistence Fix

## Issue
When logging in from an incognito window or a different browser, the user's saved dark mode preference was not being applied. The theme would always default to light mode on login.

## Root Cause
The `ThemeService.initialize()` was only called once at app startup in `main.dart` (line 17), **before** any user was logged in. When a user subsequently logged in:
1. The theme service had already been initialized with no user (defaulting to light mode)
2. No re-initialization occurred after login
3. The user's saved theme preference in Firebase was never fetched

## Solution
Updated `main.dart` to listen for Firebase auth state changes and re-initialize the theme service when a user logs in:

```dart
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
  // ...
}
```

## How It Works Now

### On App Startup (No User Logged In)
1. `main()` calls `ThemeService().initialize()`
2. No user is logged in, so it defaults to light mode
3. App shows login screen in light mode

### On User Login
1. User logs in via `FirebaseAuth.signInWithEmailAndPassword()`
2. Auth state changes from `null` to `User`
3. The listener in `_MyAppState.initState()` detects this change
4. `ThemeService().initialize()` is called again
5. This time, `FirebaseAuth.instance.currentUser` is not null
6. The service fetches user profile from backend via `AuthService.getUserProfile(userId)`
7. Extracts `preferences.darkMode` from the response
8. Updates `themeMode.value` to match the user's saved preference
9. The `ValueListenableBuilder` in the widget tree reacts to this change
10. The entire app re-renders with the correct theme

### On User Logout
1. User logs out
2. Auth state changes from `User` to `null`
3. The listener calls `ThemeService().toggleTheme(false)`
4. Theme resets to light mode

## Data Flow

```
Firebase Firestore
  └─ users/{userId}
      └─ preferences
          └─ darkMode: true/false

                ↓ (fetched via backend API)

AuthService.getUserProfile(userId)
  └─ GET /api/auth/user/{userId}

                ↓

ThemeService.initialize()
  └─ Updates themeMode.value

                ↓

ValueListenableBuilder<ThemeMode>
  └─ Rebuilds MaterialApp with correct theme

                ↓

User sees their preferred theme! 🎨
```

## Testing Instructions

1. **Enable Dark Mode**:
   - Log in to your account
   - Go to Settings
   - Toggle "Dark Mode" ON
   - Verify the UI switches to dark theme

2. **Test Persistence (Same Browser)**:
   - Refresh the page
   - Verify dark mode is still active

3. **Test Persistence (Incognito/Different Browser)**:
   - Open an incognito window or different browser
   - Log in with the same account
   - **Expected**: Dark mode should be automatically applied after login
   - **Previous behavior**: Would always show light mode

4. **Test Logout**:
   - Log out
   - Verify the theme resets to light mode
   - Log back in
   - Verify your saved theme preference is restored

## Files Modified

- `/Users/meesam/projects/urbox.ai/frontend/lib/main.dart`
  - Changed `MyApp` from `StatelessWidget` to `StatefulWidget`
  - Added `initState()` with auth state listener
  - Re-initializes theme on login, resets on logout
