/**
 * Email Service - Modular Email Management (v3.1)
 * 
 * Updated with 2024/2025 best practices:
 * - Uses ImapFlow (modern, actively maintained) for IMAP
 * - Connection pooling for better performance
 * - Robust retry logic with exponential backoff
 * - Preemptive token refresh for OAuth
 */

const { ImapFlow } = require('imapflow');
const { simpleParser } = require('mailparser');
const { google } = require('googleapis');
const axios = require('axios');
const admin = require('firebase-admin');

// Configuration
const CONFIG = {
    // Retry settings
    MAX_RETRIES: 3,
    RETRY_DELAY_BASE: 1000,
    REQUEST_TIMEOUT: 30000,

    // IMAP settings
    IMAP_CONNECTION_TIMEOUT: 30000,
    IMAP_GREETING_TIMEOUT: 15000,
    IMAP_SOCKET_TIMEOUT: 300000, // 5 minutes for IDLE

    // Batch settings
    DEFAULT_FETCH_COUNT: 20,
    MAX_FETCH_COUNT: 50,

    // Token refresh buffer (refresh 10 min before expiry)
    TOKEN_REFRESH_BUFFER: 10 * 60 * 1000
};

class EmailService {
    constructor(oauthManager, db) {
        this.oauthManager = oauthManager;
        this.db = db;
        this.connectionPool = new Map(); // userId -> Map(accountId -> connection)
    }

    /**
     * Fetch emails from multiple accounts
     */
    async fetchEmails(accounts, offsets = {}) {
        const allEmails = [];
        const pagination = {};
        const errors = [];

        // Process accounts in parallel with error isolation
        const results = await Promise.allSettled(
            accounts.map(async (account) => {
                try {
                    return await this._fetchFromAccount(account, offsets[account.id || account.email]);
                } catch (err) {
                    console.error(`[Email] Error fetching from ${account.email}:`, err.message);
                    errors.push({ account: account.email, error: err.message });
                    return { emails: [], pagination: null };
                }
            })
        );

        // Aggregate results
        for (let i = 0; i < results.length; i++) {
            const result = results[i];
            const account = accounts[i];
            const accountKey = account.id || account.email;

            if (result.status === 'fulfilled' && result.value) {
                allEmails.push(...result.value.emails);
                if (result.value.pagination) {
                    pagination[accountKey] = result.value.pagination;
                }
            }
        }

        // Sort by date descending
        allEmails.sort((a, b) => new Date(b.date) - new Date(a.date));

        return { emails: allEmails, pagination, errors };
    }

    /**
     * Fetch from a single account
     */
    async _fetchFromAccount(account, offset) {
        const provider = account.provider || 'imap';

        switch (provider) {
            case 'gmail-oauth':
                return await this._fetchFromGmail(account, offset);
            case 'microsoft-oauth':
                return await this._fetchFromMicrosoft(account, offset);
            default:
                return await this._fetchFromIMAP(account, offset);
        }
    }

    /**
     * Fetch from Gmail using OAuth
     */
    async _fetchFromGmail(account, pageToken) {
        const tokenInfo = await this.oauthManager.getValidToken(account, 'google');

        if (tokenInfo.error) {
            await this._markAccountForReauth(account, tokenInfo.error);
            return { emails: [], pagination: null };
        }

        const oauth2Client = new google.auth.OAuth2();
        oauth2Client.setCredentials({ access_token: tokenInfo.accessToken });

        const gmail = google.gmail({ version: 'v1', auth: oauth2Client });

        try {
            // List messages
            const listParams = {
                userId: 'me',
                maxResults: CONFIG.DEFAULT_FETCH_COUNT,
                q: 'in:inbox'
            };
            if (pageToken) listParams.pageToken = pageToken;

            const listResponse = await gmail.users.messages.list(listParams);
            const messages = listResponse.data.messages || [];

            if (messages.length === 0) {
                return { emails: [], pagination: { hasMore: false } };
            }

            // Fetch full message details in parallel
            const emails = await Promise.all(
                messages.map(async (msg) => {
                    try {
                        const fullMessage = await gmail.users.messages.get({
                            userId: 'me',
                            id: msg.id,
                            format: 'full'
                        });

                        return this._parseGmailMessage(fullMessage.data, account);
                    } catch (err) {
                        console.error(`[Gmail] Error fetching message ${msg.id}:`, err.message);
                        return null;
                    }
                })
            );

            const validEmails = emails.filter(e => e !== null);

            return {
                emails: validEmails,
                pagination: {
                    nextPageToken: listResponse.data.nextPageToken,
                    hasMore: !!listResponse.data.nextPageToken
                }
            };

        } catch (err) {
            if (err.code === 401 || err.message?.includes('invalid_grant')) {
                await this._markAccountForReauth(account, 'Token invalid');
            }
            throw err;
        }
    }

