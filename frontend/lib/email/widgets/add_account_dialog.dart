import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class AddAccountDialog extends StatelessWidget {
  final VoidCallback onGmail;
  final VoidCallback onMicrosoft;
  final VoidCallback onImap;

  const AddAccountDialog({
    Key? key,
    required this.onGmail,
    required this.onMicrosoft,
    required this.onImap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
      ),
      backgroundColor: AppTheme.surface,
      child: Container(
        width: 440,
        padding: const EdgeInsets.all(AppTheme.spacing6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppTheme.spacing2),
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  ),
                  child: const Icon(
                    Icons.add_circle_outline,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppTheme.spacing3),
                Expanded(
                  child: Text(
                    'Connect Email Account',
                    style: AppTheme.headingSm,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: AppTheme.textMuted),
                  onPressed: () => Navigator.pop(context),
                  splashRadius: 20,
                ),
              ],
            ),

            const SizedBox(height: AppTheme.spacing2),

            Text(
              'Choose your email provider to get started.',
              style: AppTheme.bodyMd,
            ),

            const SizedBox(height: AppTheme.spacing5),

            // Provider buttons
            _buildProviderTile(
              icon: Icons.g_mobiledata,
              gradient: const LinearGradient(
                colors: [Color(0xFFEA4335), Color(0xFFFF6F61)],
              ),
              title: 'Gmail',
              subtitle: 'Connect with Google OAuth',
              onTap: onGmail,
            ),

            const SizedBox(height: AppTheme.spacing3),

            _buildProviderTile(
              icon: Icons.window,
              gradient: const LinearGradient(
                colors: [Color(0xFF0078D4), Color(0xFF00BCF2)],
              ),
              title: 'Microsoft',
              subtitle: 'Connect Outlook or Office 365',
              onTap: onMicrosoft,
            ),

            const SizedBox(height: AppTheme.spacing3),

            _buildProviderTile(
              icon: Icons.email_outlined,
              gradient: const LinearGradient(
                colors: [Color(0xFF607D8B), Color(0xFF90A4AE)],
              ),
              title: 'IMAP',
              subtitle: 'Connect via IMAP/SMTP',
              onTap: onImap,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProviderTile({
    required IconData icon,
    required LinearGradient gradient,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        hoverColor: AppTheme.surfaceDark,
        child: Container(
          padding: const EdgeInsets.all(AppTheme.spacing4),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.border),
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
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
