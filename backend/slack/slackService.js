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
}

module.exports = { SlackService };
