import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../models/company.dart';
import '../services/payment_service.dart';

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  final user = FirebaseAuth.instance.currentUser;
  Company? _company;
  bool _isLoading = true;
  String? _companyId;

  @override
  void initState() {
    super.initState();
    _loadCompany();
  }

  Future<void> _loadCompany() async {
    if (user == null) return;

    try {
      // Get user's company ID
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .get();

      if (userDoc.exists) {
        _companyId = userDoc.data()?['companyId'];

        if (_companyId != null) {
          final companyDoc = await FirebaseFirestore.instance
              .collection('companies')
              .doc(_companyId)
              .get();

          if (companyDoc.exists) {
            _company = Company.fromFirestore(companyDoc);
          }
        }
      }

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleUpgrade() async {
    if (_companyId == null) return;

    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => const Center(child: CircularProgressIndicator()),
      );

      // Create checkout session
      final checkoutUrl = await PaymentService.createCheckoutSession(
        companyId: _companyId!,
      );

      if (mounted) Navigator.of(context).pop();

      if (checkoutUrl != null) {
        // Launch Stripe checkout
        final uri = Uri.parse(checkoutUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to create checkout session'),
              backgroundColor: AppTheme.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _handleManageSubscription() async {
    if (_companyId == null) return;

    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => const Center(child: CircularProgressIndicator()),
      );

      // Create portal session
      final portalUrl = await PaymentService.createPortalSession(
        companyId: _companyId!,
      );

      if (mounted) Navigator.of(context).pop();

      if (portalUrl != null) {
        // Launch Stripe portal
        final uri = Uri.parse(portalUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to open customer portal'),
              backgroundColor: AppTheme.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Plans & Pricing', style: AppTheme.headingMd),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppTheme.spacing6),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: Column(
                    children: [
                      // Header
                      Text(
                        'Choose the right plan for your team',
                        style: AppTheme.headingXl,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppTheme.spacing3),
                      Text(
                        'Start free, upgrade when you\'re ready',
                        style: AppTheme.bodyLg.copyWith(
                          color: AppTheme.textMuted,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: AppTheme.spacing12),

                      // Plans
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Free Plan
                          Expanded(
                            child: _buildPlanCard(
                              name: 'Free',
                              price: '\$0',
                              period: '/forever',
                              features: [
                                '1 Shared Inbox',
                                'Unlimited Team Members',
                                'Basic Email Management',
                                'Standard Support',
                              ],
                              gradient: AppTheme.successGradient,
                              isCurrentPlan: _company?.plan == 'free',
                              onSelect: null, // Can't downgrade
                            ),
                          ),

                          const SizedBox(width: AppTheme.spacing6),

                          // Pro Plan
                          Expanded(
                            child: _buildPlanCard(
                              name: 'Pro',
                              price: '\$29',
                              period: '/month',
                              features: [
                                'Unlimited Shared Inboxes',
                                'AI-Powered Automation',
                                'Cloud Storage Integration',
                                'WhatsApp Integration',
                                'Slack Integration',
                                'Priority 24/7 Support',
                                'Advanced Analytics',
                              ],
                              gradient: AppTheme.primaryGradient,
                              isCurrentPlan: _company?.hasProAccess == true,
                              isPro: true,
                              isProFree: _company?.isProFree == true,
                              onSelect: _company?.hasProAccess == true
                                  ? _handleManageSubscription
                                  : _handleUpgrade,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: AppTheme.spacing12),

                      // FAQ or Additional Info
                      _buildFaqSection(),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildPlanCard({
    required String name,
    required String price,
    required String period,
    required List<String> features,
    required LinearGradient gradient,
    required bool isCurrentPlan,
    bool isPro = false,
    bool isProFree = false,
    VoidCallback? onSelect,
  }) {
    return Card(
      elevation: isPro ? 8 : 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(AppTheme.spacing6),
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppTheme.radiusLg),
                topRight: Radius.circular(AppTheme.radiusLg),
              ),
            ),
            child: Column(
              children: [
                if (isPro)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacing3,
                      vertical: AppTheme.spacing1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    ),
                    child: Text(
                      'MOST POPULAR',
                      style: AppTheme.labelSm.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const SizedBox(height: AppTheme.spacing2),
                Text(
                  name,
                  style: AppTheme.headingLg.copyWith(color: Colors.white),
                ),
                const SizedBox(height: AppTheme.spacing2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      price,
                      style: AppTheme.headingXl.copyWith(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: AppTheme.spacing3),
                      child: Text(
                        period,
                        style: AppTheme.bodyMd.copyWith(
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ),
                  ],
                ),
                if (isProFree) ...[
                  const SizedBox(height: AppTheme.spacing2),
                  Container(
                    padding: const EdgeInsets.all(AppTheme.spacing2),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star, color: Colors.white, size: 16),
                        const SizedBox(width: AppTheme.spacing1),
                        Text(
                          'Forever Free VIP Access',
                          style: AppTheme.labelSm.copyWith(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Features
          Padding(
            padding: const EdgeInsets.all(AppTheme.spacing6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...features.map(
                  (feature) => Padding(
                    padding: const EdgeInsets.only(bottom: AppTheme.spacing3),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: isPro ? AppTheme.primary : AppTheme.success,
                          size: 20,
                        ),
                        const SizedBox(width: AppTheme.spacing2),
                        Expanded(child: Text(feature, style: AppTheme.bodyMd)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.spacing4),

                // Action Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: isCurrentPlan
                      ? OutlinedButton(
                          onPressed: isPro ? onSelect : null,
                          child: Text(
                            isProFree
                                ? 'Current Plan (VIP)'
                                : isPro
                                ? 'Manage Subscription'
                                : 'Current Plan',
                          ),
                        )
                      : ElevatedButton(
                          onPressed: onSelect,
                          child: Text(isPro ? 'Upgrade to Pro' : 'Select Plan'),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFaqSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacing6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Frequently Asked Questions', style: AppTheme.headingMd),
            const SizedBox(height: AppTheme.spacing4),
            _buildFaqItem(
              question: 'Can I cancel anytime?',
              answer:
                  'Yes! You can cancel your Pro subscription at any time from the customer portal.',
            ),
            const Divider(height: AppTheme.spacing6),
            _buildFaqItem(
              question: 'What happens when I upgrade?',
              answer:
                  'You get immediate access to all Pro features including unlimited inboxes, AI automation, and priority support.',
            ),
            const Divider(height: AppTheme.spacing6),
            _buildFaqItem(
              question: 'Is my data secure?',
              answer:
                  'Absolutely! All data is encrypted using industry-standard AES-256 encryption, and we never store your email passwords.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFaqItem({required String question, required String answer}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question,
          style: AppTheme.labelMd.copyWith(color: AppTheme.textPrimary),
        ),
        const SizedBox(height: AppTheme.spacing2),
        Text(
          answer,
          style: AppTheme.bodySm.copyWith(color: AppTheme.textMuted),
        ),
      ],
    );
  }
}
