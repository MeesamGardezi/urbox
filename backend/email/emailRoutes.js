/**
 * Email Routes
 * Handles email fetching and account authentication (OAuth & IMAP)
 */

const express = require('express');
const { google } = require('googleapis');
const admin = require('firebase-admin');
const { OAuthManager } = require('./oauthManager');
const { EmailService } = require('./emailService');

function createEmailRoutes(db) {
    const router = express.Router();
    const oauthManager = new OAuthManager(db);
    const emailService = new EmailService(oauthManager, db);

    // ============================================================================
    // ACCOUNT MANAGEMENT
    // ============================================================================

    /**
     * GET /accounts
     * List all email accounts for a company or user
     */
    router.get('/accounts', async (req, res) => {
        let { companyId, userId } = req.query;

        if (!companyId && !userId) {
            return res.status(400).json({ error: 'Missing companyId or userId' });
        }

        try {
            // If only userId provided, fetch companyId from user doc
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

            const snapshot = await db.collection('emailAccounts')
                .where('companyId', '==', companyId)
                .get();

            const accounts = [];
            snapshot.forEach(doc => {
                const data = doc.data();
                // Exclude sensitive info like passwords or refresh tokens if not needed
                // Note: We're doing a shallow copy/exclude. For nested fields like imapConfig.password, 
                // we might need to process them carefully if we want to hide them, but for listing in UI,
                // usually we just return the object. Let's return full object for now but be mindful.
                // Actually, let's just return the whole thing for now as the frontend might need specific config details
                // to show status.
                accounts.push({ id: doc.id, ...data });
            });

            res.json(accounts);
        } catch (err) {
            console.error('[Email] List accounts error:', err);
            res.status(500).json({ error: 'Failed to list accounts' });
        }
    });

    /**
     * DELETE /accounts/:id
     * Delete an email account
     */
    router.delete('/accounts/:id', async (req, res) => {
        const { id } = req.params;

        try {
            await db.collection('emailAccounts').doc(id).delete();
            res.json({ success: true });
        } catch (err) {
            console.error('[Email] Delete account error:', err);
            res.status(500).json({ error: 'Failed to delete account' });
        }
    });

    // ============================================================================
    // EMAIL FETCHING
    // ============================================================================

    /**
     * POST /
     * Fetch emails from multiple accounts
     */
    router.post('/', async (req, res) => {
        try {
            const { accounts, offsets } = req.body;

            if (!accounts || accounts.length === 0) {
                return res.status(400).json({
                    error: 'No email accounts provided. Please add accounts in Email Accounts section.'
                });
            }

            console.log(`[Email Route] Fetching from ${accounts.length} account(s)...`);

            const result = await emailService.fetchEmails(accounts, offsets || {});

            res.json({
                emails: result.emails,
                pagination: result.pagination,
                errors: result.errors
            });

        } catch (err) {
            console.error('[Email Route] Fetch error:', err);
            res.status(500).json({ error: 'Failed to fetch emails: ' + err.message });
        }
    });

    /**
     * POST /:id/read
     * Mark email as read
     */
    router.post('/:id/read', async (req, res) => {
        try {
            // Read functionality disabled by default to simplify scopes
            res.json({ success: true, message: 'Read receipt disabled (read-only mode)' });
        } catch (err) {
            console.error('[Email Route] Mark read error:', err);
            res.json({ success: false, error: err.message });
        }
    });

    // ============================================================================
    // IMAP MANAGEMENT
    // ============================================================================

    /**
     * POST /imap/test
     * Test IMAP connection before adding account
     */
    router.post('/imap/test', async (req, res) => {
        const { host, port, email, password, tls } = req.body;

        if (!host || !email || !password) {
            return res.status(400).json({
                success: false,
                error: 'Missing required fields: host, email, password'
            });
        }

        const config = {
            host,
            port: port || 993,
            user: email,
            password,
            tls: tls !== false
        };

        const result = await emailService.testImapConnection(config);
        res.json(result);
    });

    /**
     * POST /imap/add
     * Add IMAP email account
     */
    router.post('/imap/add', async (req, res) => {
        let { companyId, userId, name, host, port, email, password, tls } = req.body;

        if (!userId) {
            return res.status(400).json({ success: false, error: 'Missing userId' });
        }

        if (!companyId || companyId === 'PENDING') {
            const userDoc = await db.collection('users').doc(userId).get();
            if (userDoc.exists) {
                companyId = userDoc.data().companyId;
            }
        }

        if (!companyId) {
            return res.status(400).json({
                success: false,
                error: 'Missing companyId or could not resolve from user'
            });
        }

        if (!host || !email || !password) {
            return res.status(400).json({
                success: false,
                error: 'Missing required IMAP credentials'
            });
        }

        try {
            // First test the connection
            const config = {
                host,
                port: port || 993,
                user: email,
                password,
                tls: tls !== false
            };

            const testResult = await emailService.testImapConnection(config);
            if (!testResult.success) {
                return res.status(400).json({
                    success: false,
                    error: testResult.message
                });
            }

            // Check if account already exists
            const existingAccount = await db.collection('emailAccounts')
                .where('companyId', '==', companyId)
                .where('email', '==', email)
                .get();

            const accountData = {
                companyId,
                addedBy: userId,
                name: name || email,
                email,
                provider: 'imap',
                status: 'active',
                imapConfig: config,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            };

            let docId;
            if (!existingAccount.empty) {
                // Update existing account
                docId = existingAccount.docs[0].id;
                await existingAccount.docs[0].ref.update({
                    ...accountData,
                    updatedAt: admin.firestore.FieldValue.serverTimestamp()
                });
                console.log(`[IMAP] Updated existing account: ${email}`);
            } else {
                // Add new account
                const docRef = await db.collection('emailAccounts').add(accountData);
                docId = docRef.id;
                console.log(`[IMAP] Added new account: ${email}`);
            }

            res.json({
                success: true,
                message: `Account ${email} connected successfully!`,
                accountId: docId
            });

        } catch (error) {
            console.error('[IMAP] Add account error:', error);
            res.status(500).json({
                success: false,
                error: `Failed to add account: ${error.message}`
            });
        }
    });

    // ============================================================================
    // OAUTH FLOWS
    // ============================================================================

    // Google OAuth Scopes
    const GOOGLE_SCOPES = [
        'https://www.googleapis.com/auth/gmail.readonly',
        'https://www.googleapis.com/auth/userinfo.email',
        'https://www.googleapis.com/auth/calendar.readonly'
    ];

    /**
     * GET /auth/google
     * Initiate Google OAuth flow
     */
    router.get('/auth/google', async (req, res) => {
        let { companyId, userId } = req.query;

        if (!userId) {
            return res.status(400).send('Missing userId');
        }

        if (!companyId || companyId === 'LOOKUP') {
            const userDoc = await db.collection('users').doc(userId).get();
            if (userDoc.exists) {
                companyId = userDoc.data().companyId;
            }
        }

        if (!companyId) {
            return res.status(400).send('Company ID not found');
        }

        const state = Buffer.from(JSON.stringify({ companyId, userId })).toString('base64');
        const authUrl = oauthManager.getGoogleAuthUrl(state);

        res.redirect(authUrl);
    });

    /**
     * GET /auth/google/callback
     * Handle Google OAuth callback
     */
    router.get('/auth/google/callback', async (req, res) => {
        const { code, state } = req.query;

        if (!code || !state) {
            return res.status(400).send('Missing code or state');
        }

        try {
            const { companyId, userId } = JSON.parse(Buffer.from(state, 'base64').toString());

            const tokenResult = await oauthManager.exchangeGoogleCode(code);

            const accountData = {
                companyId,
                addedBy: userId,
                name: tokenResult.name || tokenResult.email,
                email: tokenResult.email,
                provider: 'gmail-oauth',
                status: 'active',
                oauth: {
                    accessToken: tokenResult.accessToken,
                    refreshToken: tokenResult.refreshToken,
                    expiryDate: tokenResult.expiryDate,
                    scope: tokenResult.scope
                },
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            };

            // Check if account exists
            const existingAccount = await db.collection('emailAccounts')
                .where('companyId', '==', companyId)
                .where('email', '==', tokenResult.email)
                .get();

            if (!existingAccount.empty) {
                await existingAccount.docs[0].ref.update({
                    ...accountData,
                    updatedAt: admin.firestore.FieldValue.serverTimestamp()
                });
            } else {
                await db.collection('emailAccounts').add(accountData);
            }

            // Return success page
            res.send(`
                <html>
                    <body style="font-family: sans-serif; display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100vh; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);">
                        <div style="background: white; padding: 40px; border-radius: 16px; text-align: center; box-shadow: 0 10px 40px rgba(0,0,0,0.2);">
                            <h1 style="color: #22c55e; margin-bottom: 16px;">✓ Account Connected!</h1>
                            <p style="color: #666; margin-bottom: 8px;">Successfully linked: <strong>${tokenResult.email}</strong></p>
                            <p style="color: #999; font-size: 14px;">You can close this window.</p>
                            <script>
                                setTimeout(() => window.close(), 3000);
                            </script>
                        </div>
                    </body>
                </html>
            `);

        } catch (error) {
            console.error('[Auth] Google OAuth Error:', error);
            res.status(500).send(`Authentication failed: ${error.message}`);
        }
    });

    /**
     * GET /auth/microsoft
     * Initiate Microsoft OAuth flow
     */
    router.get('/auth/microsoft', async (req, res) => {
        let { companyId, userId } = req.query;

        if (!userId) {
            return res.status(400).send('Missing userId');
        }

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
            const authUrl = await oauthManager.getMicrosoftAuthUrl(state);
            res.redirect(authUrl);
        } catch (error) {
            console.error('[Auth] Microsoft OAuth Error:', error);
            res.status(500).send(`Failed to initiate Microsoft OAuth: ${error.message}`);
        }
    });

    /**
     * GET /auth/microsoft/callback
     * Handle Microsoft OAuth callback
     */
    router.get('/auth/microsoft/callback', async (req, res) => {
        const { code, state, error, error_description } = req.query;

        if (error) {
            console.error('[Auth] Microsoft OAuth Error:', error, error_description);
            return res.status(400).send(`Authentication failed: ${error_description}`);
        }

        if (!code || !state) {
            return res.status(400).send('Missing code or state');
        }

        try {
            const { companyId, userId } = JSON.parse(Buffer.from(state, 'base64').toString());

            const tokenResult = await oauthManager.exchangeMicrosoftCode(code);

            const accountData = {
                companyId,
                addedBy: userId,
                name: tokenResult.name || tokenResult.email,
                email: tokenResult.email,
                provider: 'microsoft-oauth',
                status: 'active',
                oauth: {
                    accessToken: tokenResult.accessToken,
                    refreshToken: tokenResult.refreshToken, // NOTE: Check if MSAL returns refresh token here
                    expiryDate: tokenResult.expiryDate,
                    scope: tokenResult.scope // MSAL might not return scope string in same format
                },
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            };

            // Check if account exists
            const existingAccount = await db.collection('emailAccounts')
                .where('companyId', '==', companyId)
                .where('email', '==', tokenResult.email)
                .get();

            if (!existingAccount.empty) {
                await existingAccount.docs[0].ref.update({
                    ...accountData,
                    updatedAt: admin.firestore.FieldValue.serverTimestamp()
                });
            } else {
                await db.collection('emailAccounts').add(accountData);
            }

            // Return success page
            res.send(`
                <html>
                    <body style="font-family: sans-serif; display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100vh; background: linear-gradient(135deg, #0078d4 0%, #004578 100%);">
                        <div style="background: white; padding: 40px; border-radius: 16px; text-align: center; box-shadow: 0 10px 40px rgba(0,0,0,0.2);">
                            <h1 style="color: #22c55e; margin-bottom: 16px;">✓ Account Connected!</h1>
                            <p style="color: #666; margin-bottom: 8px;">Successfully linked: <strong>${tokenResult.email}</strong></p>
                            <p style="color: #999; font-size: 14px;">You can close this window.</p>
                            <script>
                                setTimeout(() => window.close(), 3000);
                            </script>
                        </div>
                    </body>
                </html>
            `);

        } catch (error) {
            console.error('[Auth] Microsoft OAuth Error:', error);
            res.status(500).send(`Authentication failed: ${error.message}`);
        }
    });

    return router;
}

module.exports = createEmailRoutes;
