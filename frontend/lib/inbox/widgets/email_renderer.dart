import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:url_launcher/url_launcher.dart';

class EmailRenderer extends StatelessWidget {
  final String htmlContent;

  const EmailRenderer({super.key, required this.htmlContent});

  @override
  Widget build(BuildContext context) {
    return HtmlWidget(
      htmlContent,
      onTapUrl: (url) async {
        if (await canLaunchUrl(Uri.parse(url))) {
          await launchUrl(Uri.parse(url));
          return true;
        }
        return false;
      },
      textStyle: const TextStyle(fontSize: 14, height: 1.5),

      // Custom styling for common email elements
      customStylesBuilder: (element) {
        if (element.localName == 'a') {
          return {'color': '#2563EB', 'text-decoration': 'none'};
        }
        if (element.localName == 'blockquote') {
          return {
            'border-left': '3px solid #E5E7EB',
            'margin-left': '0',
            'padding-left': '12px',
            'color': '#6B7280',
          };
        }
        return null;
      },
    );
  }
}
