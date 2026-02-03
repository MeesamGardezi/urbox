/**
 * Subscription Routes
 * 
 * Handles:
 * - Checking Pro access
 * - Getting plan details
 * - Admin endpoints for granting/revoking Pro-Free
 * - Feature access checks
 * 
 * Security:
 * - Admin endpoints protected by ADMIN_SECRET
 * - Pro-Free accounts protected from manipulation
 */

const express = require('express');
const SubscriptionService = require('./services/subscription-service');

function createSubscriptionRoutes(db) {
    const router = express.Router();
    const subscriptionService = new SubscriptionService(db);

    /**
     * POST /admin/grant-pro-free
     * Grant Pro-Free status to a company
     * 🔐 ADMIN ONLY - Requires ADMIN_SECRET
     */
    router.post('/admin/grant-pro-free', async (req, res) => {
        const { companyId, adminSecret, reason } = req.body;

        // Validate admin secret
        if (adminSecret !== process.env.ADMIN_SECRET) {
            console.warn('[Subscription] Unauthorized pro-free grant attempt');
            return res.status(403).json({
                success: false,
                error: 'Unauthorized'
            });
        }

        if (!companyId) {
            return res.status(400).json({
                success: false,
                error: 'Missing companyId'
            });
        }

        try {
            const result = await subscriptionService.grantProFree(
                companyId,
                reason || 'Manual admin grant'
            );

            res.json(result);
        } catch (error) {
            console.error('[Subscription] Grant pro-free error:', error);
            res.status(500).json({
                success: false,
                error: error.message
            });
        }
    });

    /**
     * POST /admin/revoke-pro-free
     * Revoke Pro-Free status from a company
     * 🔐 ADMIN ONLY - Requires ADMIN_SECRET
     */
    router.post('/admin/revoke-pro-free', async (req, res) => {
        const { companyId, adminSecret } = req.body;

        // Validate admin secret
        if (adminSecret !== process.env.ADMIN_SECRET) {
            console.warn('[Subscription] Unauthorized pro-free revoke attempt');
            return res.status(403).json({
                success: false,
                error: 'Unauthorized'
            });
        }

        if (!companyId) {
            return res.status(400).json({
                success: false,
                error: 'Missing companyId'
            });
        }

        try {
            const result = await subscriptionService.revokeProFree(companyId);
            res.json(result);
        } catch (error) {
            console.error('[Subscription] Revoke pro-free error:', error);
            res.status(500).json({
                success: false,
                error: error.message
            });
        }
    });

    /**
     * GET /check-access
     * Check if company has Pro access
     */
    router.get('/check-access', async (req, res) => {
        const { companyId } = req.query;

        if (!companyId) {
            return res.status(400).json({
                success: false,
                error: 'Missing companyId'
            });
        }

        try {
            const hasAccess = await subscriptionService.hasProAccess(companyId);
            const planDetails = await subscriptionService.getCompanyPlan(companyId);

            res.json({
                success: true,
                hasProAccess: hasAccess,
                ...planDetails
            });
        } catch (error) {
            console.error('[Subscription] Check access error:', error);
            res.status(500).json({
                success: false,
                error: error.message
            });
        }
    });

    /**
     * GET /plan
     * Get detailed company plan information
     */
    router.get('/plan', async (req, res) => {
        const { companyId } = req.query;

        if (!companyId) {
            return res.status(400).json({
                success: false,
                error: 'Missing companyId'
            });
        }

        try {
            const planDetails = await subscriptionService.getCompanyPlan(companyId);

            res.json({
                success: true,
                ...planDetails
            });
        } catch (error) {
            console.error('[Subscription] Get plan error:', error);
            res.status(500).json({
                success: false,
                error: error.message
            });
        }
    });

    /**
     * GET /feature-access
     * Check if company can access a specific feature
     */
    router.get('/feature-access', async (req, res) => {
        const { companyId, feature } = req.query;

        if (!companyId || !feature) {
            return res.status(400).json({
                success: false,
                error: 'Missing companyId or feature'
            });
        }

        try {
            const hasAccess = await subscriptionService.checkFeatureAccess(companyId, feature);

            res.json({
                success: true,
                feature: feature,
                hasAccess: hasAccess
            });
        } catch (error) {
            console.error('[Subscription] Feature access error:', error);
            res.status(500).json({
                success: false,
                error: error.message
            });
        }
    });

    /**
     * GET /inbox-limit
     * Get inbox creation limit for company
     */
    router.get('/inbox-limit', async (req, res) => {
        const { companyId } = req.query;

        if (!companyId) {
            return res.status(400).json({
                success: false,
                error: 'Missing companyId'
            });
        }

        try {
            const limit = await subscriptionService.getInboxLimit(companyId);
            const canCreate = await subscriptionService.canCreateInbox(companyId);

            res.json({
                success: true,
                limit: limit,
                unlimited: limit === -1,
                canCreateInbox: canCreate.canCreate,
                reason: canCreate.reason,
                message: canCreate.message
            });
        } catch (error) {
            console.error('[Subscription] Inbox limit error:', error);
            res.status(500).json({
                success: false,
                error: error.message
            });
        }
    });

    /**
     * GET /admin/list-pro-free
     * List all Pro-Free companies
     * 🔐 ADMIN ONLY
     */
    router.get('/admin/list-pro-free', async (req, res) => {
        const { adminSecret } = req.query;

        if (adminSecret !== process.env.ADMIN_SECRET) {
            console.warn('[Subscription] Unauthorized list pro-free attempt');
            return res.status(403).json({
                success: false,
                error: 'Unauthorized'
            });
        }

        try {
            const proFreeCompanies = await db.collection('companies')
                .where('isProFree', '==', true)
                .get();

            const companies = proFreeCompanies.docs.map(doc => ({
                id: doc.id,
                name: doc.data().name,
                ownerId: doc.data().ownerId,
                proFreeGrantedAt: doc.data().proFreeGrantedAt,
                proFreeReason: doc.data().proFreeReason
            }));

            res.json({
                success: true,
                count: companies.length,
                companies: companies
            });
        } catch (error) {
            console.error('[Subscription] List pro-free error:', error);
            res.status(500).json({
                success: false,
                error: error.message
            });
        }
    });

    return router;
}

module.exports = createSubscriptionRoutes;