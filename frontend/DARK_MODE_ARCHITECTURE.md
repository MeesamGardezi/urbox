# Dark Mode Implementation - Firebase Backend

## Architecture

The dark mode preference is now stored in **Firebase** as part of the user's profile, ensuring it persists across devices and sessions.

## Data Flow

```
App Startup (main.dart)
    ↓
ThemeService.initialize()
    ↓
Fetch user profile from Firebase via AuthService.getUserProfile()
    ↓
Extract preferences.darkMode from user document
    ↓
Set ThemeService.themeMode (ValueNotifier)
    ↓
MaterialApp rebuilds with correct theme
    ↓
User sees correct theme BEFORE first page loads
```

## Toggle Flow

```
User toggles Dark Mode in Settings
    ↓
setState(_darkMode = value)
    ↓
ThemeService.toggleTheme(value)  ← Updates ValueNotifier (instant UI update)
    ↓
AuthService.updatePreferences()  ← Saves to Firebase backend
    ↓
Backend updates Firestore user document
```

## Implementation Details

### 1. **ThemeService** (`theme_service.dart`)
- **Singleton** pattern for global access
- **Firebase** as single source of truth
- **ValueNotifier** for reactive UI updates

```dart
class ThemeService {
  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.light);
  
  // Called in main() - loads from Firebase
  Future<void> initialize() async {
    final user = FirebaseAuth.instance.currentUser;
    final response = await AuthService.getUserProfile(user.uid);
    final isDark = response['user']['preferences']['darkMode'] == true;
    themeMode.value = isDark ? ThemeMode.dark : ThemeMode.light;
  }
  
  // Called when user toggles - updates UI only
  void toggleTheme(bool isDark) {
    themeMode.value = isDark ? ThemeMode.dark : ThemeMode.light;
  }
}
```

### 2. **Backend Storage** (Firestore)
User document structure:
```json
{
  "id": "user_id",
  "email": "user@example.com",
  "preferences": {
    "darkMode": true,
    "language": "en",
    "timezone": "UTC"
  },
  "emailNotifications": true,
  "pushNotifications": false
}
```

### 3. **Settings Screen**
```dart
onChanged: (value) async {
  setState(() => _darkMode = value);
  ThemeService().toggleTheme(value);  // Instant UI update
  await _updatePreferences();         // Save to Firebase
}
```

### 4. **Main App** (`main.dart`)
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(...);
  
  // Load theme from Firebase BEFORE app starts
  await ThemeService().initialize();
  
  runApp(const MyApp());
}
```

## Benefits

✅ **Cross-Device Sync**: Theme preference syncs across all user devices  
✅ **No Flash**: Theme loaded before first frame renders  
✅ **Persistent**: Survives app restarts and device changes  
✅ **Instant**: UI updates immediately via ValueNotifier  
✅ **Single Source of Truth**: Firebase is the authoritative source  
✅ **Consistent**: All preferences (theme, notifications) stored in same place  

## Files Modified

1. `frontend/lib/core/services/theme_service.dart` - Use Firebase instead of SharedPreferences
2. `frontend/lib/main.dart` - Initialize theme before app starts
3. `frontend/lib/core/screens/settings_screen.dart` - Sync toggle with Firebase
4. `frontend/pubspec.yaml` - Removed shared_preferences dependency
5. `backend/auth/auth.js` - Already returns preferences in user profile

## Backend API

**GET** `/api/auth/user/:userId`
```json
{
  "success": true,
  "user": {
    "id": "...",
    "preferences": {
      "darkMode": true
    }
  }
}
```

**POST** `/api/auth/preferences`
```json
{
  "userId": "...",
  "preferences": {
    "darkMode": true
  }
}
```

## Testing

1. ✅ Toggle dark mode in Settings → Entire app turns dark instantly
2. ✅ Refresh page (hot reload) → Theme persists
3. ✅ Close and reopen app → Theme persists
4. ✅ Login from different device → Theme syncs
5. ✅ Check network tab → Preference saved to Firebase
