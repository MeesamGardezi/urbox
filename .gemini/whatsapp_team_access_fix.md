# WhatsApp Team Member Access Fix - Complete Implementation

## Problem
WhatsApp messages were not showing for team members in their custom inboxes. The issue was that WhatsApp messages were being fetched using the team member's `userId`, but WhatsApp messages are stored under the company's `companyId` in Firestore.

## Solution
Updated both backend and frontend to support fetching WhatsApp messages by `companyId` instead of (or in addition to) `userId`.

---

## Backend Changes

### File: `/backend/whatsapp/whatsapp.js`

**Updated `/messages` endpoint** (lines 344-422):
- Changed parameter validation to accept either `userId` OR `companyId`
- Added conditional query logic:
  - If `companyId` is provided: fetch messages by `companyId` (for team members)
  - If `userId` is provided: fetch messages by `userId` (for owner/backward compatibility)
- This allows both admin and team members to access WhatsApp messages

```javascript
// Before
if (!userId) {
    return res.status(400).json({
        success: false,
        error: 'Missing userId parameter'
    });
}
const snapshot = await db.collection('whatsappMessages')
    .where('userId', '==', userId)
    .get();

// After
if (!userId && !companyId) {
    return res.status(400).json({
        success: false,
        error: 'Missing userId or companyId parameter'
    });
}
let query = db.collection('whatsappMessages');
if (companyId) {
    query = query.where('companyId', '==', companyId);
} else {
    query = query.where('userId', '==', userId);
}
const snapshot = await query.get();
```

---

## Frontend Changes

### 1. File: `/frontend/lib/core/config/app_config.dart`

**Updated `whatsappMessages` method** (lines 87-101):
- Made `userId` optional
- Added optional `companyId` parameter
- Updated URL construction to include both parameters when provided

```dart
// Before
static String whatsappMessages({
  required String userId,
  ...
}) {
  var url = '$whatsappEndpoint/messages?userId=$userId&limit=$limit';
  ...
}

// After
static String whatsappMessages({
  String? userId,
  String? companyId,
  ...
}) {
  var url = '$whatsappEndpoint/messages?limit=$limit';
  if (userId != null) url += '&userId=$userId';
  if (companyId != null) url += '&companyId=$companyId';
  ...
}
```

### 2. File: `/frontend/lib/whatsapp/services/whatsapp_service.dart`

**Updated `getMessages` method** (lines 263-360):
- Made `userId` optional
- Added optional `companyId` parameter
- Updated cache key to use either `userId` or `companyId`
- Passes both parameters to `AppConfig.whatsappMessages`

```dart
// Before
Future<Map<String, dynamic>> getMessages({
  required String userId,
  ...
}) async {
  final cacheKey = '${userId}_${groupId ?? 'all'}_${searchQuery ?? ''}';
  ...
  AppConfig.whatsappMessages(userId: userId, ...)
}

// After
Future<Map<String, dynamic>> getMessages({
  String? userId,
  String? companyId,
  ...
}) async {
  final cacheKey = '${userId ?? companyId ?? 'unknown'}_${groupId ?? 'all'}_${searchQuery ?? ''}';
  ...
  AppConfig.whatsappMessages(userId: userId, companyId: companyId, ...)
}
```

### 3. File: `/frontend/lib/inbox/screens/inbox_screen.dart`

**Key Changes:**
- Removed the complex `ownerId` fetching logic
- Simplified to use `companyId` directly (already available from user profile)
- Updated `_fetchWhatsApp` to accept `companyId` instead of `userId`
- Updated WhatsApp service call to use `companyId`

```dart
// Removed this entire block (lines 262-279):
// - Fetching company data via SubscriptionService
// - Getting ownerId from company
// - Fallback logic

// Updated WhatsApp fetching (line 177-186):
// Before
if (_hasMoreWhatsApp && _ownerId != null) {
  tasks.add(_fetchWhatsApp(_ownerId!, isLoadMore));
}

// After
if (_hasMoreWhatsApp && _companyId != null) {
  tasks.add(_fetchWhatsApp(_companyId!, isLoadMore));
}

// Updated method signature (line 376):
// Before
Future<List<InboxItem>> _fetchWhatsApp(String userId, bool isLoadMore)

// After
Future<List<InboxItem>> _fetchWhatsApp(String companyId, bool isLoadMore)

// Updated service call (line 384-388):
// Before
final whatsappMessages = await _whatsAppService.getMessages(
  userId: userId,
  ...
);

// After
final whatsappMessages = await _whatsAppService.getMessages(
  companyId: companyId,
  ...
);
```