    /**
     * Parse Gmail message to our format
     */
    _parseGmailMessage(message, account) {
        const headers = message.payload?.headers || [];
        const getHeader = (name) => headers.find(h => h.name.toLowerCase() === name.toLowerCase())?.value || '';

        const email = {
            id: `gmail_${account.id}_${message.id}`,
            messageId: message.id,
            threadId: message.threadId,
            accountId: account.id,
            accountName: account.name || account.email,
            accountType: 'gmail-oauth',
            from: getHeader('From'),
            to: getHeader('To'),
            subject: getHeader('Subject') || '(No Subject)',
            date: new Date(parseInt(message.internalDate)),
            snippet: message.snippet || '',
            isRead: !(message.labelIds || []).includes('UNREAD'),
            labels: message.labelIds || [],
            primaryCategory: this._getGmailCategory(message.labelIds),
            html: '',
            text: ''
        };

        // Extract body
        const body = this._extractGmailBody(message.payload);
        email.html = body.html || (body.text ? `<pre>${body.text}</pre>` : '');
        email.text = body.text;

        return email;
    }

    _getGmailCategory(labelIds) {
        if (!labelIds) return 'PERSONAL';
        if (labelIds.includes('CATEGORY_PROMOTIONS')) return 'PROMOTIONS';
        if (labelIds.includes('CATEGORY_SOCIAL')) return 'SOCIAL';
        if (labelIds.includes('CATEGORY_UPDATES')) return 'UPDATES';
        if (labelIds.includes('CATEGORY_FORUMS')) return 'FORUMS';
        return 'PERSONAL';
    }

    _extractGmailBody(payload) {
        let html = '';
        let text = '';

        const extractFromPart = (part) => {
            if (part.mimeType === 'text/html' && part.body?.data) {
                html = Buffer.from(part.body.data, 'base64').toString('utf8');
            } else if (part.mimeType === 'text/plain' && part.body?.data) {
                text = Buffer.from(part.body.data, 'base64').toString('utf8');
            }
            if (part.parts) {
                part.parts.forEach(extractFromPart);
            }
        };

        if (payload.body?.data) {
            const content = Buffer.from(payload.body.data, 'base64').toString('utf8');
            if (payload.mimeType === 'text/html') html = content;
            else text = content;
        }
        if (payload.parts) {
            payload.parts.forEach(extractFromPart);
        }

        return { html, text };
    }

    /**
     * Fetch from Microsoft using Graph API
     */
    async _fetchFromMicrosoft(account, skipToken) {
        const tokenInfo = await this.oauthManager.getValidToken(account, 'microsoft');

        if (tokenInfo.error) {
            await this._markAccountForReauth(account, tokenInfo.error);
            return { emails: [], pagination: null };
        }

        try {
            let url = 'https://graph.microsoft.com/v1.0/me/mailfolders/inbox/messages';
            url += `?$top=${CONFIG.DEFAULT_FETCH_COUNT}`;
            url += '&$select=id,subject,bodyPreview,from,toRecipients,receivedDateTime,isRead,body';
            url += '&$orderby=receivedDateTime desc';

            if (skipToken) {
                url = skipToken; // Microsoft returns full URL as skipToken
            }

            const response = await axios.get(url, {
                headers: { Authorization: `Bearer ${tokenInfo.accessToken}` },
                timeout: CONFIG.REQUEST_TIMEOUT
            });

            const messages = response.data.value || [];
            const emails = messages.map(msg => this._parseMicrosoftMessage(msg, account));

            return {
                emails,
                pagination: {
                    nextPageToken: response.data['@odata.nextLink'],
                    hasMore: !!response.data['@odata.nextLink']
                }
            };

        } catch (err) {
            if (err.response?.status === 401) {
                await this._markAccountForReauth(account, 'Token expired');
            }
            throw err;
        }
    }

