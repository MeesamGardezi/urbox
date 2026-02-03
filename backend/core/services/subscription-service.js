/**
 * Subscription Service
 * 
 * Manages subscription plans and access control:
 * - Free plan (1 shared inbox)
 * - Pro plan (unlimited inboxes + premium features)
 * - Pro-Free plan (special forever-free pro access)
 * 
 * Business Rules:
 * - Pro-Free accounts never get downgraded
 * - Regular Pro accounts require active Stripe subscription
 * - All plan changes are backend-controlled
 */

const admin = require('firebase-admin');

class SubscriptionService {
    constructor(db) {
        this.db = db;
        console.log('[Subscription] Service initialized successfully ✓');
    }

    /**
     * Check if company has PRO access
     * Returns true for both paid Pro and Pro-Free accounts
     */
    async hasProAccess(companyId) {
        try {
            const doc = await this.db.collection('companies').doc(companyId).get();

            if (!doc.exists) {
                console.warn(`[Subscription] Company not found: ${companyId}`);
                return false;
            }

            const data = doc.data();

            // Pro-Free accounts always have access
            if (data.isProFree === true) {
                return true;
            }

            // Regular Pro accounts must have active subscription
            if (data.plan === 'pro' && data.subscriptionStatus === 'active') {
                return true;
            }

            return false;
        } catch (error) {
            console.error('[Subscription] Error checking Pro access:', error);
            return false;
        }
    }

    /**
     * Get detailed company plan information
     */
    async getCompanyPlan(companyId) {
        try {
            const doc = await this.db.collection('companies').doc(companyId).get();

            if (!doc.exists) {
                throw new Error('Company not found');
            }

            const data = doc.data();
            const hasProAccess = await this.hasProAccess(companyId);

            return {
                plan: data.plan || 'free',
                isFree: data.isFree !== false,
                isProFree: data.isProFree === true,
                subscriptionStatus: data.subscriptionStatus || 'none',
                hasProAccess: hasProAccess,
                canUpgrade: data.plan === 'free' && !data.isProFree,
                stripeCustomerId: data.stripeCustomerId || null,
            };
        } catch (error) {
            console.error('[Subscription] Error getting plan:', error);
            throw error;
        }
    }

    /**
     * Grant Pro-Free status (special forever-free pro access)
     * 🔐 ADMIN ONLY - Use for VIP customers, partners, etc.
     */
    async grantProFree(companyId, reason = 'Manual grant') {
        try {
            await this.db.collection('companies').doc(companyId).update({
                plan: 'pro',
                isFree: false,
                isProFree: true,
                subscriptionStatus: 'special',
                proFreeGrantedAt: admin.firestore.FieldValue.serverTimestamp(),
                proFreeReason: reason,
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            });

            console.log(`✅ [Subscription] Granted Pro-Free to company: ${companyId} (Reason: ${reason})`);

            return {
                success: true,
                message: 'Pro-Free access granted successfully'
            };
        } catch (error) {
            console.error('[Subscription] Error granting Pro-Free:', error);
            throw error;
        }
    }

    /**
     * Revoke Pro-Free status (downgrade to free plan)
     * 🔐 ADMIN ONLY
     */
    async revokeProFree(companyId) {
        try {
            const doc = await this.db.collection('companies').doc(companyId).get();

            if (!doc.exists) {
                throw new Error('Company not found');
            }

            const data = doc.data();

            if (!data.isProFree) {
                return {
                    success: false,
                    message: 'Company is not a Pro-Free account'
                };
            }

            await this.db.collection('companies').doc(companyId).update({
                plan: 'free',
                isFree: true,
                isProFree: false,
                subscriptionStatus: 'none',
                proFreeRevokedAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            });

            console.log(`⚠️ [Subscription] Revoked Pro-Free from company: ${companyId}`);

            return {
                success: true,
                message: 'Pro-Free access revoked successfully'
            };
        } catch (error) {
            console.error('[Subscription] Error revoking Pro-Free:', error);
            throw error;
        }
    }

