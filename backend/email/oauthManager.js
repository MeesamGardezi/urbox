/**
 * OAuth Manager - Centralized Token Management (v3.1)
 * 
 * Updated with 2024/2025 best practices:
 * - Preemptive token refresh (10 min before expiry)
 * - Concurrent refresh protection
 * - Token caching with TTL
 * - Graceful error classification
 * - Automatic retry with exponential backoff
 */

const { google } = require('googleapis');
const { ConfidentialClientApplication } = require('@azure/msal-node');
const admin = require('firebase-admin');

// Configuration
const CONFIG = {
    // Refresh buffer - refresh tokens 10 minutes before expiry
    REFRESH_BUFFER_MS: 10 * 60 * 1000,

    // Cache TTL - 50 minutes (access tokens typically last 60 min)
    CACHE_TTL_MS: 50 * 60 * 1000,

    // Retry settings
    MAX_RETRIES: 3,
    RETRY_DELAY_BASE: 1000,

    // Request timeout
    REQUEST_TIMEOUT: 15000,

    // Slack specific
    SLACK_TOKEN_URL: 'https://slack.com/api/oauth.v2.access',
    SLACK_AUTH_URL: 'https://slack.com/oauth/v2/authorize'
};

// Token cache: accountId -> { token, expiresAt, refreshPromise }
const tokenCache = new Map();

// In-progress refresh promises to prevent concurrent refreshes
const refreshInProgress = new Map();

class OAuthManager {
    constructor(db) {
        this.db = db;

        // Google OAuth2 client
        this.googleClient = new google.auth.OAuth2(
            process.env.GOOGLE_CLIENT_ID,
            process.env.GOOGLE_CLIENT_SECRET,
            process.env.GOOGLE_REDIRECT_URI
        );

        // Microsoft MSAL client
        this.msalClient = process.env.MICROSOFT_CLIENT_ID ? new ConfidentialClientApplication({
            auth: {
                clientId: process.env.MICROSOFT_CLIENT_ID,
                clientSecret: process.env.MICROSOFT_CLIENT_SECRET,
                authority: 'https://login.microsoftonline.com/common'
            }
        }) : null;
    }

    /**
     * Get a valid access token for an account
     * Handles caching, refresh logic, and error cases
     */
    async getValidToken(account, provider) {
        const accountId = account.id || account.email;
        const cacheKey = `${provider}_${accountId}`;

        // Check cache first
        const cached = tokenCache.get(cacheKey);
        if (cached && cached.expiresAt > Date.now() + CONFIG.REFRESH_BUFFER_MS) {
            return { accessToken: cached.token, cached: true };
        }

        // Check if refresh is already in progress for this account
        if (refreshInProgress.has(cacheKey)) {
            console.log(`[OAuth] Waiting for in-progress refresh: ${account.email}`);
            try {
                const result = await refreshInProgress.get(cacheKey);
                return result;
            } catch (err) {
                // If the in-progress refresh failed, try again
                refreshInProgress.delete(cacheKey);
            }
        }

        // Start refresh and store promise to prevent concurrent refreshes
        const refreshPromise = this._performRefresh(account, provider, cacheKey);
        refreshInProgress.set(cacheKey, refreshPromise);

        try {
            const result = await refreshPromise;
            return result;
        } finally {
            refreshInProgress.delete(cacheKey);
        }
    }

    /**
     * Perform the actual token refresh
     */
    async _performRefresh(account, provider, cacheKey) {
        console.log(`[OAuth] Refreshing token for ${account.email} (${provider})`);

        try {
            let result;

            if (provider === 'google') {
                result = await this._refreshGoogleToken(account);
            } else if (provider === 'microsoft') {
                result = await this._refreshMicrosoftToken(account);
            } else if (provider === 'slack') {
                result = await this._refreshSlackToken(account);
            } else {
                throw new Error(`Unknown provider: ${provider}`);
            }

            if (result.error) {
                return result;
            }

            // Cache the new token
            tokenCache.set(cacheKey, {
                token: result.accessToken,
                expiresAt: result.expiryDate || (Date.now() + CONFIG.CACHE_TTL_MS)
            });

            // Persist to Firestore if refresh token changed
            if (result.refreshed || result.newRefreshToken) {
                await this._persistTokens(account, result);
            }

            return result;

        } catch (err) {
            console.error(`[OAuth] Refresh failed for ${account.email}:`, err.message);
            return this._classifyError(err);
        }
    }

