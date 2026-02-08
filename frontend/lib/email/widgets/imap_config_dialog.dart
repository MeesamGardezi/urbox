import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../services/email_service.dart';

class ImapConfigDialog extends StatefulWidget {
  final String companyId;
  final String userId;

  const ImapConfigDialog({
    Key? key,
    required this.companyId,
    required this.userId,
  }) : super(key: key);

  @override
  State<ImapConfigDialog> createState() => _ImapConfigDialogState();
}

class _ImapConfigDialogState extends State<ImapConfigDialog> {
  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '993');
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  bool _useTls = true;
  bool _isTestingConnection = false;
  bool _isSaving = false;
  bool _connectionTested = false;
  String? _testResult;
  bool _testSuccess = false;
  bool _showPassword = false;

  final _emailService = EmailService();

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isTestingConnection = true;
      _testResult = null;
      _connectionTested = false;
    });

    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 993;
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    final result = await _emailService.testImapConnection(
      host,
      port,
      email,
      password,
      _useTls,
    );

    if (mounted) {
      setState(() {
        _isTestingConnection = false;
        _connectionTested = true;
        _testSuccess = result['success'] == true;
        _testResult = result['success'] == true
            ? 'Connection successful!'
            : result['error'] ?? 'Connection failed';
      });
    }
  }

  Future<void> _saveAccount() async {
    if (!_testSuccess) return;

    setState(() {
      _isSaving = true;
    });

    final result = await _emailService.addImapAccount(
      widget.companyId,
      widget.userId,
      _nameController.text.trim(),
      _hostController.text.trim(),
      int.tryParse(_portController.text.trim()) ?? 993,
      _emailController.text.trim(),
      _passwordController.text,
      _useTls,
    );

    if (mounted) {
      setState(() {
        _isSaving = false;
      });

      if (result['success'] == true) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('IMAP Account connected successfully')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save account: ${result['error']}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
      ),
      backgroundColor: AppTheme.surface,
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(AppTheme.spacing6),
        child: Form(
          key: _formKey,
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
                      gradient: const LinearGradient(
                        colors: [Color(0xFF607D8B), Color(0xFF90A4AE)],
                      ),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    ),
                    child: const Icon(
                      Icons.settings_input_component,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacing3),
                  Expanded(
                    child: Text('Configure IMAP', style: AppTheme.headingSm),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: AppTheme.textMuted),
                    onPressed: () => Navigator.pop(context),
                    splashRadius: 20,
                  ),
                ],
              ),

              const SizedBox(height: AppTheme.spacing6),

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Display Name
                      Text('Account Name (Optional)', style: AppTheme.labelMd),
                      const SizedBox(height: AppTheme.spacing2),
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          hintText: 'e.g., Work Email',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                      ),

                      const SizedBox(height: AppTheme.spacing4),

                      // Email & Password
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Email Address', style: AppTheme.labelMd),
                                const SizedBox(height: AppTheme.spacing2),
                                TextFormField(
                                  controller: _emailController,
                                  decoration: const InputDecoration(
                                    hintText: 'user@example.com',
                                    prefixIcon: Icon(Icons.email_outlined),
                                  ),
                                  validator: (v) =>
                                      v?.isNotEmpty == true ? null : 'Required',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppTheme.spacing4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Password / App Password',
                                  style: AppTheme.labelMd,
                                ),
                                const SizedBox(height: AppTheme.spacing2),
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: !_showPassword,
                                  decoration: InputDecoration(
                                    hintText: '********',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _showPassword
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                      ),
                                      onPressed: () => setState(
                                        () => _showPassword = !_showPassword,
                                      ),
                                    ),
                                  ),
                                  validator: (v) =>
                                      v?.isNotEmpty == true ? null : 'Required',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: AppTheme.spacing4),

                      // Server Settings
                      Text('IMAP Server Settings', style: AppTheme.labelLg),
                      const SizedBox(height: AppTheme.spacing3),

                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Hostname', style: AppTheme.labelMd),
                                const SizedBox(height: AppTheme.spacing2),
                                TextFormField(
                                  controller: _hostController,
                                  decoration: const InputDecoration(
                                    hintText: 'imap.example.com',
                                    prefixIcon: Icon(Icons.dns_outlined),
                                  ),
                                  validator: (v) =>
                                      v?.isNotEmpty == true ? null : 'Required',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppTheme.spacing4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Port', style: AppTheme.labelMd),
                                const SizedBox(height: AppTheme.spacing2),
                                TextFormField(
                                  controller: _portController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    hintText: '993',
                                  ),
                                  validator: (v) =>
                                      v?.isNotEmpty == true ? null : 'Required',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: AppTheme.spacing4),

                      // Security
                      CheckboxListTile(
                        value: _useTls,
                        onChanged: (v) => setState(() => _useTls = v!),
                        title: Text(
                          'Use Secure Connection (TLS/SSL)',
                          style: AppTheme.bodyMd,
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        activeColor: AppTheme.primary,
                      ),

                      // Test Result
                      if (_connectionTested) ...[
                        const SizedBox(height: AppTheme.spacing4),
                        Container(
                          padding: const EdgeInsets.all(AppTheme.spacing3),
                          decoration: BoxDecoration(
                            color: _testSuccess
                                ? AppTheme.success.withValues(alpha: 0.1)
                                : AppTheme.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusMd,
                            ),
                            border: Border.all(
                              color: _testSuccess
                                  ? AppTheme.success
                                  : AppTheme.error,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _testSuccess ? Icons.check_circle : Icons.error,
                                color: _testSuccess
                                    ? AppTheme.success
                                    : AppTheme.error,
                              ),
                              const SizedBox(width: AppTheme.spacing3),
                              Expanded(
                                child: Text(
                                  _testResult!,
                                  style: AppTheme.bodySm.copyWith(
                                    color: _testSuccess
                                        ? AppTheme.successDark
                                        : AppTheme.error,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppTheme.spacing6),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isTestingConnection || _isSaving
                        ? null
                        : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppTheme.spacing4),
                  OutlinedButton.icon(
                    onPressed: _isTestingConnection || _isSaving
                        ? null
                        : _testConnection,
                    icon: _isTestingConnection
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_tethering, size: 18),
                    label: Text(
                      _isTestingConnection ? 'Testing...' : 'Test Connection',
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacing4),
                  ElevatedButton.icon(
                    onPressed: !_testSuccess || _isSaving ? null : _saveAccount,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: Text(_isSaving ? 'Saving...' : 'Connect Account'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
