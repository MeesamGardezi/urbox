import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';
import '../models/company.dart';
import '../services/subscription_service.dart';
import '../../auth/services/auth_service.dart';

/// Plans & Billing Screen - Fortune 500 Design
///
/// Features:
/// - Premium pricing cards with gradient accents
/// - Feature comparison table
/// - Current plan status
/// - Smooth animations and hover effects
/// - Professional corporate aesthetic
class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  final user = FirebaseAuth.instance.currentUser;
  Company? _company;
  bool _isLoading = true;
  bool _isAnnual = true; // Toggle between monthly/annual pricing

  @override
  void initState() {
    super.initState();
    _loadCompanyData();
  }

  Future<void> _loadCompanyData() async {
    if (user == null) return;

    try {
      final userResponse = await AuthService.getUserProfile(user!.uid);

      if (userResponse['success'] != true) {
        throw Exception(userResponse['error'] ?? 'Failed to load user profile');
      }

      final userData = userResponse['user'] as Map<String, dynamic>;
      final companyId = userData['companyId'] as String?;

      if (companyId != null && companyId.isNotEmpty) {
        final response = await SubscriptionService.getCompanyPlan(companyId);

        if (response['success'] == true && response['company'] != null) {
          final data = response['company'] as Map<String, dynamic>;

          _company = Company(
            id: companyId,
            name: data['companyName']?.toString() ?? 'Your Company',
            ownerId: '',
            plan: data['plan']?.toString() ?? 'free',
            isFree: data['isFree'] == true,
            isProFree: data['isProFree'] == true,
            subscriptionStatus:
                data['subscriptionStatus']?.toString() ?? 'none',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
        }
      }

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading company data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.spacing6),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              const SizedBox(height: AppTheme.spacing5),
              if (_company != null) _buildCurrentPlanBanner(context),
              if (_company != null) const SizedBox(height: AppTheme.spacing5),
              _buildPricingToggle(context),
              const SizedBox(height: AppTheme.spacing5),
              _buildPricingCards(context),
              const SizedBox(height: AppTheme.spacing8),
              _buildFeatureComparison(context),
              const SizedBox(height: AppTheme.spacing6),
              _buildFAQ(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;
    final mutedColor = isDark ? AppTheme.gray400 : AppTheme.textMuted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Plans & Billing',
          style: AppTheme.headingXl.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: textColor,
          ),
        ),
        const SizedBox(height: AppTheme.spacing2),
        Text(
          'Choose the perfect plan for your team. Upgrade, downgrade, or cancel anytime.',
          style: AppTheme.bodyMd.copyWith(color: mutedColor, height: 1.5),
        ),
      ],
    );
  }

  Widget _buildCurrentPlanBanner(BuildContext context) {
    final isProFree = _company!.isProFree;
    final hasPro = _company!.hasProAccess;
    final isFree = _company!.isFree;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;
    final mutedColor = isDark ? AppTheme.gray400 : AppTheme.textMuted;

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing4),
      decoration: BoxDecoration(
        gradient: isProFree || hasPro
            ? AppTheme.primaryGradient
            : LinearGradient(
                colors: isDark
                    ? [AppTheme.gray800, AppTheme.gray900]
                    : [AppTheme.gray100, AppTheme.gray50],
              ),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(
          color: isProFree || hasPro
              ? Colors.transparent
              : (isDark ? AppTheme.gray700 : AppTheme.border),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppTheme.spacing3),
            decoration: BoxDecoration(
              color: (isProFree || hasPro)
                  ? Colors.white.withOpacity(0.2)
                  : (isDark ? AppTheme.gray800 : Colors.white),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Icon(
              isProFree || hasPro ? Icons.workspace_premium : Icons.inbox,
              color: isProFree || hasPro ? Colors.white : AppTheme.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isProFree
                      ? 'Pro Plan (Forever Free)'
                      : hasPro
                      ? 'Pro Plan - Active'
                      : 'Free Plan',
                  style: AppTheme.labelLg.copyWith(
                    color: isProFree || hasPro ? Colors.white : textColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isProFree
                      ? 'You have special VIP access with all Pro features'
                      : hasPro
                      ? 'Enjoying unlimited inboxes and premium features'
                      : 'Limited to 1 shared inbox',
                  style: AppTheme.bodySm.copyWith(
                    color: isProFree || hasPro
                        ? Colors.white.withOpacity(0.9)
                        : mutedColor,
                  ),
                ),
              ],
            ),
          ),
          if (isFree && !isProFree)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1,
              ),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(AppTheme.radiusFull),
              ),
              child: Text(
                'Current Plan',
                style: AppTheme.labelSm.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPricingToggle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.gray800 : AppTheme.gray100,
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildToggleButton(context, 'Monthly', !_isAnnual, () {
              setState(() => _isAnnual = false);
            }),
            _buildToggleButton(context, 'Annual (Save 20%)', _isAnnual, () {
              setState(() => _isAnnual = true);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleButton(
    BuildContext context,
    String label,
    bool isSelected,
    VoidCallback onTap,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;
    final mutedColor = isDark ? AppTheme.gray400 : AppTheme.textMuted;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing6,
          vertical: AppTheme.spacing3,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? AppTheme.gray700 : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: AppTheme.labelMd.copyWith(
            color: isSelected ? textColor : mutedColor,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildPricingCards(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _buildPricingCard(
            context,
            name: 'Free',
            price: _isAnnual ? '\$0' : '\$0',
            period: 'forever',
            description: 'Perfect for getting started',
            features: [
              '1 shared inbox',
              'Up to 3 team members',
              'Email integration (Gmail, Outlook)',
              'Basic support',
              'Mobile apps',
            ],
            isPopular: false,
            onSelect: () {},
            isCurrent: _company?.isFree == true && !_company!.isProFree,
          ),
        ),
        const SizedBox(width: AppTheme.spacing6),
        Expanded(
          child: _buildPricingCard(
            context,
            name: 'Pro',
            price: _isAnnual ? '\$20' : '\$25',
            period: _isAnnual ? 'per user/month' : 'per user/month',
            description: 'Everything you need to scale',
            features: [
              'Unlimited shared inboxes',
              'Unlimited team members',
              'Advanced email rules & filters',
              'Priority support',
              'Custom integrations',
              'Advanced analytics',
              'SLA guarantee',
            ],
            isPopular: true,
            onSelect: () => _handleUpgrade(),
            isCurrent: _company?.hasProAccess == true,
          ),
        ),
      ],
    );
  }

  Widget _buildPricingCard(
    BuildContext context, {
    required String name,
    required String price,
    required String period,
    required String description,
    required List<String> features,
    required bool isPopular,
    required VoidCallback onSelect,
    bool isCurrent = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;
    final mutedColor = isDark ? AppTheme.gray400 : AppTheme.textMuted;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: Card(
        elevation: isPopular ? 4 : 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          side: BorderSide(
            color: isPopular ? AppTheme.primary : AppTheme.border,
            width: isPopular ? 2 : 1,
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(AppTheme.spacing5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isPopular)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacing2,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  ),
                  child: Text(
                    'MOST POPULAR',
                    style: AppTheme.labelSm.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      fontSize: 10,
                    ),
                  ),
                ),
              if (isPopular) const SizedBox(height: AppTheme.spacing3),

              Text(
                name,
                style: AppTheme.headingMd.copyWith(
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
              const SizedBox(height: AppTheme.spacing1),
              Text(
                description,
                style: AppTheme.bodySm.copyWith(color: mutedColor),
              ),
              const SizedBox(height: AppTheme.spacing4),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    price,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacing1),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      period,
                      style: AppTheme.bodySm.copyWith(color: mutedColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacing4),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isCurrent ? null : onSelect,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isPopular
                        ? AppTheme.primary
                        : AppTheme.gray800,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppTheme.spacing3,
                    ),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    ),
                  ),
                  child: Text(
                    isCurrent ? 'Current Plan' : 'Get Started',
                    style: AppTheme.labelMd.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: AppTheme.spacing4),
              const Divider(),
              const SizedBox(height: AppTheme.spacing3),

              ...features
                  .map(
                    (feature) => Padding(
                      padding: const EdgeInsets.only(bottom: AppTheme.spacing2),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: AppTheme.success,
                            size: 16,
                          ),
                          const SizedBox(width: AppTheme.spacing2),
                          Expanded(
                            child: Text(
                              feature,
                              style: AppTheme.bodySm.copyWith(color: textColor),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureComparison(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;
    final mutedColor = isDark ? AppTheme.gray400 : AppTheme.textMuted;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacing5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Compare Plans',
              style: AppTheme.headingMd.copyWith(
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
            const SizedBox(height: AppTheme.spacing1),
            Text(
              'See what\'s included in each plan',
              style: AppTheme.bodySm.copyWith(color: mutedColor),
            ),
            const SizedBox(height: AppTheme.spacing4),

            Table(
              columnWidths: const {
                0: FlexColumnWidth(3),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(1),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.gray800 : AppTheme.gray50,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  ),
                  children: [
                    _buildTableHeader(context, 'Feature'),
                    _buildTableHeader(context, 'Free'),
                    _buildTableHeader(context, 'Pro'),
                  ],
                ),
                ..._buildComparisonRows(context),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<TableRow> _buildComparisonRows(BuildContext context) {
    final features = [
      {'name': 'Shared Inboxes', 'free': '1', 'pro': 'Unlimited'},
      {'name': 'Team Members', 'free': '3', 'pro': 'Unlimited'},
      {'name': 'Email Integration', 'free': true, 'pro': true},
      {'name': 'Mobile Apps', 'free': true, 'pro': true},
      {'name': 'Advanced Rules & Filters', 'free': false, 'pro': true},
      {'name': 'Custom Integrations', 'free': false, 'pro': true},
      {'name': 'Priority Support', 'free': false, 'pro': true},
      {'name': 'Advanced Analytics', 'free': false, 'pro': true},
      {'name': 'SLA Guarantee', 'free': false, 'pro': true},
    ];

    return features.map((feature) {
      return TableRow(
        children: [
          _buildTableCell(context, feature['name'] as String, isHeader: true),
          _buildTableCell(context, feature['free'], centered: true),
          _buildTableCell(context, feature['pro'], centered: true),
        ],
      );
    }).toList();
  }

  Widget _buildTableHeader(BuildContext context, String text) {
    final textColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;

    return Padding(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      child: Text(
        text,
        style: AppTheme.labelSm.copyWith(
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
        textAlign: text == 'Feature' ? TextAlign.left : TextAlign.center,
      ),
    );
  }

  Widget _buildTableCell(
    BuildContext context,
    dynamic value, {
    bool isHeader = false,
    bool centered = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;
    final mutedColor = isDark ? AppTheme.gray400 : AppTheme.textMuted;

    Widget content;

    if (value is bool) {
      content = Icon(
        value ? Icons.check_circle : Icons.remove_circle_outline,
        color: value ? AppTheme.success : mutedColor,
        size: 16,
      );
    } else {
      content = Text(
        value.toString(),
        style: isHeader
            ? AppTheme.bodySm.copyWith(
                fontWeight: FontWeight.w500,
                color: textColor,
              )
            : AppTheme.bodySm.copyWith(color: mutedColor),
        textAlign: centered ? TextAlign.center : TextAlign.left,
      );
    }

    return Padding(
      padding: const EdgeInsets.all(AppTheme.spacing2),
      child: centered ? Center(child: content) : content,
    );
  }

  Widget _buildFAQ(BuildContext context) {
    final textColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacing5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Frequently Asked Questions',
              style: AppTheme.headingMd.copyWith(
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
            const SizedBox(height: AppTheme.spacing4),

            _buildFAQItem(
              context,
              question: 'Can I change plans anytime?',
              answer:
                  'Yes! You can upgrade, downgrade, or cancel your plan at any time. Changes take effect immediately.',
            ),
            _buildFAQItem(
              context,
              question: 'Is there a free trial?',
              answer:
                  'Our Free plan is available forever with no credit card required. Upgrade to Pro anytime to unlock unlimited features.',
            ),
            _buildFAQItem(
              context,
              question: 'How does billing work?',
              answer:
                  'We bill monthly or annually based on your selection. Annual plans save 20% compared to monthly billing.',
            ),
            _buildFAQItem(
              context,
              question: 'What payment methods do you accept?',
              answer:
                  'We accept all major credit cards (Visa, Mastercard, American Express) and PayPal.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFAQItem(
    BuildContext context, {
    required String question,
    required String answer,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;
    final mutedColor = isDark ? AppTheme.gray400 : AppTheme.textMuted;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacing4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question,
            style: AppTheme.labelMd.copyWith(
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          const SizedBox(height: AppTheme.spacing1),
          Text(
            answer,
            style: AppTheme.bodySm.copyWith(color: mutedColor, height: 1.5),
          ),
        ],
      ),
    );
  }

  void _handleUpgrade() {
    // TODO: Implement Stripe checkout
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Upgrade functionality coming soon!'),
        action: SnackBarAction(label: 'OK', onPressed: () {}),
      ),
    );
  }
}