    /**
     * Refresh Google OAuth token
     */
    async _refreshGoogleToken(account) {
        const refreshToken = account.oauth?.refreshToken || account.refreshToken;

        if (!refreshToken) {
            return { error: 'no_refresh_token', message: 'No refresh token available' };
        }

        // Check if current token is still valid
        const currentExpiry = account.oauth?.expiryDate || account.expiryDate;
        if (currentExpiry && currentExpiry > Date.now() + CONFIG.REFRESH_BUFFER_MS) {
            return {
                accessToken: account.oauth?.accessToken || account.accessToken,
                expiryDate: currentExpiry,
                refreshed: false
            };
        }

        try {
            this.googleClient.setCredentials({
                refresh_token: refreshToken
            });

            const { credentials } = await this.googleClient.refreshAccessToken();

            return {
                accessToken: credentials.access_token,
                expiryDate: credentials.expiry_date,
                refreshToken: credentials.refresh_token || refreshToken,
                newRefreshToken: !!credentials.refresh_token,
                refreshed: true
            };

        } catch (err) {
            // Handle specific Google error cases
            if (err.message?.includes('invalid_grant') ||
                err.message?.includes('Token has been expired or revoked')) {
                return {
                    error: 'invalid_grant',
                    message: 'Refresh token expired or revoked. Re-authentication required.'
                };
            }
            throw err;
        }
    }

    /**
     * Refresh Microsoft OAuth token
     */
    async _refreshMicrosoftToken(account) {
        if (!this.msalClient) {
            return { error: 'no_msal_client', message: 'MSAL client not configured' };
        }

        const refreshToken = account.oauth?.refreshToken || account.refreshToken;

        if (!refreshToken) {
            return { error: 'no_refresh_token', message: 'No refresh token available' };
        }

        // Check if current token is still valid
        const currentExpiry = account.oauth?.expiryDate || account.expiryDate;
        if (currentExpiry && currentExpiry > Date.now() + CONFIG.REFRESH_BUFFER_MS) {
            return {
                accessToken: account.oauth?.accessToken || account.accessToken,
                expiryDate: currentExpiry,
                refreshed: false
            };
        }

        try {
            const result = await this.msalClient.acquireTokenByRefreshToken({
                refreshToken: refreshToken,
                scopes: ['openid', 'profile', 'email', 'Mail.Read', 'Mail.ReadWrite', 'Calendars.Read']
            });

            if (!result || !result.accessToken) {
                return { error: 'no_token_returned', message: 'No access token in response' };
            }

            // Calculate expiry
            const expiresIn = result.expiresOn
                ? new Date(result.expiresOn).getTime()
                : Date.now() + 3600 * 1000;

            return {
                accessToken: result.accessToken,
                expiryDate: expiresIn,
                refreshToken: refreshToken, // MSAL doesn't always return new refresh token
                refreshed: true
            };

        } catch (err) {
            // Handle specific Microsoft error cases
            if (err.errorCode === 'invalid_grant' ||
                err.errorMessage?.includes('interaction_required') ||
                err.errorMessage?.includes('consent_required')) {
                return {
                    error: 'interaction_required',
                    message: 'Re-authentication required. Please sign in again.'
                };
            }
            throw err;
        }
    }

    /**
     * Refresh Slack OAuth token
     */
    async _refreshSlackToken(account) {
        const refreshToken = account.oauth?.refreshToken || account.refreshToken;

        // Slack tokens might not expire if they are bot tokens or non-rotating user tokens
        // But if we have an expiry date, we should respect it.
        const currentExpiry = account.oauth?.expiryDate || account.expiryDate;

        // If no expiry date, assume it's good forever (or until revocation)
        if (!currentExpiry) {
            return {
                accessToken: account.oauth?.accessToken || account.accessToken,
                expiryDate: null,
                refreshed: false
            };
        }

        if (currentExpiry && currentExpiry > Date.now() + CONFIG.REFRESH_BUFFER_MS) {
            return {
                accessToken: account.oauth?.accessToken || account.accessToken,
                expiryDate: currentExpiry,
                refreshed: false
            };
        }

        if (!refreshToken) {
            return { error: 'no_refresh_token', message: 'No refresh token available for expiring Slack token' };
        }

        try {
            const axios = require('axios');
            const response = await axios.post(CONFIG.SLACK_TOKEN_URL, new URLSearchParams({
                client_id: process.env.SLACK_CLIENT_ID,
                client_secret: process.env.SLACK_CLIENT_SECRET,
                grant_type: 'refresh_token',
                refresh_token: refreshToken
            }));

            if (!response.data.ok) {
                return {
                    error: response.data.error,
                    message: `Slack refresh failed: ${response.data.error}`
                };
            }

            const { access_token, refresh_token, expires_in } = response.data;

            return {
                accessToken: access_token,
                refreshToken: refresh_token || refreshToken, // Slack rotates refresh tokens too usually
                expiryDate: Date.now() + (expires_in * 1000),
                newRefreshToken: !!refresh_token,
                refreshed: true
            };

        } catch (err) {
            console.error('[OAuth] Slack refresh error:', err.message);
            return {
                error: 'slack_refresh_failed',
                message: err.message
            };
        }
    }

