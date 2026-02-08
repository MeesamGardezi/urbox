import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class AddSlackDialog extends StatelessWidget {
  final VoidCallback onConnect;

  const AddSlackDialog({super.key, required this.onConnect});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Connect Slack', style: AppTheme.headingSm),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 20,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Connect your Slack workspace to sync messages.',
              style: AppTheme.bodyMd,
            ),
            const SizedBox(height: 24),
            _buildOption(
              icon: Icons.tag, // Or Slack logo asset if available
              title: 'Connect Workspace',
              subtitle: 'Sign in to Slack',
              color: const Color(0xFF4A154B), // Slack purple
              gradient: const LinearGradient(
                colors: [Color(0xFF4A154B), Color(0xFF611f69)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              onTap: onConnect,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Gradient gradient,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: Container(
          padding: const EdgeInsets.all(AppTheme.spacing4),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.border),
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: AppTheme.spacing4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTheme.labelLg),
                    const SizedBox(height: 2),
                    Text(subtitle, style: AppTheme.bodySm),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppTheme.textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
