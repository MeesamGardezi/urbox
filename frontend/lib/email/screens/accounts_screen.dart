import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../services/email_service.dart';
import '../widgets/add_account_dialog.dart';
import '../widgets/imap_config_dialog.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({Key? key}) : super(key: key);

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  final _emailService = EmailService();
  String? _companyId;
  String? _userId;
  List<dynamic> _accounts = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchUserAndAccounts();
  }

  Future<void> _fetchUserAndAccounts() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _userId = user.uid;
        // In a strictly no-firestore scenario, we rely on backend to resolve companyId via userId
        _fetchAccounts();
      } else {
        setState(() {
          _error = 'User not authenticated';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to initialize: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchAccounts() async {
    if (_userId == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Pass userId to backend, which will resolve companyId
      final accounts = await _emailService.getEmailAccounts(userId: _userId);

      if (mounted) {
        setState(() {
          _accounts = accounts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.background,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppTheme.error),
            const SizedBox(height: 16),
            Text('Error loading accounts: $_error', style: AppTheme.bodyMd),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchAccounts,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_accounts.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppTheme.spacing6),
      itemCount: _accounts.length,
      itemBuilder: (context, index) {
        return _buildAccountCard(_accounts[index]);
      },
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing6),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppTheme.spacing3),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.email_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: AppTheme.spacing4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Email Connections', style: AppTheme.headingMd),
                const SizedBox(height: 2),
                Text(
                  'Manage your connected email accounts',
                  style: AppTheme.bodyMd,
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => _showAddAccountDialog(context),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Account'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(AppTheme.spacing6),
            decoration: BoxDecoration(
              color: AppTheme.primarySubtle,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.email_outlined,
              size: 64,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: AppTheme.spacing6),
          Text('No email accounts connected', style: AppTheme.headingSm),
          const SizedBox(height: AppTheme.spacing2),
          Text(
            'Connect your email accounts to start receiving messages',
            style: AppTheme.bodyMd,
          ),
          const SizedBox(height: AppTheme.spacing6),
          ElevatedButton.icon(
            onPressed: () => _showAddAccountDialog(context),
            icon: const Icon(Icons.add),
            label: const Text('Connect Account'),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard(dynamic account) {
    final provider = account['provider'] as String?;
    final status = account['status'] as String?;
    final isGmail = provider == 'gmail-oauth';
    final isMicrosoft = provider == 'microsoft-oauth';
    final needsReauth = status == 'requires_reauth';

    IconData icon;
    Color color;

    if (isGmail) {
      icon = Icons.g_mobiledata; // Or a custom Gmail icon asset
      color = const Color(0xFFEA4335);
    } else if (isMicrosoft) {
      icon = Icons.window;
      color = const Color(0xFF0078D4);
    } else {
      icon = Icons.email;
      color = const Color(0xFF607D8B);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacing4),
      padding: const EdgeInsets.all(AppTheme.spacing4),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(
          color: needsReauth
              ? AppTheme.warning.withOpacity(0.5)
              : AppTheme.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: AppTheme.spacing4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account['name'] ?? account['email'] ?? 'Unknown',
                  style: AppTheme.labelLg,
                ),
                Text(account['email'] ?? '', style: AppTheme.bodyMd),
                if (needsReauth) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.warning,
                        size: 14,
                        color: AppTheme.warning,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Re-authentication required',
                        style: AppTheme.bodySm.copyWith(
                          color: AppTheme.warning,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (needsReauth)
            TextButton(
              onPressed: () => _reauthenticate(provider!, account['id']),
              child: const Text('Reconnect'),
            )
          else
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _deleteAccount(account['id']),
              color: AppTheme.textMuted,
            ),
        ],
      ),
    );
  }

  void _showAddAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      useRootNavigator:
          true, // Ensure we use the root navigator to show the dialog
      builder: (context) => AddAccountDialog(
        onGmail: _connectGmail,
        onMicrosoft: _connectMicrosoft,
        onImap: () {
          // Close the dialog using the root navigator
          Navigator.of(context, rootNavigator: true).pop();
          _showImapDialog();
        },
      ),
    );
  }

  void _showImapDialog() async {
    if (_userId == null) return;

    final result = await showDialog<bool>(
      context: context,
      useRootNavigator: true, // Ensure we use the root navigator
      builder: (context) => ImapConfigDialog(
        companyId: _companyId ?? 'PENDING',
        userId: _userId!,
      ),
    );

    if (result == true) {
      _fetchAccounts();
    }
  }

  void _connectGmail() {
    // Close the dialog using the root navigator
    Navigator.of(context, rootNavigator: true).pop();

    final url = AppConfig.googleAuthUrl(_companyId ?? 'LOOKUP', _userId!);
    _openOAuthWebView(url, 'Gmail');
  }

  void _connectMicrosoft() {
    // Close the dialog using the root navigator
    Navigator.of(context, rootNavigator: true).pop();

    final url = AppConfig.microsoftAuthUrl(_companyId ?? 'LOOKUP', _userId!);
    _openOAuthWebView(url, 'Microsoft');
  }

  void _reauthenticate(String provider, String accountId) {
    if (provider == 'gmail-oauth') _connectGmail();
    if (provider == 'microsoft-oauth') _connectMicrosoft();
  }

  void _deleteAccount(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text('Are you sure you want to remove this account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _emailService.deleteAccount(id);
      _fetchAccounts();
    }
  }

  void _openOAuthWebView(String url, String provider) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => OAuthWebView(url: url, provider: provider),
      ),
    );
  }
}

class OAuthWebView extends StatefulWidget {
  final String url;
  final String provider;

  const OAuthWebView({Key? key, required this.url, required this.provider})
    : super(key: key);

  @override
  State<OAuthWebView> createState() => _OAuthWebViewState();
}

class _OAuthWebViewState extends State<OAuthWebView> {
  bool _launched = false;

  @override
  void initState() {
    super.initState();
    _launch();
  }

  Future<void> _launch() async {
    if (await canLaunchUrl(Uri.parse(widget.url))) {
      await launchUrl(
        Uri.parse(widget.url),
        mode: LaunchMode.externalApplication,
      );
      setState(() {
        _launched = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Connect ${widget.provider}')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_launched) ...[
              const Icon(
                Icons.check_circle_outline,
                size: 64,
                color: AppTheme.success,
              ),
              const SizedBox(height: 16),
              const Text('Browser opened for authentication.'),
              const SizedBox(height: 8),
              const Text(
                'Once completed, close this page and refresh your accounts.',
              ),
            ] else ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Opening browser...'),
            ],
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Return to App'),
            ),
          ],
        ),
      ),
    );
  }
}