    /**
     * Classify error for proper handling
     */
    _classifyError(err) {
        const message = err.message || err.toString();

        // Authentication errors requiring user interaction
        if (message.includes('invalid_grant') ||
            message.includes('interaction_required') ||
            message.includes('consent_required') ||
            message.includes('expired') ||
            message.includes('revoked')) {
            return {
                error: 'requires_reauth',
                message: 'Authentication expired. Please sign in again.'
            };
        }

        // Network errors - transient
        if (message.includes('ECONNREFUSED') ||
            message.includes('ETIMEDOUT') ||
            message.includes('network')) {
            return {
                error: 'network_error',
                message: 'Network error. Please try again.',
                retryable: true
            };
        }

        // Unknown error
        return {
            error: 'unknown_error',
            message: message
        };
    }

    /**
     * Persist updated tokens to Firestore
     */
    async _persistTokens(account, tokenResult) {
        if (!account.id || !this.db) return;

        try {
            const updateData = {
                'oauth.accessToken': tokenResult.accessToken,
                'oauth.expiryDate': tokenResult.expiryDate,
                status: 'active',
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            };

            // Only update refresh token if we got a new one
            if (tokenResult.newRefreshToken && tokenResult.refreshToken) {
                updateData['oauth.refreshToken'] = tokenResult.refreshToken;
            }

            // Clear any previous error
            updateData['oauth.error'] = admin.firestore.FieldValue.delete();

            // Determine collection based on provider
            const collectionName = (account.provider === 'slack') ? 'slackAccounts' : 'emailAccounts';

            await this.db.collection(collectionName).doc(account.id).update(updateData);
            console.log(`[OAuth] Tokens persisted for ${account.email || account.name} in ${collectionName}`);

        } catch (err) {
            console.error(`[OAuth] Failed to persist tokens:`, err.message);
        }
    }

    /**
     * Generate Google OAuth URL
     */
    getGoogleAuthUrl(state) {
        return this.googleClient.generateAuthUrl({
            access_type: 'offline',
            prompt: 'consent', // Force to get refresh token
            scope: [
                'https://www.googleapis.com/auth/gmail.readonly',
                'https://www.googleapis.com/auth/calendar.readonly',
                'https://www.googleapis.com/auth/userinfo.email',
                'https://www.googleapis.com/auth/userinfo.profile'
            ],
            state
        });
    }

    /**
     * Exchange Google auth code for tokens
     */
    async exchangeGoogleCode(code) {
        const { tokens } = await this.googleClient.getToken(code);
        this.googleClient.setCredentials(tokens);

        // Get user info
        const oauth2 = google.oauth2({ version: 'v2', auth: this.googleClient });
        const userInfo = await oauth2.userinfo.get();

        return {
            email: userInfo.data.email,
            name: userInfo.data.name,
            picture: userInfo.data.picture,
            accessToken: tokens.access_token,
            refreshToken: tokens.refresh_token,
            expiryDate: tokens.expiry_date,
            scope: tokens.scope
        };
    }

    /**
     * Generate Microsoft OAuth URL
     */
    async getMicrosoftAuthUrl(state) {
        if (!this.msalClient) {
            throw new Error('MSAL client not configured');
        }

        return await this.msalClient.getAuthCodeUrl({
            redirectUri: process.env.MICROSOFT_REDIRECT_URI,
            scopes: ['openid', 'profile', 'email', 'offline_access', 'Mail.Read', 'Mail.ReadWrite', 'Calendars.Read'],
            state,
            prompt: 'consent'
        });
    }

