/**
 * Slack Routes
 * Handles Slack authentication and connection management
 */

const express = require('express');
const admin = require('firebase-admin');
const { OAuthManager } = require('../email/oauthManager');
const { SlackService } = require('./slackService');

function createSlackRoutes(db) {
    const router = express.Router();
    const oauthManager = new OAuthManager(db);
    const slackService = new SlackService(oauthManager, db);

    // Middleware to resolve accountId
    const requireAccount = async (req, res, next) => {
        const { accountId } = req.query;
        if (!accountId) {
            // For POST request body check
            if (req.body && req.body.accountId) {
                req.query.accountId = req.body.accountId;
            } else {
                return res.status(400).json({ error: 'Missing accountId' });
            }
        }

        try {
            // Re-check after potential body fallback
            const finalAccountId = req.query.accountId || req.body.accountId;
            if (!finalAccountId) return res.status(400).json({ error: 'Missing accountId' });

            const doc = await db.collection('slackAccounts').doc(finalAccountId).get();
            if (!doc.exists) {
                return res.status(404).json({ error: 'Account not found' });
            }
            req.account = { id: doc.id, ...doc.data() };
            next();
        } catch (err) {
            console.error('[Slack] Middleware error:', err);
            res.status(500).json({ error: 'Internal server error' });
        }
    };

    // ============================================================================
    // ACCOUNT MANAGEMENT
    // ============================================================================

    /**
     * GET /accounts
     * List all connected Slack accounts for a company or user
     */
    router.get('/accounts', async (req, res) => {
        let { companyId, userId } = req.query;

        if (!companyId && !userId) {
            return res.status(400).json({ error: 'Missing companyId or userId' });
        }

        try {
            // Resolve companyId if only userId is provided
            if (!companyId && userId) {
                const userDoc = await db.collection('users').doc(userId).get();
                if (!userDoc.exists) {
                    return res.status(404).json({ error: 'User not found' });
                }
                companyId = userDoc.data().companyId;
            }

            if (!companyId) {
                return res.status(400).json({ error: 'Company ID not found for user' });
            }

            const accounts = await slackService.listAccounts(companyId);
            res.json(accounts);
        } catch (err) {
            console.error('[Slack] List accounts error:', err);
            res.status(500).json({ error: 'Failed to list slack accounts' });
        }
    });

    /**
     * DELETE /accounts/:id
     * Disconnect a Slack account
     */
    router.delete('/accounts/:id', async (req, res) => {
        const { id } = req.params;

        try {
            await slackService.deleteAccount(id);
            res.json({ success: true });
        } catch (err) {
            console.error('[Slack] Delete account error:', err);
            res.status(500).json({ error: 'Failed to disconnect slack account' });
        }
    });

    // ============================================================================
    // OAUTH FLOWS
    // ============================================================================

    /**
     * GET /auth
     * Initiate Slack OAuth flow
     */
    router.get('/auth', async (req, res) => {
        let { companyId, userId } = req.query;

        if (!userId) {
            return res.status(400).send('Missing userId');
        }

        // Resolve companyId logic
        if (!companyId || companyId === 'LOOKUP') {
            const userDoc = await db.collection('users').doc(userId).get();
            if (userDoc.exists) {
                companyId = userDoc.data().companyId;
            }
        }

        if (!companyId) {
            return res.status(400).send('Company ID not found');
        }

        try {
            const state = Buffer.from(JSON.stringify({ companyId, userId })).toString('base64');
            const authUrl = oauthManager.getSlackAuthUrl(state);
            res.redirect(authUrl);
        } catch (error) {
            console.error('[Slack] Auth Init Error:', error);
            res.status(500).send(`Failed to initiate Slack OAuth: ${error.message}`);
        }
    });

    /**
     * GET /auth/callback
     * Handle Slack OAuth callback
     */
    router.get('/auth/callback', async (req, res) => {
        const { code, state, error } = req.query;

        if (error) {
            console.error('[Slack] OAuth Error:', error);
            return res.status(400).send(`Authentication failed: ${error}`);
        }

        if (!code || !state) {
            return res.status(400).send('Missing code or state');
        }

        try {
            const { companyId, userId } = JSON.parse(Buffer.from(state, 'base64').toString());

            const result = await slackService.storeNewAccount(code, companyId, userId);

            // Return success page
            res.send(`
                <html>
                    <body style="font-family: sans-serif; display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100vh; background: linear-gradient(135deg, #4A154B 0%, #36C5F0 100%);">
                        <div style="background: white; padding: 40px; border-radius: 16px; text-align: center; box-shadow: 0 10px 40px rgba(0,0,0,0.2);">
                            <h1 style="color: #22c55e; margin-bottom: 16px;">✓ Slack Connected!</h1>
                            <p style="color: #666; margin-bottom: 8px;">Successfully linked workspace: <strong>${result.teamName}</strong></p>
                            <p style="color: #666; margin-bottom: 8px;">User: <strong>${result.userName}</strong></p>
                            <p style="color: #999; font-size: 14px;">You can close this window.</p>
                            <script>
                                setTimeout(() => window.close(), 3000);
                            </script>
                        </div>
                    </body>
                </html>
            `);

        } catch (error) {
            console.error('[Slack] OAuth Callback Error:', error);
            res.status(500).send(`Authentication failed: ${error.message}`);
        }
    });

    // ============================================================================
    // CHANNEL MANAGEMENT
    // ============================================================================

    /**
     * GET /channels
     * List all Slack channels for this account
     */
    router.get('/channels', requireAccount, async (req, res) => {
        try {
            const channels = await slackService.listConversations(req.account);
            res.json({ channels });
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    /**
     * POST /channels/track
     * Update tracked channels
     */
    router.post('/channels/track', requireAccount, async (req, res) => {
        const { channels } = req.body;

        if (!Array.isArray(channels)) {
            return res.status(400).json({ error: 'channels must be an array' });
        }

        try {
            await db.collection('slackAccounts').doc(req.account.id).update({
                trackedChannels: channels,
                updatedAt: new Date()
            });

            res.json({ success: true, trackedChannels: channels });
        } catch (err) {
            console.error('[Slack] Update Tracked Channels Error:', err);
            res.status(500).json({ error: err.message });
        }
    });

    /**
     * GET /messages
     * Fetch recent messages from all tracked channels in this company
     */
    router.get('/messages', async (req, res) => {
        const { companyId, limit, before } = req.query;

        if (!companyId) {
            return res.status(400).json({ error: 'Missing companyId' });
        }

        try {
            const messages = await slackService.getMessages(
                companyId,
                limit ? parseInt(limit) : 20,
                before
            );
            res.json({ messages });
        } catch (err) {
            console.error('[Slack] Get messages error:', err);
            res.status(500).json({ error: 'Failed to fetch messages' });
        }
    });

    return router;
}

module.exports = createSlackRoutes;