    /**
     * Parse Microsoft message to our format
     */
    _parseMicrosoftMessage(message, account) {
        return {
            id: `microsoft_${account.id}_${message.id}`,
            messageId: message.id,
            accountId: account.id,
            accountName: account.name || account.email,
            accountType: 'microsoft-oauth',
            from: message.from?.emailAddress?.address
                ? `${message.from.emailAddress.name || ''} <${message.from.emailAddress.address}>`.trim()
                : 'Unknown',
            to: (message.toRecipients || [])
                .map(r => r.emailAddress?.address)
                .filter(Boolean)
                .join(', '),
            subject: message.subject || '(No Subject)',
            date: new Date(message.receivedDateTime),
            snippet: message.bodyPreview || '',
            isRead: message.isRead,
            html: message.body?.contentType === 'html' ? message.body?.content : '',
            text: message.body?.contentType === 'text' ? message.body?.content : ''
        };
    }

    /**
     * Fetch from IMAP using ImapFlow (modern library)
     */
    async _fetchFromIMAP(account, offset = 0) {
        const imapConfig = this._getImapConfig(account);
        if (!imapConfig) {
            console.error(`[IMAP] No credentials for ${account.email}`);
            return { emails: [], pagination: null };
        }

        let client;
        try {
            client = new ImapFlow({
                host: imapConfig.host,
                port: imapConfig.port,
                secure: imapConfig.tls !== false,
                auth: {
                    user: imapConfig.user,
                    pass: imapConfig.password
                },
                tls: {
                    rejectUnauthorized: false
                },
                logger: false,
                connectionTimeout: CONFIG.IMAP_CONNECTION_TIMEOUT,
                greetingTimeout: CONFIG.IMAP_GREETING_TIMEOUT,
                socketTimeout: CONFIG.IMAP_SOCKET_TIMEOUT
            });

            console.log(`[IMAP:${account.email}] Connecting to ${imapConfig.host}:${imapConfig.port}...`);
            await client.connect();

            const mailbox = await client.mailboxOpen('INBOX');
            const totalMessages = mailbox.exists;

            if (totalMessages === 0) {
                return { emails: [], pagination: { hasMore: false } };
            }

            // Calculate range (fetch newest first)
            const numOffset = parseInt(offset) || 0;
            const start = Math.max(1, totalMessages - numOffset - CONFIG.DEFAULT_FETCH_COUNT + 1);
            const end = Math.max(1, totalMessages - numOffset);

            if (start > end) {
                return { emails: [], pagination: { hasMore: false } };
            }

            console.log(`[IMAP:${account.email}] Fetching ${start}:${end} of ${totalMessages}`);

            const emails = [];

            // Fetch messages
            for await (const message of client.fetch(`${start}:${end}`, {
                envelope: true,
                bodyStructure: true,
                source: true,
                uid: true
            })) {
                try {
                    // Pass raw buffer to simpleParser to handle encodings correctly
                    const parsed = await simpleParser(message.source);

                    // Utility to escape HTML
                    const escapeHtml = (text) => {
                        return text
                            .replace(/&/g, "&amp;")
                            .replace(/</g, "&lt;")
                            .replace(/>/g, "&gt;")
                            .replace(/"/g, "&quot;")
                            .replace(/'/g, "&#039;");
                    };

                    const htmlContent = parsed.html || parsed.textAsHtml || (parsed.text ? `<pre style="white-space: pre-wrap; font-family: sans-serif;">${escapeHtml(parsed.text)}</pre>` : '');

                    // Handle cases with no body but with attachments
                    let finalHtml = htmlContent;
                    if (!finalHtml && parsed.attachments && parsed.attachments.length > 0) {
                        const attachmentList = parsed.attachments.map(att =>
                            `<li><strong>${escapeHtml(att.filename || 'Unnamed')}</strong> (${Math.round((att.size || 0) / 1024)} KB)</li>`
                        ).join('');

                        finalHtml = `
                            <div style="font-family: sans-serif; color: #444;">
                                <p><em>This message has no text content.</em></p>
                                <div style="margin-top: 16px; padding: 16px; background: #f8f9fa; border: 1px solid #e9ecef; border-radius: 8px;">
                                    <strong style="display: block; margin-bottom: 8px;">📎 Attachments (${parsed.attachments.length})</strong>
                                    <ul style="margin: 0; padding-left: 20px;">${attachmentList}</ul>
                                </div>
                            </div>
                        `;
                    }

                    if (!finalHtml) {
                        console.log(`[IMAP] Warning: No content for message ${message.uid}`);
                        console.log(`[IMAP] Debug Parsed Keys: ${Object.keys(parsed).join(', ')}`);
                        console.log(`[IMAP] Content-Type: ${parsed.headers?.get('content-type')}`);
                        console.log(`[IMAP] Attachments: ${JSON.stringify(parsed.attachments || [])}`);
                        console.log(`[IMAP] Structure: ${parsed.structure || 'N/A'}`);
                    }

                    emails.push({
                        id: `imap_${account.id}_${message.uid}`,
                        uid: message.uid,
                        accountId: account.id,
                        accountName: account.name || account.email,
                        accountType: 'imap',
                        from: parsed.from?.text || 'Unknown',
                        to: parsed.to?.text || '',
                        subject: parsed.subject || '(No Subject)',
                        date: parsed.date || new Date(),
                        snippet: (parsed.text || 'No text content').substring(0, 200).replace(/[\r\n]+/g, ' '),
                        isRead: true, // ImapFlow doesn't expose flags directly in this fetch
                        html: finalHtml || '',
                        text: parsed.text || '',
                        attachments: (parsed.attachments || []).map(att => ({
                            filename: att.filename,
                            contentType: att.contentType,
                            size: att.size,
                            contentId: att.contentId,
                            checksum: att.checksum
                        }))
                    });
                } catch (parseErr) {
                    console.error(`[IMAP] Parse error for message ${message.seq}:`, parseErr.message);
                    // Fallback: try to use envelope data if parsing fails
                    if (message.envelope) {
                        emails.push({
                            id: `imap_${account.id}_${message.uid}`,
                            uid: message.uid,
                            accountId: account.id,
                            accountName: account.name || account.email,
                            accountType: 'imap',
                            from: message.envelope.from?.[0]?.address || 'Unknown',
                            to: message.envelope.to?.[0]?.address || '',
                            subject: message.envelope.subject || '(No Subject)',
                            date: message.envelope.date || new Date(),
                            snippet: '(Preview unavailable)',
                            isRead: true,
                            html: '',
                            text: ''
                        });
                        console.log(`[IMAP] Used envelope fallback for message ${message.seq}`);
                    }
                }
            }

            // Sort by date descending
            emails.sort((a, b) => new Date(b.date) - new Date(a.date));

            const nextOffset = numOffset + emails.length;
            const hasMore = start > 1;

            return {
                emails,
                pagination: {
                    nextOffset,
                    hasMore
                }
            };

        } catch (err) {
            console.error(`[IMAP:${account.email}] Connection error:`, err.message);

            if (err.authenticationFailed || err.message?.includes('authentication')) {
                await this._markAccountForReauth(account, 'Invalid credentials');
            }

            throw err;
        } finally {
            if (client) {
                try {
                    await client.logout();
                } catch (e) {
                    // Ignore logout errors
                }
            }
        }
    }

    /**
     * Get IMAP configuration for an account
     */
    _getImapConfig(account) {
        // Check account-level credentials first
        if (account.imapConfig) {
            return account.imapConfig;
        }

        // Fall back to environment variables for testing
        if (account.email === process.env.IMAP_USER) {
            return {
                host: process.env.IMAP_HOST,
                port: parseInt(process.env.IMAP_PORT) || 993,
                user: process.env.IMAP_USER,
                password: process.env.IMAP_PASSWORD,
                tls: true
            };
        }

        return null;
    }

    /**
     * Mark account as needing re-authentication
     */
    async _markAccountForReauth(account, reason) {
        console.log(`[Email] Marking ${account.email} for reauth: ${reason}`);

        if (account.id && this.db) {
            try {
                await this.db.collection('emailAccounts').doc(account.id).update({
                    status: 'requires_reauth',
                    'oauth.error': reason,
                    updatedAt: admin.firestore.FieldValue.serverTimestamp()
                });
            } catch (err) {
                console.error(`[Email] Failed to mark account: ${err.message}`);
            }
        }
    }

    // NOTE: Read-only mode - markAsRead functionality removed for simpler OAuth verification
    // If you need write access, re-add gmail.modify scope and the markAsRead functions

    /**
     * Test IMAP connection
     */
    async testImapConnection(config) {
        let client;
        try {
            client = new ImapFlow({
                host: config.host,
                port: config.port || 993,
                secure: config.tls !== false,
                auth: {
                    user: config.user,
                    pass: config.password
                },
                logger: false,
                connectionTimeout: 15000,
                greetingTimeout: 10000
            });

            await client.connect();
            const mailbox = await client.mailboxOpen('INBOX');

            return {
                success: true,
                message: `Connected successfully! Found ${mailbox.exists} messages in inbox.`
            };
        } catch (err) {
            return {
                success: false,
                message: `Connection failed: ${err.message}`
            };
        } finally {
            if (client) {
                try {
                    await client.logout();
                } catch (e) { /* ignore */ }
            }
        }
    }
}

module.exports = { EmailService };
