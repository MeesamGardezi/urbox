# Settings Page Performance Optimization

## Problem
The Settings page was taking too long to load, causing a poor user experience with extended loading spinner times.

## Root Cause
The `_loadData()` method was making **two sequential API calls**:
1. `AuthService.getUserProfile()` - to fetch user data
2. `SubscriptionService.getCompanyPlan()` - to fetch company data

These were executed **sequentially** (one after the other), which meant:
- If each API call takes 500ms, total loading time = 1000ms (1 second)
- Users had to wait for both calls to complete before seeing ANY content
- The loading spinner blocked the entire UI during this time

## Solution

### 1. Progressive Loading Strategy
Instead of waiting for all data before showing the UI, we now:
- ✅ Load user data first (most important)
- ✅ Show the UI immediately after user data loads
- ✅ Load company data in the background (non-blocking)
- ✅ Update the company section when data arrives

### 2. Loading Skeleton
Added a loading skeleton for the company section that:
- Shows placeholder UI while company data is being fetched
- Provides visual feedback that content is loading
- Maintains layout stability (no content jumping)

## Performance Improvement

### Before
```
User clicks Settings
    ↓
Show loading spinner
    ↓
Fetch user data (500ms)
    ↓
Fetch company data (500ms)
    ↓
Hide loading spinner
    ↓
Show content
Total: ~1000ms with blank screen
```

### After
```
User clicks Settings
    ↓
Show loading spinner
    ↓
Fetch user data (500ms)
    ↓
Hide loading spinner + Show UI with skeleton
    ↓ (background)
Fetch company data (500ms)
    ↓
Update company section
Total: ~500ms to first content
```

**Result**: **50% faster perceived loading time** ⚡

## Implementation Details

### Modified Methods

#### `_loadData()` - Main data loading
```dart
Future<void> _loadData() async {
  // 1. Fetch user profile
  final userResponse = await AuthService.getUserProfile(user!.uid);
  
  // 2. Parse user data and update state
  _userProfile = UserProfile(...);
  
  // 3. Show UI immediately
  setState(() {
    _isLoading = false;  // ← Key change: don't wait for company data
  });
  
  // 4. Load company data in background (non-blocking)
  if (_userProfile!.companyId.isNotEmpty) {
    _loadCompanyData(_userProfile!.companyId);
  }
}
```

#### `_loadCompanyData()` - Background company loading
```dart
Future<void> _loadCompanyData(String companyId) async {
  // Fetch company data without blocking UI
  final companyResponse = await SubscriptionService.getCompanyPlan(companyId);
  
  // Update company section when data arrives
  setState(() {
    _company = Company(...);
  });
}
```

#### `_buildCompanySection()` - Smart rendering
```dart
Widget _buildCompanySection() {
  return Card(
    child: Column(
      children: [
        // Header (always visible)
        Text('Company Information'),
        
        // Conditional content
        if (_company != null) ...[
          // Show actual company data
          _buildInfoRow(...),
        ] else ...[
          // Show loading skeleton
          _buildLoadingSkeleton(),
        ],
      ],
    ),
  );
}
```

## Benefits

✨ **Faster Initial Load**: Users see content in ~500ms instead of ~1000ms
🎯 **Better UX**: Progressive loading feels more responsive
💪 **Resilient**: If company data fails, user still sees their profile
🎨 **Visual Feedback**: Loading skeleton shows progress
📱 **Professional**: Matches modern app loading patterns

## Testing

To verify the improvement:
1. Open Settings page
2. Observe that:
   - ✅ Profile section appears immediately
   - ✅ Company section shows loading skeleton
   - ✅ Company data populates after ~500ms
   - ✅ No full-page loading spinner after initial load

## Files Modified

- `/frontend/lib/core/screens/settings_screen.dart`
  - Split `_loadData()` into two methods
  - Added `_loadCompanyData()` for background loading
  - Added `_buildLoadingSkeleton()` and `_buildSkeletonRow()`
  - Updated `_buildCompanySection()` to handle loading state

## Future Optimizations

Consider these additional improvements:
1. **Caching**: Cache user/company data to avoid repeated API calls
2. **Prefetching**: Load settings data when user navigates to dashboard
3. **Optimistic Updates**: Show cached data immediately, refresh in background
4. **Request Deduplication**: Prevent multiple simultaneous API calls
