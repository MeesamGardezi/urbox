/**
 * Slack Service
 * Handles Slack API interactions and account management
 */

const { WebClient } = require('@slack/web-api');
const admin = require('firebase-admin');

class SlackService {
    constructor(oauthManager, db) {
        this.oauthManager = oauthManager;
        this.db = db;
    }

    /**
     * List all connected Slack accounts for a company
     * @param {string} companyId 
     * @returns {Promise<Array>} List of slack accounts
     */
    async listAccounts(companyId) {
        try {
            const snapshot = await this.db.collection('slackAccounts')
                .where('companyId', '==', companyId)
                .get();

            const accounts = [];
            snapshot.forEach(doc => {
                const data = doc.data();
                // Return safe data, excluding tokens
                const { oauth, ...safeData } = data;
                accounts.push({ id: doc.id, ...safeData });
            });

            return accounts;
        } catch (err) {
            console.error('[SlackService] List accounts error:', err);
            throw new Error('Failed to list slack accounts');
        }
    }

    /**
     * Delete/Disconnect a Slack account
     * @param {string} accountId 
     */
    async deleteAccount(accountId) {
        try {
            await this.db.collection('slackAccounts').doc(accountId).delete();
            return { success: true };
        } catch (err) {
            console.error('[SlackService] Delete account error:', err);
            throw new Error('Failed to disconnect slack account');
        }
    }

    /**
     * Exchange OAuth code for tokens and save account
     * @param {string} code 
     * @param {string} companyId 
     * @param {string} userId 
     */
    async storeNewAccount(code, companyId, userId) {
        const tokenResult = await this.oauthManager.exchangeSlackCode(code);

        // Fetch user info to populate name/email if not in initial token response
        let userInfo = { name: 'Slack User', email: null };
        try {
            userInfo = await this.oauthManager.getSlackUserInfo(tokenResult.accessToken, tokenResult.slackId);
        } catch (e) {
            console.warn('[SlackService] Failed to fetch user profile:', e.message);
        }

        const accountData = {
            companyId,
            addedBy: userId,
            name: tokenResult.teamName || userInfo.name,
            email: userInfo.email, // Might be null
            slackId: tokenResult.slackId,
            teamId: tokenResult.teamId, // Slack Workspace ID
            teamName: tokenResult.teamName,
            provider: 'slack',
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

        const existingAccount = await this.db.collection('slackAccounts')
            .where('companyId', '==', companyId)
            .where('slackId', '==', tokenResult.slackId)
            .where('teamId', '==', tokenResult.teamId)
            .get();

        if (!existingAccount.empty) {
            await existingAccount.docs[0].ref.update({
                ...accountData,
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            });
        } else {
            await this.db.collection('slackAccounts').add(accountData);
        }

        return {
            teamName: tokenResult.teamName,
            userName: userInfo.name
        };
    }
    async listConversations(accountId) {
        let account;
        // If accountId is a string, fetch the doc
        if (typeof accountId === 'string') {
            const doc = await this.db.collection('slackAccounts').doc(accountId).get();
            if (!doc.exists) throw new Error('Account not found');
            account = { id: doc.id, ...doc.data() };
        } else {
            account = accountId;
        }

        const tokenResult = await this.oauthManager.getValidToken(account, 'slack');
        if (tokenResult.error) {
            throw new Error(`Token error: ${tokenResult.error}`);
        }

        const client = new WebClient(tokenResult.accessToken);

        try {
            const result = await client.conversations.list({
                types: 'public_channel,private_channel',
                limit: 1000,
                exclude_archived: true
            });

            if (!result.ok) {
                throw new Error(result.error);
            }

            return result.channels.map(c => ({
                id: c.id,
                name: c.name,
                is_private: c.is_private,
                is_member: c.is_member
            }));
        } catch (error) {
            console.error('[SlackService] List conversations error:', error);
            throw error;
        }
    }
    async getMessages(companyId, limit = 20, before = null) {
        try {
            // 1. Get all accounts
            const accounts = await this.listAccounts(companyId);
            const allMessages = [];

            // 2. Process each account
            for (const accountWithoutToken of accounts) {
                try {
                    // Need to fetch full doc to get trackedChannels if listAccounts filters it?
                    // listAccounts returns "safeData". Let's verify if trackedChannels is safe. 
                    // It should be. But let's check the verify. 
                    // Actually listAccounts excludes 'oauth'. 
                    // We need to re-fetch or trust listAccounts.
                    // To be safe and get token, we need the doc content anyway for getValidToken.

                    const doc = await this.db.collection('slackAccounts').doc(accountWithoutToken.id).get();
                    if (!doc.exists) continue;
                    const account = { id: doc.id, ...doc.data() };

                    // 3. Get Token
                    const tokenResult = await this.oauthManager.getValidToken(account, 'slack');
                    if (tokenResult.error) {
                        console.warn(`[SlackService] Token error for account ${account.name}: ${tokenResult.error}`);
                        continue;
                    }

                    const client = new WebClient(tokenResult.accessToken);
                    const trackedChannels = account.trackedChannels || [];

                    // 4. Fetch from tracked channels
                    for (const channel of trackedChannels) {
                        try {
                            // Only fetch if channel ID is valid
                            if (!channel.id) continue;

                            const params = {
                                channel: channel.id,
                                limit: limit,
                            };
                            if (before) {
                                params.latest = before;
                            }

                            const history = await client.conversations.history(params);

                            if (history.ok && history.messages) {
                                // 5. Normalize
                                const messages = history.messages.map(msg => ({
                                    id: `slack_${msg.ts}`,
                                    originalId: msg.ts,
                                    platform: 'slack',
                                    body: msg.text || '',
                                    timestamp: new Date(parseFloat(msg.ts) * 1000),
                                    sender: msg.user || 'Unknown', // We might need to resolve user names... skipping for speed
                                    senderName: msg.username || msg.user || 'User', // Slack messages often just have user ID
                                    channelId: channel.id,
                                    channelName: channel.name,
                                    accountId: account.id,
                                    accountName: account.name,
                                    teamId: account.teamId,
                                    hasMedia: msg.files && msg.files.length > 0,
                                    mediaUrl: msg.files && msg.files.length > 0 ? msg.files[0].url_private : null
                                }));
                                allMessages.push(...messages);
                            }
                        } catch (chanErr) {
                            console.warn(`[SlackService] Failed to fetch channel ${channel.name}: ${chanErr.message}`);
                        }
                    }

                } catch (accErr) {
                    console.error(`[SlackService] Failed to process account ${accountWithoutToken.id}: ${accErr}`);
                }
            }

            // 6. Sort and Limit
            return allMessages
                .sort((a, b) => b.timestamp - a.timestamp)
                .slice(0, limit);

        } catch (err) {
            console.error('[SlackService] Get messages error:', err);
            throw new Error('Failed to fetch slack messages');
        }
    }
}

module.exports = { SlackService };