    /**
     * Upgrade company to paid Pro plan (via Stripe)
     */
    async upgradeToPro(companyId, stripeCustomerId, stripeSubscriptionId) {
        try {
            const doc = await this.db.collection('companies').doc(companyId).get();

            if (!doc.exists) {
                throw new Error('Company not found');
            }

            const data = doc.data();

            // Don't allow upgrading Pro-Free accounts to paid
            if (data.isProFree === true) {
                return {
                    success: false,
                    message: 'Pro-Free accounts cannot be upgraded to paid plans'
                };
            }

            await this.db.collection('companies').doc(companyId).update({
                plan: 'pro',
                isFree: false,
                isProFree: false,
                subscriptionStatus: 'active',
                stripeCustomerId,
                stripeSubscriptionId,
                upgradedAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            });

            console.log(`✅ [Subscription] Upgraded company to Pro: ${companyId}`);

            return {
                success: true,
                message: 'Successfully upgraded to Pro plan'
            };
        } catch (error) {
            console.error('[Subscription] Error upgrading to Pro:', error);
            throw error;
        }
    }

    /**
     * Downgrade company to free plan (subscription canceled/expired)
     * Pro-Free accounts are protected from downgrade
     */
    async downgradeToFree(companyId) {
        try {
            const doc = await this.db.collection('companies').doc(companyId).get();

            if (!doc.exists) {
                throw new Error('Company not found');
            }

            const data = doc.data();

            // 🔐 CRITICAL: Protect Pro-Free accounts from downgrade
            if (data.isProFree === true) {
                console.log(`⚠️ [Subscription] Cannot downgrade Pro-Free account: ${companyId}`);
                return {
                    success: false,
                    message: 'Pro-Free accounts cannot be downgraded'
                };
            }

            await this.db.collection('companies').doc(companyId).update({
                plan: 'free',
                isFree: true,
                subscriptionStatus: 'canceled',
                downgradedAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            });

            console.log(`⚠️ [Subscription] Downgraded company to Free: ${companyId}`);

            return {
                success: true,
                message: 'Downgraded to Free plan'
            };
        } catch (error) {
            console.error('[Subscription] Error downgrading to Free:', error);
            throw error;
        }
    }

    /**
     * Check if company can access a specific feature
     */
    async checkFeatureAccess(companyId, feature) {
        const hasProAccess = await this.hasProAccess(companyId);

        // Define pro-only features
        const proFeatures = [
            'unlimited_inboxes',
            'ai_automation',
            'cloud_storage',
            'whatsapp_integration',
            'slack_integration',
            'priority_support',
            'advanced_analytics',
            'custom_branding'
        ];

        // If feature is pro-only, check pro access
        if (proFeatures.includes(feature)) {
            return hasProAccess;
        }

        // Free features available to all
        return true;
    }

    /**
     * Get inbox limit based on plan
     */
    async getInboxLimit(companyId) {
        const hasProAccess = await this.hasProAccess(companyId);
        return hasProAccess ? -1 : 1; // -1 means unlimited, 1 means one inbox
    }

    /**
     * Check if company can create another inbox
     */
    async canCreateInbox(companyId) {
        try {
            const limit = await this.getInboxLimit(companyId);

            // Unlimited for pro users
            if (limit === -1) {
                return { canCreate: true, reason: 'unlimited' };
            }

            // Check current inbox count
            const inboxes = await this.db.collection('customInboxes')
                .where('companyId', '==', companyId)
                .get();

            const currentCount = inboxes.size;

            if (currentCount >= limit) {
                return {
                    canCreate: false,
                    reason: 'limit_reached',
                    message: 'Free plan limited to 1 inbox. Upgrade to Pro for unlimited inboxes.'
                };
            }

            return { canCreate: true, reason: 'within_limit' };
        } catch (error) {
            console.error('[Subscription] Error checking inbox creation:', error);
            return { canCreate: false, reason: 'error' };
        }
    }
}

module.exports = SubscriptionService;