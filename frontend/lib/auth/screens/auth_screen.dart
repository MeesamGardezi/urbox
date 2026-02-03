import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import '../services/auth_service.dart';
import '../services/team_service.dart';
import '../../core/theme/app_theme.dart';

/// Unified Authentication Screen - Fortune 500 Design
/// Handles login, signup, and invite acceptance in one place
class AuthScreen extends StatefulWidget {
  final String? inviteToken;

  const AuthScreen({super.key, this.inviteToken});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _companyController = TextEditingController();
  final _emailController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _companyFocusNode = FocusNode();
  final _emailFocusNode = FocusNode();
  final _displayNameFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _confirmPasswordFocusNode = FocusNode();

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  bool _isLogin = true;
  bool _isLoading = false;
  bool _isCheckingInvite = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;

  // Invite state
  bool _hasPendingInvite = false;
  String? _inviteCompanyName;
  String? _inviterName;
  String? _inviteToken;

  Timer? _emailCheckDebounce;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: AppTheme.animSlow,
    );
    _fadeAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );
    _animController.forward();

    // Handle invite token from URL if present
    if (widget.inviteToken != null) {
      _loadInviteFromToken(widget.inviteToken!);
    }

    // Listen to email changes for invite detection
    _emailController.addListener(_onEmailChanged);
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailCheckDebounce?.cancel();
    _companyController.dispose();
    _emailController.dispose();
    _displayNameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _companyFocusNode.dispose();
    _emailFocusNode.dispose();
    _displayNameFocusNode.dispose();
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    super.dispose();
  }

  void _onEmailChanged() {
    if (_isLogin) return; // Only check for invites in signup mode

    _emailCheckDebounce?.cancel();
    _emailCheckDebounce = Timer(const Duration(milliseconds: 800), () {
      final email = _emailController.text.trim();
      if (email.contains('@') && email.length > 3) {
        _checkForPendingInvite(email);
      }
    });
  }

  Future<void> _loadInviteFromToken(String token) async {
    setState(() {
      _isLogin = false;
      _isCheckingInvite = true;
    });

    try {
      final response = await TeamService.getInvitation(token);

      if (response['email'] != null && mounted) {
        setState(() {
          _emailController.text = response['email'];
          _inviteCompanyName = response['companyName'];
          _inviterName = response['inviterName'];
          _hasPendingInvite = true;
          _inviteToken = token;
          _isCheckingInvite = false;
        });
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = response['error'] ?? 'Invalid invitation';
            _isCheckingInvite = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load invitation';
          _isCheckingInvite = false;
        });
      }
    }
  }

  Future<void> _checkForPendingInvite(String email) async {
    setState(() => _isCheckingInvite = true);

    try {
      final response = await TeamService.checkPendingInvite(email);

      if (mounted) {
        setState(() {
          _hasPendingInvite = response['hasPendingInvite'] ?? false;
          _inviteCompanyName = response['companyName'];
          _inviterName = response['inviterName'];
          _inviteToken = response['token'];
          _isCheckingInvite = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCheckingInvite = false);
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_isLogin) {
        await _handleLogin();
      } else if (_hasPendingInvite && _inviteToken != null) {
        await _handleAcceptInvite();
      } else {
        await _handleSignup();
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleLogin() async {
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (mounted) {
        context.go('/dashboard');
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = _getFirebaseErrorMessage(e.code);
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'An error occurred. Please try again.';
      });
    }
  }

  Future<void> _handleSignup() async {
    try {
      final response = await AuthService.signup(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        displayName: _displayNameController.text.trim(),
        companyName: _companyController.text.trim(),
      );

      if (response['success'] == true && response['customToken'] != null) {
        await FirebaseAuth.instance.signInWithCustomToken(
          response['customToken'],
        );

        if (mounted) {
          context.go('/dashboard');
        }
      } else {
        setState(() {
          _errorMessage = response['error'] ?? 'Signup failed';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'An error occurred. Please try again.';
      });
    }
  }

  Future<void> _handleAcceptInvite() async {
    try {
      final response = await TeamService.acceptInvitation(
        token: _inviteToken!,
        password: _passwordController.text,
        displayName: _displayNameController.text.trim(),
      );

      if (response['success'] == true && response['customToken'] != null) {
        await FirebaseAuth.instance.signInWithCustomToken(
          response['customToken'],
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Welcome to $_inviteCompanyName!'),
              backgroundColor: AppTheme.success,
            ),
          );
          context.go('/dashboard');
        }
      } else {
        setState(() {
          _errorMessage = response['error'] ?? 'Failed to accept invitation';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'An error occurred. Please try again.';
      });
    }
  }

  String _getFirebaseErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email';
      case 'wrong-password':
        return 'Incorrect password';
      case 'invalid-email':
        return 'Invalid email address';
      case 'user-disabled':
        return 'This account has been disabled';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later';
      case 'invalid-credential':
        return 'Invalid email or password';
      default:
        return 'Authentication failed. Please try again';
    }
  }

  void _toggleMode() {
    _animController.reset();
    setState(() {
      _isLogin = !_isLogin;
      _errorMessage = null;
      _hasPendingInvite = false;
      _inviteCompanyName = null;
      _inviterName = null;
      _inviteToken = null;
      _formKey.currentState?.reset();
    });
    _animController.forward();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Row(
        children: [
          // Left Panel - Branding (Hidden on mobile)
          if (MediaQuery.of(context).size.width > 900)
            Expanded(flex: 5, child: _buildBrandingPanel()),

          // Right Panel - Form
          Expanded(
            flex: 4,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppTheme.spacing8),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: _buildFormCard(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrandingPanel() {
    final isInviteMode = !_isLogin && _hasPendingInvite;

    return Container(
      color: AppTheme.gray50,
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          padding: const EdgeInsets.all(AppTheme.spacing12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isInviteMode ? AppTheme.success : AppTheme.primary,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: Icon(
                  isInviteMode ? Icons.mail_outlined : Icons.all_inbox_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),

              const SizedBox(height: AppTheme.spacing8),

              // Headline
              Text(
                isInviteMode
                    ? 'You\'re invited to\njoin the team'
                    : (_isLogin
                          ? 'Unified inbox\nfor your team'
                          : 'Start your team\'s\nworkspace today'),
                style: AppTheme.headingXl.copyWith(
                  height: 1.15,
                  letterSpacing: -1,
                ),
              ),

              const SizedBox(height: AppTheme.spacing4),

              // Subtitle
              Text(
                isInviteMode
                    ? 'Create your account and start collaborating with your team in minutes.'
                    : (_isLogin
                          ? 'Manage emails, WhatsApp messages, and calendars in one beautiful workspace.'
                          : 'Join thousands of teams using our platform to streamline communication.'),
                style: AppTheme.bodyLg.copyWith(
                  color: AppTheme.textSecondary,
                  height: 1.6,
                ),
              ),

              const SizedBox(height: AppTheme.spacing8),

              // Feature List
              if (isInviteMode) ...[
                _buildFeature(
                  Icons.people_outline,
                  'Team Collaboration',
                  'Access shared inboxes and work together',
                  AppTheme.success,
                ),
                const SizedBox(height: AppTheme.spacing4),
                _buildFeature(
                  Icons.notifications_active_outlined,
                  'Stay Updated',
                  'Get real-time notifications on assignments',
                  AppTheme.success,
                ),
                const SizedBox(height: AppTheme.spacing4),
                _buildFeature(
                  Icons.workspace_premium_outlined,
                  'Premium Tools',
                  'Full access to all team features',
                  AppTheme.success,
                ),
              ] else if (_isLogin) ...[
                _buildFeature(
                  Icons.email_outlined,
                  'Unified Email',
                  'Connect multiple accounts in one inbox',
                  AppTheme.primary,
                ),
                const SizedBox(height: AppTheme.spacing4),
                _buildFeature(
                  Icons.message_outlined,
                  'Team Collaboration',
                  'Share inboxes and assign conversations',
                  AppTheme.primary,
                ),
                const SizedBox(height: AppTheme.spacing4),
                _buildFeature(
                  Icons.insights_outlined,
                  'Smart Organization',
                  'AI-powered filters and custom workflows',
                  AppTheme.primary,
                ),
              ] else ...[
                _buildFeature(
                  Icons.speed_outlined,
                  'Quick Setup',
                  'Get started in minutes with guided onboarding',
                  AppTheme.primary,
                ),
                const SizedBox(height: AppTheme.spacing4),
                _buildFeature(
                  Icons.security_outlined,
                  'Enterprise Security',
                  'Bank-level encryption and data protection',
                  AppTheme.primary,
                ),
                const SizedBox(height: AppTheme.spacing4),
                _buildFeature(
                  Icons.support_agent_outlined,
                  '24/7 Support',
                  'Our team is here to help you succeed',
                  AppTheme.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeature(
    IconData icon,
    String title,
    String description,
    Color color,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: AppTheme.spacing3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTheme.labelLg.copyWith(color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: AppTheme.bodySm.copyWith(color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFormCard() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.all(AppTheme.spacing8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            _buildFormHeader(),

            const SizedBox(height: AppTheme.spacing6),

            // Error Message
            if (_errorMessage != null) _buildErrorBanner(),

            // Invite Banner
            if (!_isLogin && _hasPendingInvite) _buildInviteBanner(),

            // Company Name Field (Signup only, not for invites)
            if (!_isLogin && !_hasPendingInvite) ...[
              _buildInputLabel('Company Name'),
              const SizedBox(height: AppTheme.spacing2),
              _buildTextField(
                controller: _companyController,
                focusNode: _companyFocusNode,
                hintText: 'Acme Inc.',
                prefixIcon: Icons.business_outlined,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                onFieldSubmitted: (_) => _displayNameFocusNode.requestFocus(),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Company name is required'
                    : null,
              ),
              const SizedBox(height: AppTheme.spacing4),
            ],

            // Display Name Field (Signup only)
            if (!_isLogin) ...[
              _buildInputLabel('Your Name'),
              const SizedBox(height: AppTheme.spacing2),
              _buildTextField(
                controller: _displayNameController,
                focusNode: _displayNameFocusNode,
                hintText: 'John Doe',
                prefixIcon: Icons.person_outline,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                onFieldSubmitted: (_) => _emailFocusNode.requestFocus(),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Your name is required'
                    : null,
              ),
              const SizedBox(height: AppTheme.spacing4),
            ],

            // Email Field
            _buildInputLabel('Email'),
            const SizedBox(height: AppTheme.spacing2),
            _buildTextField(
              controller: _emailController,
              focusNode: _emailFocusNode,
              hintText: 'you@company.com',
              prefixIcon: Icons.mail_outline,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => _isLogin
                  ? _passwordFocusNode.requestFocus()
                  : _passwordFocusNode.requestFocus(),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Email is required';
                }
                if (!value.contains('@')) {
                  return 'Enter a valid email';
                }
                return null;
              },
              suffixWidget: _isCheckingInvite
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),

            const SizedBox(height: AppTheme.spacing4),

            // Password Field
            _buildInputLabel('Password'),
            const SizedBox(height: AppTheme.spacing2),
            _buildTextField(
              controller: _passwordController,
              focusNode: _passwordFocusNode,
              hintText: '••••••••',
              prefixIcon: Icons.lock_outline,
              obscureText: _obscurePassword,
              textInputAction: _isLogin
                  ? TextInputAction.done
                  : TextInputAction.next,
              onFieldSubmitted: (_) => _isLogin
                  ? _submit()
                  : _confirmPasswordFocusNode.requestFocus(),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Password is required';
                }
                if (!_isLogin && value.length < 6) {
                  return 'Password must be at least 6 characters';
                }
                return null;
              },
              suffixWidget: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: AppTheme.textMuted,
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),

            // Confirm Password Field (Signup only)
            if (!_isLogin) ...[
              const SizedBox(height: AppTheme.spacing4),
              _buildInputLabel('Confirm Password'),
              const SizedBox(height: AppTheme.spacing2),
              _buildTextField(
                controller: _confirmPasswordController,
                focusNode: _confirmPasswordFocusNode,
                hintText: '••••••••',
                prefixIcon: Icons.lock_outline,
                obscureText: _obscureConfirmPassword,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please confirm your password';
                  }
                  if (value != _passwordController.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
                suffixWidget: IconButton(
                  icon: Icon(
                    _obscureConfirmPassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: AppTheme.textMuted,
                    size: 20,
                  ),
                  onPressed: () => setState(
                    () => _obscureConfirmPassword = !_obscureConfirmPassword,
                  ),
                ),
              ),
            ],

            const SizedBox(height: AppTheme.spacing6),

            // Submit Button
            _buildSubmitButton(),

            const SizedBox(height: AppTheme.spacing4),

            // Toggle Mode Link
            _buildToggleModeLink(),
          ],
        ),
      ),
    );
  }

  Widget _buildFormHeader() {
    String title;
    String subtitle;

    if (_isLogin) {
      title = 'Welcome back';
      subtitle = 'Sign in to your account';
    } else if (_hasPendingInvite) {
      title = 'Join your team';
      subtitle = 'Create your account to accept the invitation';
    } else {
      title = 'Get started';
      subtitle = 'Create your company workspace';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTheme.headingLg),
        const SizedBox(height: AppTheme.spacing1),
        Text(subtitle, style: AppTheme.bodyMd),
      ],
    );
  }

  Widget _buildInviteBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacing4),
      padding: const EdgeInsets.all(AppTheme.spacing4),
      decoration: BoxDecoration(
        color: AppTheme.success.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.success.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_outline, size: 18, color: AppTheme.success),
              const SizedBox(width: AppTheme.spacing2),
              Expanded(
                child: Text(
                  'Invited by $_inviterName',
                  style: AppTheme.bodySm.copyWith(
                    color: AppTheme.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing2),
          Row(
            children: [
              Icon(Icons.business_outlined, size: 18, color: AppTheme.success),
              const SizedBox(width: AppTheme.spacing2),
              Expanded(
                child: Text(
                  _inviteCompanyName ?? 'Your team',
                  style: AppTheme.bodySm.copyWith(color: AppTheme.success),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInputLabel(String label) {
    return Text(
      label,
      style: AppTheme.labelMd.copyWith(color: AppTheme.textPrimary),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
    required IconData prefixIcon,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    TextCapitalization textCapitalization = TextCapitalization.none,
    bool obscureText = false,
    Function(String)? onFieldSubmitted,
    String? Function(String?)? validator,
    Widget? suffixWidget,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      obscureText: obscureText,
      onFieldSubmitted: onFieldSubmitted,
      validator: validator,
      style: AppTheme.bodyMd.copyWith(color: AppTheme.textPrimary),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: AppTheme.bodySm.copyWith(color: AppTheme.textMuted),
        prefixIcon: Icon(prefixIcon, size: 20, color: AppTheme.textMuted),
        suffixIcon: suffixWidget,
        filled: true,
        fillColor: AppTheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          borderSide: BorderSide(color: AppTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          borderSide: BorderSide(color: AppTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          borderSide: BorderSide(color: AppTheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          borderSide: BorderSide(color: AppTheme.error, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacing4),
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: AppTheme.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.error.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: AppTheme.error, size: 20),
          const SizedBox(width: AppTheme.spacing2),
          Expanded(
            child: Text(
              _errorMessage!,
              style: AppTheme.bodySm.copyWith(color: AppTheme.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    String buttonText;
    if (_isLogin) {
      buttonText = 'Sign in';
    } else if (_hasPendingInvite) {
      buttonText = 'Join team';
    } else {
      buttonText = 'Create account';
    }

    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: _hasPendingInvite && !_isLogin
              ? AppTheme.success
              : AppTheme.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor:
              (_hasPendingInvite && !_isLogin
                      ? AppTheme.success
                      : AppTheme.primary)
                  .withOpacity(0.6),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                buttonText,
                style: AppTheme.labelLg.copyWith(color: Colors.white),
              ),
      ),
    );
  }

  Widget _buildToggleModeLink() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _isLogin ? "Don't have an account? " : "Already have an account? ",
          style: AppTheme.bodySm,
        ),
        TextButton(
          onPressed: _toggleMode,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            _isLogin ? 'Create one' : 'Sign in',
            style: AppTheme.labelMd.copyWith(color: AppTheme.primary),
          ),
        ),
      ],
    );
  }
}