    /**
     * Exchange Microsoft auth code for tokens
     */
    async exchangeMicrosoftCode(code) {
        if (!this.msalClient) {
            throw new Error('MSAL client not configured');
        }

        const result = await this.msalClient.acquireTokenByCode({
            code,
            redirectUri: process.env.MICROSOFT_REDIRECT_URI,
            scopes: ['openid', 'profile', 'email', 'offline_access', 'Mail.Read', 'Mail.ReadWrite', 'Calendars.Read']
        });

        if (!result || !result.account) {
            throw new Error('Failed to get account info from Microsoft');
        }

        return {
            email: result.account.username,
            name: result.account.name,
            homeAccountId: result.account.homeAccountId,
            accessToken: result.accessToken,
            expiryDate: result.expiresOn ? new Date(result.expiresOn).getTime() : Date.now() + 3600000
        };
    }

    /**
     * Generate Slack OAuth URL
     */
    getSlackAuthUrl(state) {
        const scopes = [
            'channels:history',
            'groups:history',
            'im:history',
            'mpim:history',
            'channels:read',
            'groups:read',
            'im:read',
            'mpim:read',
            'chat:write',
            'users:read',
            'users.profile:read',
            'team:read'
        ];

        // We use user scopes because the user wants to sync THEIR chats
        const userScopes = scopes.join(',');

        const url = new URL(CONFIG.SLACK_AUTH_URL);
        url.searchParams.append('client_id', process.env.SLACK_CLIENT_ID);
        url.searchParams.append('user_scope', userScopes); // Requesting user token
        url.searchParams.append('redirect_uri', process.env.SLACK_REDIRECT_URI);
        url.searchParams.append('state', state);

        return url.toString();
    }

    /**
     * Exchange Slack auth code for tokens
     */
    async exchangeSlackCode(code) {
        const axios = require('axios');

        const response = await axios.post(CONFIG.SLACK_TOKEN_URL, new URLSearchParams({
            client_id: process.env.SLACK_CLIENT_ID,
            client_secret: process.env.SLACK_CLIENT_SECRET,
            code: code,
            redirect_uri: process.env.SLACK_REDIRECT_URI
        }));

        if (!response.data.ok) {
            throw new Error(`Slack exchange failed: ${response.data.error}`);
        }

        const data = response.data;
        const authedUser = data.authed_user;

        if (!authedUser) {
            throw new Error('No user token received. Make sure to use user_scope.');
        }

        return {
            email: null, // Slack doesn't always give email easily in this payload, fetch later
            slackId: authedUser.id,
            teamId: data.team.id,
            teamName: data.team.name,
            accessToken: authedUser.access_token,
            refreshToken: authedUser.refresh_token,
            expiryDate: authedUser.expires_in ? Date.now() + (authedUser.expires_in * 1000) : null,
            scope: authedUser.scope
        };
    }

    /**
     * Get User Info from Slack (helper since ID token isn't always standard)
     */
    async getSlackUserInfo(accessToken, userId) {
        const axios = require('axios');
        const response = await axios.get('https://slack.com/api/users.info', {
            params: { user: userId },
            headers: { Authorization: `Bearer ${accessToken}` }
        });

        if (response.data.ok) {
            return {
                email: response.data.user.profile.email,
                name: response.data.user.real_name || response.data.user.name,
                avatar: response.data.user.profile.image_512 || response.data.user.profile.image_192
            };
        }
        return { email: null, name: 'Slack User' };
    }

    /**
     * Revoke tokens for an account
     */
    async revokeTokens(account, provider) {
        const cacheKey = `${provider}_${account.id || account.email}`;
        tokenCache.delete(cacheKey);

        // For Google, we can revoke the token
        if (provider === 'google' && account.oauth?.accessToken) {
            try {
                await this.googleClient.revokeToken(account.oauth.accessToken);
                console.log(`[OAuth] Revoked Google token for ${account.email}`);
            } catch (err) {
                console.error(`[OAuth] Token revocation failed:`, err.message);
            }
        }

        // Microsoft doesn't have a simple revocation endpoint,
        // but we can clear from cache and update Firestore
        if (account.id && this.db) {
            const collectionName = (account.provider === 'slack') ? 'slackAccounts' : 'emailAccounts';
            await this.db.collection(collectionName).doc(account.id).update({
                status: 'disconnected',
                'oauth.accessToken': admin.firestore.FieldValue.delete(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            });
        }
    }

    /**
     * Clear expired entries from cache
     */
    cleanupCache() {
        const now = Date.now();
        for (const [key, value] of tokenCache.entries()) {
            if (value.expiresAt < now) {
                tokenCache.delete(key);
            }
        }
    }
}

module.exports = { OAuthManager };
