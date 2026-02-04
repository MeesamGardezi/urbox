/// Company Model
///
/// Represents a company/organization with subscription information
/// Supports: Free, Pro, and Pro-Free (special forever-free pro) plans
class Company {
  final String id;
  final String name;
  final String ownerId;

  // Subscription Management
  final String plan; // 'free' | 'pro' | 'pro-free'
  final bool isFree;
  final bool isProFree; // Special forever-free pro accounts
  final String subscriptionStatus; // 'active' | 'canceled' | 'none' | 'special'

  // Stripe (only for paying customers)
  final String? stripeCustomerId;
  final String? stripeSubscriptionId;

  // Metadata
  final DateTime createdAt;
  final DateTime updatedAt;

  Company({
    required this.id,
    required this.name,
    required this.ownerId,
    this.plan = 'free',
    this.isFree = true,
    this.isProFree = false,
    this.subscriptionStatus = 'none',
    this.stripeCustomerId,
    this.stripeSubscriptionId,
    required this.createdAt,
    required this.updatedAt,
  });

  // Computed properties
  bool get hasPaidPro => plan == 'pro' && !isProFree;
  bool get hasProAccess => plan == 'pro' || isProFree;
  bool get canUpgrade => plan == 'free' && !isProFree;
  bool get isSpecialAccount => isProFree;

  // Feature limits
  int get inboxLimit => hasProAccess ? -1 : 1; // -1 = unlimited
  bool get hasUnlimitedInboxes => hasProAccess;
  bool get hasAIAutomation => hasProAccess;
  bool get hasCloudStorage => hasProAccess;
  bool get hasWhatsAppIntegration => hasProAccess;
  bool get hasPrioritySupport => hasProAccess;

  Company copyWith({
    String? id,
    String? name,
    String? ownerId,
    String? plan,
    bool? isFree,
    bool? isProFree,
    String? subscriptionStatus,
    String? stripeCustomerId,
    String? stripeSubscriptionId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Company(
      id: id ?? this.id,
      name: name ?? this.name,
      ownerId: ownerId ?? this.ownerId,
      plan: plan ?? this.plan,
      isFree: isFree ?? this.isFree,
      isProFree: isProFree ?? this.isProFree,
      subscriptionStatus: subscriptionStatus ?? this.subscriptionStatus,
      stripeCustomerId: stripeCustomerId ?? this.stripeCustomerId,
      stripeSubscriptionId: stripeSubscriptionId ?? this.stripeSubscriptionId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
