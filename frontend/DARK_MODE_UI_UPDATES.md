# Dark Mode UI Updates

## Overview
Updated all pages in the application to properly support dark mode with theme-aware colors and proper contrast.

## Changes Made

### 1. Plans & Billing Screen (`plans_screen.dart`)
**Problem**: The plans page was using hardcoded colors (like `AppTheme.gray100`, `AppTheme.textPrimary`) that didn't adapt to dark mode, causing poor contrast and readability issues.

**Solution**: Made all UI elements theme-aware by:
- Adding `BuildContext` parameter to all builder methods
- Using `Theme.of(context).brightness` to detect dark mode
- Dynamically selecting colors based on theme:
  - Text colors: `Theme.of(context).textTheme.bodyLarge?.color`
  - Muted text: `isDark ? AppTheme.gray400 : AppTheme.textMuted`
  - Backgrounds: `isDark ? AppTheme.gray800 : AppTheme.gray100`
  - Borders: `isDark ? AppTheme.gray700 : AppTheme.border`

**Updated Components**:
- ✅ Page header and description
- ✅ Current plan banner (with gradient backgrounds)
- ✅ Pricing toggle (Monthly/Annual selector)
- ✅ Pricing cards (Free & Pro plans)
- ✅ Feature comparison table
- ✅ FAQ section

### 2. Placeholder Pages (`app_router.dart`)
**Problem**: "Coming Soon" pages (Inbox, Sent, Email Accounts, Custom Inboxes) had hardcoded grey colors that looked bad in dark mode.

**Solution**: Updated all placeholder pages to use theme-aware styling:
- Icons: `Theme.of(context).iconTheme.color?.withOpacity(0.5)`
- Headings: `Theme.of(context).textTheme.headlineSmall`
- Body text: `Theme.of(context).textTheme.bodyMedium` with muted color

**Updated Pages**:
- ✅ Inbox
- ✅ Sent
- ✅ Email Accounts
- ✅ Custom Inboxes

### 3. Settings Screen
**Already Implemented**: The settings screen was already using theme-aware colors and adapts properly to dark mode.

### 4. Dashboard Screen
**Already Implemented**: The dashboard screen uses the Card widget which automatically adapts to the theme.

## Dark Mode Color Palette

### Light Mode
- Background: `#F8FAFC` (very light blue-grey)
- Surface: `#FFFFFF` (white)
- Text Primary: `#1E293B` (dark slate)
- Text Muted: `#94A3B8` (light slate)
- Border: `#E2E8F0` (light grey)

### Dark Mode
- Background: `#000000` (black)
- Surface: `#171717` (gray900)
- Text Primary: `#FFFFFF` (white)
- Text Muted: `#A3A3A3` (gray400)
- Border: `#262626` (gray800)

## Implementation Pattern

For any new screens or components, follow this pattern:

```dart
Widget _buildComponent(BuildContext context) {
  // Detect dark mode
  final isDark = Theme.of(context).brightness == Brightness.dark;
  
  // Get theme-aware colors
  final textColor = Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;
  final mutedColor = isDark ? AppTheme.gray400 : AppTheme.textMuted;
  final bgColor = isDark ? AppTheme.gray800 : AppTheme.gray100;
  final borderColor = isDark ? AppTheme.gray700 : AppTheme.border;
  
  // Use these colors in your widgets
  return Container(
    color: bgColor,
    child: Text(
      'Hello',
      style: TextStyle(color: textColor),
    ),
  );
}
```

## Testing Checklist

- [x] Plans page displays correctly in light mode
- [x] Plans page displays correctly in dark mode
- [x] Pricing cards have proper contrast in both modes
- [x] Feature comparison table is readable in both modes
- [x] Placeholder pages adapt to theme changes
- [x] Theme persists across sessions
- [x] Theme loads correctly on login

## Files Modified

1. `/frontend/lib/core/screens/plans_screen.dart`
   - Made all builder methods theme-aware
   - Updated colors to adapt to dark mode
   - Fixed contrast issues

2. `/frontend/lib/core/routing/app_router.dart`
   - Updated placeholder pages to use theme colors
   - Improved consistency across the app

## Benefits

✨ **Consistent Experience**: All pages now properly support dark mode
🎨 **Better Contrast**: Text and UI elements are readable in both themes
🔄 **Automatic Adaptation**: Pages automatically update when theme changes
📱 **Professional Look**: Dark mode feels polished and intentional
