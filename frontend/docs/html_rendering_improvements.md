# HTML Parsing Improvements for Email Rendering

## Problem
The original HTML rendering was causing layout constraint violations and displaying text vertically (one character per line). This was due to:
1. Lack of proper constraints on the HTML widget
2. No error handling for malformed HTML
3. Missing table and image styling
4. No sanitization of potentially problematic HTML elements

## Solution Implemented

### 1. **Added HTML Sanitization**
- Removes `<script>` and `<style>` tags that can cause rendering issues
- Wraps unwrapped content in a `<div>` tag
- Returns safe fallback for empty content

### 2. **Proper Constraints**
```dart
ConstrainedBox(
  constraints: const BoxConstraints(
    minHeight: 100,
    maxWidth: double.infinity,
  ),
  // ...
)
```

### 3. **Render Mode Configuration**
```dart
renderMode: RenderMode.column,
```
This forces the HTML to render in a column layout, preventing horizontal overflow issues.

### 4. **Comprehensive Element Styling**
Added custom styles for:
- **Tables**: Full width, proper borders, and spacing
- **Images**: Max width 100%, auto height, proper margins
- **Code blocks**: Background color, padding, monospace font
- **Headings**: Proper margins and font weights
- **Paragraphs**: Consistent line height and spacing
- **Links**: Proper color and underline
- **Blockquotes**: Border, padding, and styling

### 5. **Custom Image Widget**
- Proper constraints (max height 400px)
- Loading indicator while images load
- Error handling with fallback UI
- Prevents CORS errors from breaking the layout

### 6. **Error Handling**
- `onErrorBuilder` catches rendering errors
- Displays user-friendly error messages
- Logs errors for debugging
- Prevents app crashes from malformed HTML

## Additional Recommendations

### Option 1: Use WebView for Complex Emails (Recommended for very complex layouts)

If you still encounter issues with complex HTML emails, consider using a WebView as a fallback:

```dart
import 'package:webview_flutter/webview_flutter.dart';

class EmailRendererWithWebView extends StatelessWidget {
  final String htmlContent;
  final bool useWebView;

  const EmailRendererWithWebView({
    super.key,
    required this.htmlContent,
    this.useWebView = false,
  });

  @override
  Widget build(BuildContext context) {
    if (useWebView) {
      return SizedBox(
        height: 600,
        child: WebViewWidget(
          controller: WebViewController()
            ..loadHtmlString('''
              <!DOCTYPE html>
              <html>
              <head>
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <style>
                  body { 
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    font-size: 14px;
                    line-height: 1.6;
                    padding: 16px;
                    color: #1F2937;
                  }
                  img { max-width: 100%; height: auto; }
                  table { width: 100%; border-collapse: collapse; }
                  td, th { padding: 8px; border: 1px solid #E5E7EB; }
                </style>
              </head>
              <body>
                $htmlContent
              </body>
              </html>
            '''),
        ),
      );
    }
    
    return EmailRenderer(htmlContent: htmlContent);
  }
}
```

### Option 2: Detect Complex HTML and Switch Renderers

```dart
bool _isComplexHtml(String html) {
  // Check for complex table structures
  final tableCount = RegExp(r'<table', caseSensitive: false).allMatches(html).length;
  if (tableCount > 3) return true;
  
  // Check for nested tables
  if (html.contains(RegExp(r'<table[^>]*>.*<table', caseSensitive: false, dotAll: true))) {
    return true;
  }
  
  // Check for inline styles that might cause issues
  final inlineStyleCount = RegExp(r'style\s*=', caseSensitive: false).allMatches(html).length;
  if (inlineStyleCount > 50) return true;
  
  return false;
}
```

### Option 3: Pre-process HTML on Backend

For best results, consider sanitizing and simplifying HTML on the backend before sending to Flutter:

```javascript
// Backend example using cheerio
const cheerio = require('cheerio');

function sanitizeEmailHtml(html) {
  const $ = cheerio.load(html);
  
  // Remove problematic elements
  $('script, style, iframe, object, embed').remove();
  
  // Simplify complex tables
  $('table').each((i, table) => {
    $(table).css({
      'width': '100%',
      'max-width': '100%',
      'table-layout': 'auto'
    });
  });
  
  // Fix images
  $('img').each((i, img) => {
    $(img).css({
      'max-width': '100%',
      'height': 'auto'
    });
  });
  
  return $.html();
}
```

## Testing the Fix

1. **Hot reload** your Flutter app
2. **Open an email** with complex HTML
3. **Check the console** for any rendering errors
4. **Verify** that:
   - Text displays normally (not vertically)
   - Images load with proper constraints
   - Tables render correctly
   - No layout overflow errors

## Performance Considerations

The improved renderer:
- ✅ Handles most email HTML correctly
- ✅ Prevents layout crashes
- ✅ Provides better error messages
- ✅ Improves image loading UX
- ⚠️ May be slower for very large HTML (>100KB)

For very large emails, consider:
1. Lazy loading images
2. Truncating extremely long emails
3. Using WebView for emails >100KB

## Monitoring

Add analytics to track rendering issues:

```dart
onErrorBuilder: (context, element, error) {
  // Log to your analytics service
  FirebaseAnalytics.instance.logEvent(
    name: 'html_render_error',
    parameters: {
      'element': element.localName ?? 'unknown',
      'error': error.toString(),
    },
  );
  
  debugPrint('HTML rendering error: $error');
  // ... rest of error UI
}
```

## Summary

The new `EmailRenderer` provides:
1. ✅ **Better HTML sanitization** - Removes problematic elements
2. ✅ **Proper constraints** - Prevents layout overflow
3. ✅ **Comprehensive styling** - Handles tables, images, code blocks
4. ✅ **Error handling** - Graceful degradation on errors
5. ✅ **Image optimization** - Loading states and error fallbacks
6. ✅ **CORS handling** - Better error messages for blocked images

This should resolve the vertical text issue and most rendering problems!
