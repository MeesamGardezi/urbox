import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:url_launcher/url_launcher.dart';

class EmailRenderer extends StatelessWidget {
  final String htmlContent;

  const EmailRenderer({super.key, required this.htmlContent});

  /// Sanitize and prepare HTML content for rendering
  String _sanitizeHtml(String html) {
    if (html.isEmpty) return '<p>No content</p>';

    // Remove potentially problematic elements
    String sanitized = html
        .replaceAll(
          RegExp(
            r'<script[^>]*>.*?</script>',
            caseSensitive: false,
            dotAll: true,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'<style[^>]*>.*?</style>',
            caseSensitive: false,
            dotAll: true,
          ),
          '',
        );

    // Wrap content if not already wrapped
    if (!sanitized.trim().startsWith('<')) {
      sanitized = '<div>$sanitized</div>';
    }

    return sanitized;
  }

  @override
  Widget build(BuildContext context) {
    final sanitizedContent = _sanitizeHtml(htmlContent);

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: 100,
        maxWidth: double.infinity,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: HtmlWidget(
          sanitizedContent,

          // Render mode configuration
          renderMode: RenderMode.column,

          // Handle URL taps
          onTapUrl: (url) async {
            try {
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
                return true;
              }
            } catch (e) {
              debugPrint('Error launching URL: $e');
            }
            return false;
          },

          // Base text style
          textStyle: const TextStyle(
            fontSize: 14,
            height: 1.6,
            color: Color(0xFF1F2937),
          ),

          // Custom styling for email elements
          customStylesBuilder: (element) {
            final styles = <String, String>{};

            switch (element.localName) {
              case 'a':
                styles.addAll({
                  'color': '#2563EB',
                  'text-decoration': 'underline',
                });
                break;

              case 'blockquote':
                styles.addAll({
                  'border-left': '3px solid #E5E7EB',
                  'margin': '16px 0',
                  'padding-left': '16px',
                  'color': '#6B7280',
                  'font-style': 'italic',
                });
                break;

              case 'table':
                styles.addAll({
                  'width': '100%',
                  'border-collapse': 'collapse',
                  'margin': '16px 0',
                });
                break;

              case 'td':
              case 'th':
                styles.addAll({
                  'padding': '8px',
                  'border': '1px solid #E5E7EB',
                  'text-align': 'left',
                });
                break;

              case 'img':
                styles.addAll({
                  'max-width': '100%',
                  'height': 'auto',
                  'display': 'block',
                  'margin': '8px 0',
                });
                break;

              case 'pre':
              case 'code':
                styles.addAll({
                  'background-color': '#F3F4F6',
                  'padding': '12px',
                  'border-radius': '6px',
                  'overflow-x': 'auto',
                  'font-family': 'monospace',
                  'font-size': '13px',
                });
                break;

              case 'p':
                styles.addAll({'margin': '8px 0', 'line-height': '1.6'});
                break;

              case 'h1':
              case 'h2':
              case 'h3':
              case 'h4':
              case 'h5':
              case 'h6':
                styles.addAll({
                  'margin': '16px 0 8px 0',
                  'font-weight': 'bold',
                  'color': '#111827',
                });
                break;
            }

            return styles.isNotEmpty ? styles : null;
          },

          // Custom widget builder for better control
          customWidgetBuilder: (element) {
            // Handle images with error handling
            if (element.localName == 'img') {
              final src = element.attributes['src'];
              if (src != null && src.isNotEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: double.infinity,
                      maxHeight: 400,
                    ),
                    child: Image.network(
                      src,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.broken_image, color: Colors.grey[400]),
                              const SizedBox(width: 8),
                              Text(
                                'Image failed to load',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        );
                      },
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Center(
                          child: CircularProgressIndicator(
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded /
                                      loadingProgress.expectedTotalBytes!
                                : null,
                          ),
                        );
                      },
                    ),
                  ),
                );
              }
            }
            return null;
          },

          // Error handling
          onErrorBuilder: (context, element, error) {
            debugPrint('HTML rendering error: $error');
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red[700]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Error rendering this section',
                      style: TextStyle(color: Colors.red[700]),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
