import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/team_service.dart';
import '../../core/theme/app_theme.dart';

/// Premium Accept Invite Screen - Fortune 500 Design
/// Features split-screen layout, smooth animations, and refined UX
class AcceptInviteScreen extends StatefulWidget {
  final String token;

  const AcceptInviteScreen({super.key, required this.token});

  @override
  State<AcceptInviteScreen> createState() => _AcceptInviteScreenState();
}

class _AcceptInviteScreenState extends State<AcceptInviteScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _displayNameFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _confirmPasswordFocusNode = FocusNode();

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;

  String? _companyName;
  String? _inviterName;
  String? _email;
  bool _inviteValid = false;

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
    _loadInvite();
  }

  @override
  void dispose() {
    _animController.dispose();
    _displayNameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _displayNameFocusNode.dispose();
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadInvite() async {
    try {
      final response = await TeamService.getInvitation(widget.token);

      if (response['email'] != null) {
        setState(() {
          _email = response['email'];
          _companyName = response['companyName'];
          _inviterName = response['inviterName'];
          _inviteValid = true;
          _isLoading = false;
        });
        _animController.forward();
      } else {
        setState(() {
          _errorMessage = response['error'] ?? 'Invalid invitation';
          _isLoading = false;
        });
        _animController.forward();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load invitation';
        _isLoading = false;
      });
      _animController.forward();
    }
  }

  Future<void> _acceptInvite() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final response = await TeamService.acceptInvitation(
        token: widget.token,
        password: _passwordController.text,
        displayName: _displayNameController.text.trim(),
      );

      if (response['success'] == true && response['customToken'] != null) {
        // Sign in with custom token
        await FirebaseAuth.instance.signInWithCustomToken(
          response['customToken'],
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Welcome to $_companyName!'),
              backgroundColor: AppTheme.success,
            ),
          );
          context.go('/');
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = response['error'] ?? 'Failed to accept invitation';
            _isSubmitting = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'An error occurred. Please try again.';
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Loading invitation...',
                style: AppTheme.bodyMd.copyWith(color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
      );
    }

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
                    child: _inviteValid ? _buildFormCard() : _buildErrorCard(),
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
                  color: AppTheme.success,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: const Icon(
                  Icons.mail_outlined,
                  color: Colors.white,
                  size: 32,
                ),
              ),

              const SizedBox(height: AppTheme.spacing8),

              // Headline
              Text(
                'You\'re invited to\njoin the team',
                style: AppTheme.headingXl.copyWith(
                  height: 1.15,
                  letterSpacing: -1,
                ),
              ),

              const SizedBox(height: AppTheme.spacing4),

              // Subtitle
              Text(
                'Create your account and start collaborating with your team in minutes.',
                style: AppTheme.bodyLg.copyWith(
                  color: AppTheme.textSecondary,
                  height: 1.6,
                ),
              ),

              const SizedBox(height: AppTheme.spacing8),

              // Feature List
              _buildFeature(
                Icons.people_outline,
                'Team Collaboration',
                'Access shared inboxes and work together',
              ),
              const SizedBox(height: AppTheme.spacing4),
              _buildFeature(
                Icons.notifications_active_outlined,
                'Stay Updated',
                'Get real-time notifications on assignments',
              ),
              const SizedBox(height: AppTheme.spacing4),
              _buildFeature(
                Icons.workspace_premium_outlined,
                'Premium Tools',
                'Full access to all team features',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeature(IconData icon, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.success.withOpacity(0.1),
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          ),
          child: Icon(icon, size: 20, color: AppTheme.success),
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

            // Invite Banner
            _buildInviteBanner(),

            const SizedBox(height: AppTheme.spacing6),

            // Error Message
            if (_errorMessage != null) _buildErrorBanner(),

            // Display Name Field
            _buildInputLabel('Your Name'),
            const SizedBox(height: AppTheme.spacing2),
            _buildTextField(
              controller: _displayNameController,
              focusNode: _displayNameFocusNode,
              hintText: 'John Doe',
              prefixIcon: Icons.person_outline,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              onFieldSubmitted: (_) => _passwordFocusNode.requestFocus(),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your name';
                }
                return null;
              },
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
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => _confirmPasswordFocusNode.requestFocus(),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a password';
                }
                if (value.length < 6) {
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

            const SizedBox(height: AppTheme.spacing4),

            // Confirm Password Field
            _buildInputLabel('Confirm Password'),
            const SizedBox(height: AppTheme.spacing2),
            _buildTextField(
              controller: _confirmPasswordController,
              focusNode: _confirmPasswordFocusNode,
              hintText: '••••••••',
              prefixIcon: Icons.lock_outline,
              obscureText: _obscureConfirmPassword,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _acceptInvite(),
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

            const SizedBox(height: AppTheme.spacing6),

            // Submit Button
            _buildSubmitButton(),

            const SizedBox(height: AppTheme.spacing4),

            // Login Link
            _buildLoginLink(),
          ],
        ),
      ),
    );
  }

  Widget _buildFormHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Join your team', style: AppTheme.headingLg),
        const SizedBox(height: AppTheme.spacing1),
        Text(
          'Create your account to join $_companyName',
          style: AppTheme.bodyMd,
        ),
      ],
    );
  }

  Widget _buildInviteBanner() {
    return Container(
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
              Icon(Icons.email_outlined, size: 18, color: AppTheme.success),
              const SizedBox(width: AppTheme.spacing2),
              Expanded(
                child: Text(
                  _email!,
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
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _acceptInvite,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.success,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppTheme.success.withOpacity(0.6),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          ),
        ),
        child: _isSubmitting
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                'Create Account & Join Team',
                style: AppTheme.labelLg.copyWith(color: Colors.white),
              ),
      ),
    );
  }

  Widget _buildLoginLink() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Already have an account? ', style: AppTheme.bodySm),
        TextButton(
          onPressed: () => context.go('/login'),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            'Sign in',
            style: AppTheme.labelMd.copyWith(color: AppTheme.primary),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorCard() {
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.error.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            ),
            child: Icon(Icons.error_outline, size: 48, color: AppTheme.error),
          ),
          const SizedBox(height: AppTheme.spacing6),
          Text(
            'Invalid Invitation',
            style: AppTheme.headingMd.copyWith(color: AppTheme.error),
          ),
          const SizedBox(height: AppTheme.spacing2),
          Text(
            _errorMessage ?? 'This invitation link is invalid or has expired.',
            style: AppTheme.bodyMd.copyWith(color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.spacing6),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => context.go('/login'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
              ),
              child: Text(
                'Go to Login',
                style: AppTheme.labelLg.copyWith(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
