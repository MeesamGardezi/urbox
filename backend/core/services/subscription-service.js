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
     * Now includes companyName for dashboard display
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
                companyName: data.name || 'Your Company',  // Added for dashboard
                plan: data.plan || 'free',
                isFree: data.isFree !== false,
                isProFree: data.isProFree === true,
                subscriptionStatus: data.subscriptionStatus || 'none',
                hasProAccess: hasProAccess,
                canUpgrade: data.plan === 'free' && !data.isProFree,
                stripeCustomerId: data.stripeCustomerId || null,
                memberCount: (await this.db.collection('users').where('companyId', '==', companyId).count().get()).data().count,
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
    async grantProFree(companyId, grantedBy = 'admin') {
        try {
            const docRef = this.db.collection('companies').doc(companyId);
            const doc = await docRef.get();

            if (!doc.exists) {
                throw new Error('Company not found');
            }

            await docRef.update({
                plan: 'pro',
                isProFree: true,
                subscriptionStatus: 'special',
                proFreeGrantedAt: admin.firestore.FieldValue.serverTimestamp(),
                proFreeGrantedBy: grantedBy,
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            });

            console.log(`[Subscription] Pro-Free granted to company ${companyId} by ${grantedBy}`);

            return {
                success: true,
                message: 'Pro-Free status granted successfully'
            };
        } catch (error) {
            console.error('[Subscription] Error granting Pro-Free:', error);
            throw error;
        }
    }

    /**
     * Revoke Pro-Free status
     * 🔐 ADMIN ONLY - Returns company to free plan
     */
    async revokeProFree(companyId) {
        try {
            const docRef = this.db.collection('companies').doc(companyId);
            const doc = await docRef.get();

            if (!doc.exists) {
                throw new Error('Company not found');
            }

            const data = doc.data();

            if (!data.isProFree) {
                return {
                    success: false,
                    message: 'Company does not have Pro-Free status'
                };
            }

            await docRef.update({
                plan: 'free',
                isProFree: false,
                isFree: true,
                subscriptionStatus: 'none',
                proFreeRevokedAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            });

            console.log(`[Subscription] Pro-Free revoked from company ${companyId}`);

            return {
                success: true,
                message: 'Pro-Free status revoked'
            };
        } catch (error) {
            console.error('[Subscription] Error revoking Pro-Free:', error);
            throw error;
        }
    }

    /**
     * Check feature access
     */
    async checkFeatureAccess(companyId, feature) {
        const hasAccess = await this.hasProAccess(companyId);

        // Define which features require Pro
        const proFeatures = [
            'unlimited_inboxes',
            'ai_automation',
            'cloud_storage',
            'whatsapp_integration',
            'priority_support',
            'advanced_analytics'
        ];

        if (proFeatures.includes(feature)) {
            return hasAccess;
        }

        // All other features available to everyone
        return true;
    }

    /**
     * Get inbox limit for company
     */
    async getInboxLimit(companyId) {
        const hasAccess = await this.hasProAccess(companyId);
        return hasAccess ? -1 : 1; // -1 = unlimited
    }

    /**
     * Check if company can create more inboxes
     */
    async canCreateInbox(companyId, currentInboxCount) {
        const limit = await this.getInboxLimit(companyId);

        if (limit === -1) return true; // Unlimited
        return currentInboxCount < limit;
    }

    /**
     * List all Pro-Free companies (admin tool)
     */
    async listProFreeCompanies() {
        try {
            const snapshot = await this.db.collection('companies')
                .where('isProFree', '==', true)
                .get();

            return snapshot.docs.map(doc => ({
                id: doc.id,
                name: doc.data().name,
                grantedAt: doc.data().proFreeGrantedAt,
                grantedBy: doc.data().proFreeGrantedBy
            }));
        } catch (error) {
            console.error('[Subscription] Error listing Pro-Free companies:', error);
            throw error;
        }
    }

    /**
     * Update subscription from Stripe webhook
     */
    async updateFromStripe(companyId, stripeData) {
        try {
            const docRef = this.db.collection('companies').doc(companyId);
            const doc = await docRef.get();

            if (!doc.exists) {
                throw new Error('Company not found');
            }

            // Don't override Pro-Free accounts
            if (doc.data().isProFree) {
                console.log(`[Subscription] Skipping Stripe update for Pro-Free company ${companyId}`);
                return { success: true, message: 'Pro-Free account unchanged' };
            }

            const updateData = {
                stripeCustomerId: stripeData.customerId,
                stripeSubscriptionId: stripeData.subscriptionId,
                subscriptionStatus: stripeData.status,
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            };

            // Update plan based on subscription status
            if (stripeData.status === 'active') {
                updateData.plan = 'pro';
                updateData.isFree = false;
            } else if (['canceled', 'unpaid', 'past_due'].includes(stripeData.status)) {
                updateData.plan = 'free';
                updateData.isFree = true;
            }

            await docRef.update(updateData);

            console.log(`[Subscription] Updated company ${companyId} from Stripe: ${stripeData.status}`);

            return { success: true };
        } catch (error) {
            console.error('[Subscription] Error updating from Stripe:', error);
            throw error;
        }
    }
}

module.exports = SubscriptionService;