### 4. File: `/frontend/lib/inbox/screens/main_inbox_screen.dart`

**Updated for consistency:**
- Changed WhatsApp fetching to use `companyId` instead of `user.uid`
- Updated `_fetchWhatsApp` method signature
- Updated WhatsApp service call

```dart
// Updated WhatsApp task (line 143-148):
// Before
if (_hasMoreWhatsApp) {
  tasks.add(_fetchWhatsApp(user.uid, isLoadMore));
}

// After
if (_hasMoreWhatsApp && _companyId != null) {
  tasks.add(_fetchWhatsApp(_companyId!, isLoadMore));
}

// Updated method signature (line 271):
// Before
Future<List<InboxItem>> _fetchWhatsApp(String userId, bool isLoadMore)

// After
Future<List<InboxItem>> _fetchWhatsApp(String companyId, bool isLoadMore)

// Updated service call (line 290-294):
// Before
final whatsappMessages = await _whatsAppService.getMessages(
  userId: userId,
  ...
);

// After
final whatsappMessages = await _whatsAppService.getMessages(
  companyId: companyId,
  ...
);
```

---

## How It Works Now

### For Admin/Owner:
1. User logs in with their account
2. `companyId` is loaded from user profile
3. WhatsApp messages are fetched using `companyId`
4. All WhatsApp messages for the company are displayed

### For Team Members:
1. Team member logs in with their account
2. `companyId` is loaded from user profile (same company as owner)
3. WhatsApp messages are fetched using the same `companyId`
4. Messages are filtered based on custom inbox assignments
5. Team member sees only WhatsApp messages from groups assigned to their custom inbox

### Data Flow:
```
User Login
    ↓
Load User Profile (includes companyId)
    ↓
Fetch WhatsApp Messages (using companyId)
    ↓
Backend queries: whatsappMessages.where('companyId', '==', companyId)
    ↓
Returns all WhatsApp messages for the company
    ↓
Frontend filters by custom inbox assignments (if applicable)
    ↓
Display messages to user
```

---

## Benefits

1. **Simplified Logic**: Removed complex ownerId fetching and fallback logic
2. **Better Performance**: No extra API call to fetch company owner
3. **Team Member Access**: Team members can now see WhatsApp messages in their custom inboxes
4. **Backward Compatible**: Still supports userId parameter for any legacy code
5. **Consistent**: Both MainInboxScreen and InboxScreen use the same approach

---

## Testing Checklist

- [x] Backend accepts companyId parameter
- [x] Backend queries by companyId correctly
- [x] Frontend config supports companyId
- [x] WhatsApp service supports companyId
- [x] InboxScreen uses companyId
- [x] MainInboxScreen uses companyId
- [x] Code compiles without errors
- [ ] Test admin can see WhatsApp messages
- [ ] Test team member can see WhatsApp messages in custom inbox
- [ ] Test pagination works correctly
- [ ] Test filtering by WhatsApp groups works

---

## Files Modified

### Backend:
1. `/backend/whatsapp/whatsapp.js` - Updated `/messages` endpoint

### Frontend:
1. `/frontend/lib/core/config/app_config.dart` - Updated whatsappMessages method
2. `/frontend/lib/whatsapp/services/whatsapp_service.dart` - Updated getMessages method
3. `/frontend/lib/inbox/screens/inbox_screen.dart` - Updated to use companyId
4. `/frontend/lib/inbox/screens/main_inbox_screen.dart` - Updated to use companyId

---

## Notes

- WhatsApp messages must have `companyId` field in Firestore for this to work
- The backend already stores `companyId` when saving WhatsApp messages
- This change maintains backward compatibility with `userId` parameter
