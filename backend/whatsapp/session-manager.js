/**
 * WhatsApp Session Manager (Enhanced)
 * 
 * Manages WhatsApp Web connections using whatsapp-web.js
 * - Maintains active sessions in memory
 * - Handles QR code generation
 * - Processes incoming messages
 * - Robust reconnection with exponential backoff
 * - Heartbeat monitoring for session health
 */

const { Client, LocalAuth } = require('whatsapp-web.js');
const admin = require('firebase-admin');
const qrcode = require('qrcode-terminal');
const fs = require('fs');
const path = require('path');
const { StorageService } = require('../storage/storage-service');

const storageService = new StorageService();

// Configuration
const CONFIG = {
    HEARTBEAT_INTERVAL: 60 * 1000, // 1 minute
    RECONNECT_BASE_DELAY: 5000,
    RECONNECT_MAX_DELAY: 60000,
    MAX_RECONNECT_ATTEMPTS: 5,
    QR_TIMEOUT: 2 * 60 * 1000, // 2 minutes
    AUTH_TIMEOUT: 90000,
    QR_MAX_RETRIES: 5,
};

class WhatsAppSessionManager {
    constructor(db) {
        this.db = db;
        this.activeSessions = new Map(); // userId -> { client, companyId, status, phone, name }
        this.qrCodes = new Map(); // userId -> qr code string
        this.heartbeatIntervals = new Map(); // userId -> interval
        this.reconnectAttempts = new Map(); // userId -> number
        this.reconnectTimeouts = new Map(); // userId -> timeout
    }

    /**
     * Start a new WhatsApp session for a user
     */
    async startSession(userId, companyId) {
        try {
            // Check if session already exists
            if (this.activeSessions.has(userId)) {
                const session = this.activeSessions.get(userId);
                if (session.status === 'connected' || session.status === 'qr_pending') {
                    console.log(`[WhatsApp] Session already active for user ${userId}`);
                    return { success: true, message: 'Session already active' };
                }
            }

            console.log(`[WhatsApp] Starting session for user ${userId}`);

            // Function to create client configuration
            const createClient = () => {
                return new Client({
                    authStrategy: new LocalAuth({
                        clientId: userId,
                        dataPath: path.join(process.cwd(), '.wwebjs_auth')
                    }),
                    authTimeoutMs: CONFIG.AUTH_TIMEOUT,
                    qrMaxRetries: CONFIG.QR_MAX_RETRIES,
                    restartOnAuthFail: true,
                    takeoverOnConflict: true,
                    takeoverTimeoutMs: 10000,
                    puppeteer: {
                        headless: true,
                        args: [
                            '--no-sandbox',
                            '--disable-setuid-sandbox',
                            '--disable-dev-shm-usage',
                            '--disable-accelerated-2d-canvas',
                            '--no-first-run',
                            '--disable-gpu'
                        ]
                    }
                });
            };

            let client = createClient();

            // Store session info
            this.activeSessions.set(userId, {
                client,
                companyId,
                status: 'initializing',
                phone: null,
                name: null
            });

            // Set up event handlers
            this._setupClientHandlers(client, userId, companyId);

            // Initialize client (this triggers QR generation or auth)
            try {
                await client.initialize();
            } catch (initError) {
                if (initError.message && initError.message.includes('browser is already running')) {
                    console.warn(`[WhatsApp] Session lock detected for ${userId}. Attempting to clear lock and retry...`);

                    // Remove from active sessions before retrying to avoid pollution
                    this.activeSessions.delete(userId);

                    // Force cleanup of the lock file
                    this._forceCleanupSessionDirectory(userId);

                    // Re-create client and retry
                    client = createClient();
                    this.activeSessions.set(userId, {
                        client,
                        companyId,
                        status: 'initializing',
                        phone: null,
                        name: null
                    });
                    this._setupClientHandlers(client, userId, companyId);

                    await client.initialize();
                    console.log(`[WhatsApp] Retry successful for ${userId}`);
                } else {
                    throw initError;
                }
            }

            // Update Firestore
            await this._updateFirestoreStatus(userId, {
                status: 'initializing',
                companyId,
                lastSync: admin.firestore.FieldValue.serverTimestamp()
            });

            return { success: true };

        } catch (error) {
            console.error(`[WhatsApp] Error starting session for ${userId}:`, error);

            // Clean up on error
            await this._cleanupSession(userId);

            return {
                success: false,
                error: error.message
            };
        }
    }

    /**
     * Force cleanup of session directory lock
     */
    _forceCleanupSessionDirectory(userId) {
        try {
            const lockPath = path.join(process.cwd(), '.wwebjs_auth', `session-${userId}`, 'SingletonLock');
            if (fs.existsSync(lockPath)) {
                console.log(`[WhatsApp] Removing SingletonLock for ${userId}`);
                fs.unlinkSync(lockPath);
            }
        } catch (e) {
            console.error(`[WhatsApp] Error forcing cleanup for ${userId}:`, e.message);
        }
    }

    /**
     * Set up event handlers for WhatsApp client
     */
    _setupClientHandlers(client, userId, companyId) {
        const session = this.activeSessions.get(userId);

        // QR Code generation
        client.on('qr', async (qr) => {
            console.log(`[WhatsApp] QR code generated for user ${userId}`);

            // Store QR code in memory
            this.qrCodes.set(userId, qr);

            // Update session status
            if (session) session.status = 'qr_pending';

            // Update Firestore
            await this._updateFirestoreStatus(userId, {
                status: 'qr_pending',
                qrCode: qr,
                lastSync: admin.firestore.FieldValue.serverTimestamp()
            });

            // Print QR to console for debugging
            if (process.env.NODE_ENV === 'development') {
                qrcode.generate(qr, { small: true });
            }

            // Set QR timeout
            setTimeout(async () => {
                if (session && session.status === 'qr_pending') {
                    console.log(`[WhatsApp] QR timeout for ${userId}`);
                    await this.stopSession(userId, false);
                    await this._updateFirestoreStatus(userId, {
                        status: 'disconnected',
                        disconnectReason: 'QR code expired. Please try again.'
                    });
                }
            }, CONFIG.QR_TIMEOUT);
        });

        // Authentication
        client.on('authenticated', async () => {
            console.log(`[WhatsApp] Authenticated for user: ${userId}`);

            if (session) session.status = 'authenticating';

            await this._updateFirestoreStatus(userId, {
                status: 'authenticating',
                qrCode: admin.firestore.FieldValue.delete(),
                lastSync: admin.firestore.FieldValue.serverTimestamp()
            });

            // Clear QR code from memory
            this.qrCodes.delete(userId);

            // Reset reconnect attempts on successful auth
            this.reconnectAttempts.set(userId, 0);
        });

        // Ready (connected)
        client.on('ready', async () => {
            console.log(`[WhatsApp] Client ready for ${userId}`);

            // Get account info
            const info = client.info;

            if (session) {
                session.status = 'connected';
                session.phone = info.wid.user;
                session.name = info.pushname || info.wid.user;
            }

            await this._updateFirestoreStatus(userId, {
                status: 'connected',
                phone: info.wid.user,
                name: info.pushname || info.wid.user,
                connectedAt: admin.firestore.FieldValue.serverTimestamp(),
                lastSync: admin.firestore.FieldValue.serverTimestamp()
            });

            // Start heartbeat monitoring
            this._startHeartbeat(userId);

            // Reset reconnect attempts
            this.reconnectAttempts.set(userId, 0);
        });

        // Incoming messages
        client.on('message', async (msg) => {
            await this._handleIncomingMessage(userId, companyId, msg);
        });

        // Sent messages (by the user from phone or web)
        client.on('message_create', async (msg) => {
            if (msg.fromMe) {
                await this._handleIncomingMessage(userId, companyId, msg);
            }
        });

        // Disconnected
        client.on('disconnected', async (reason) => {
            console.log(`[WhatsApp] Disconnected for user ${userId}:`, reason);

            await this._updateFirestoreStatus(userId, {
                status: 'disconnected',
                disconnectReason: reason,
                lastSync: admin.firestore.FieldValue.serverTimestamp()
            });

            // Stop heartbeat
            this._stopHeartbeat(userId);

            // Decide whether to attempt reconnection
            const noReconnectReasons = ['LOGOUT', 'TOS_BLOCK', 'SMB_TOS_BLOCK', 'NAVIGATION'];

            if (!noReconnectReasons.includes(reason)) {
                console.log(`[WhatsApp] Will attempt reconnection for ${userId}`);
                this._scheduleReconnect(userId, companyId);
            } else {
                console.log(`[WhatsApp] No reconnection for ${userId} due to reason: ${reason}`);
                await this._cleanupSession(userId);

                // Clean up auth if logged out
                if (reason === 'LOGOUT') {
                    this._deleteAuthData(userId);
                }
            }
        });

        // Auth failure
        client.on('auth_failure', async (msg) => {
            console.error(`[WhatsApp] Auth failure for user ${userId}:`, msg);

            await this._updateFirestoreStatus(userId, {
                status: 'error',
                error: 'Authentication failed',
                lastSync: admin.firestore.FieldValue.serverTimestamp()
            });

            await this._cleanupSession(userId);
            this._deleteAuthData(userId);
        });

        // State change
        client.on('change_state', async (state) => {
            console.log(`[WhatsApp] State changed for ${userId}: ${state}`);

            if (state === 'UNPAIRED' || state === 'UNPAIRED_IDLE') {
                console.log(`[WhatsApp] Session unpaired for ${userId}`);
                await this._updateFirestoreStatus(userId, {
                    status: 'disconnected',
                    disconnectReason: 'Session was logged out from WhatsApp'
                });
                await this._cleanupSession(userId);
                this._deleteAuthData(userId);
            }
        });
    }

    /**
     * Handle incoming/outgoing WhatsApp message
     */
    async _handleIncomingMessage(userId, companyId, msg) {
        try {
            // Get chat info
            const chat = await msg.getChat();

            // Only process group messages
            if (!chat.isGroup) return;

            const groupId = chat.id._serialized;

            // Check if this group is being monitored
            const monitoredGroups = await this.db
                .collection('whatsappGroups')
                .where('userId', '==', userId)
                .where('groupId', '==', groupId)
                .where('isMonitoring', '==', true)
                .limit(1)
                .get();

            if (monitoredGroups.empty) {
                // Group not monitored, skip
                return;
            }

            console.log(`[WhatsApp] New message in monitored group ${chat.name} for user ${userId} (fromMe: ${msg.fromMe})`);

            // Get sender info
            let senderName = 'Unknown';
            try {
                const contact = await msg.getContact();
                senderName = contact.pushname || contact.number || 'Unknown';
            } catch (error) {
                console.warn(`[WhatsApp] Could not get contact info: ${error.message}`);
                if (msg.fromMe) senderName = 'You';
            }

            let mediaData = {
                storageKey: null,
                downloadUrl: null
            };

            // Process media if present
            if (msg.hasMedia) {
                try {
                    console.log(`[WhatsApp] Downloading media for message in ${chat.name}`);
                    const media = await msg.downloadMedia();

                    if (media) {
                        // Determine extension
                        let extension = 'bin';
                        if (media.mimetype) {
                            extension = media.mimetype.split('/')[1];
                            if (extension && extension.includes(';')) {
                                extension = extension.split(';')[0];
                            }
                        }

                        // Filename: timestamp.extension
                        const timestamp = msg.timestamp || Math.floor(Date.now() / 1000);
                        const filename = `${timestamp}.${extension}`;

                        // Buffer
                        const buffer = Buffer.from(media.data, 'base64');

                        // Prepare file object for StorageService
                        const file = {
                            buffer: buffer,
                            originalname: filename,
                            mimetype: media.mimetype,
                            size: buffer.length
                        };

                        // Upload to Folder: CompanyId/GroupName
                        const cleanGroupName = chat.name.replace(/[^a-zA-Z0-9-_ ]/g, '_').trim(); // Ensure valid folder name
                        const folderPath = `${companyId}/${cleanGroupName}`;
                        const uploadResult = await storageService.uploadFile(file, folderPath);

                        if (uploadResult.success) {
                            mediaData.storageKey = uploadResult.key;

                            // Get presigned URL for download
                            // Note: Presigned URLs have an expiration.
                            // If the user wants a permanent URL, the storage bucket needs to be public or we need a proxy.
                            // Assuming presigned URL is acceptable for immediate use, or the app uses the 'downloadUrl' refreshes.
                            // However, saving a presigned URL to Firestore means it will expire.
                            // Better practice: Frontend should request a fresh URL using the storageKey.
                            // BUT, user explicitly said "downloadurl will be there in the message".
                            const presigned = await storageService.getPresignedDownloadUrl(uploadResult.key);
                            mediaData.downloadUrl = presigned.presignedUrl;

                            console.log(`[WhatsApp] Media saved to ${uploadResult.key}`);
                        }
                    }
                } catch (mediaError) {
                    console.error(`[WhatsApp] Error handling media:`, mediaError);
                }
            }

            // Save message to Firestore
            await this.db.collection('whatsappMessages').add({
                userId,
                companyId,
                groupId,
                groupName: chat.name,
                senderName,
                senderNumber: msg.author || msg.from,
                body: msg.body || '',
                hasMedia: msg.hasMedia,
                mediaType: msg.type,
                ...mediaData, // Add storage info
                isFromMe: msg.fromMe || false,
                timestamp: admin.firestore.Timestamp.fromDate(new Date(msg.timestamp * 1000)),
                createdAt: admin.firestore.FieldValue.serverTimestamp()
            });

        } catch (error) {
            console.error('[WhatsApp] Error handling message:', error);
        }
    }

    /**
     * Stop a WhatsApp session
     */
    async stopSession(userId, deleteAuth = true) {
        try {
            console.log(`[WhatsApp] Stopping session for user ${userId}`);

            // Clear any pending reconnect
            if (this.reconnectTimeouts.has(userId)) {
                clearTimeout(this.reconnectTimeouts.get(userId));
                this.reconnectTimeouts.delete(userId);
            }

            const session = this.activeSessions.get(userId);

            if (session && session.client) {
                if (deleteAuth) {
                    // Logout and delete auth data
                    await session.client.logout();
                } else {
                    // Just destroy client, keep auth for reconnection
                    await session.client.destroy();
                }
            }

            // Update Firestore
            await this._updateFirestoreStatus(userId, {
                status: 'disconnected',
                qrCode: admin.firestore.FieldValue.delete(),
                lastSync: admin.firestore.FieldValue.serverTimestamp()
            });

            // Clean up
            await this._cleanupSession(userId);

            if (deleteAuth) {
                this._deleteAuthData(userId);
            }

            return { success: true };

        } catch (error) {
            console.error(`[WhatsApp] Error stopping session:`, error);
            return { success: false, error: error.message };
        }
    }

    /**
     * Cancel a pending WhatsApp connection
     * Used when user cancels during QR code scanning
     * Does NOT delete auth data
     */
    async cancelSession(userId) {
        try {
            console.log(`[WhatsApp] Cancelling session for user ${userId}`);

            // Clear any pending reconnect timeouts
            if (this.reconnectTimeouts.has(userId)) {
                clearTimeout(this.reconnectTimeouts.get(userId));
                this.reconnectTimeouts.delete(userId);
            }

            // Reset reconnect attempts
            this.reconnectAttempts.set(userId, 0);

            const session = this.activeSessions.get(userId);

            if (session && session.client) {
                try {
                    // Destroy the client but don't logout (keep auth data)
                    await session.client.destroy();
                } catch (e) {
                    console.log(`[WhatsApp] Error destroying client during cancel:`, e.message);
                }
            }

            // Update Firestore to disconnected
            await this._updateFirestoreStatus(userId, {
                status: 'disconnected',
                qrCode: admin.firestore.FieldValue.delete(),
                disconnectReason: 'Connection cancelled by user',
                lastSync: admin.firestore.FieldValue.serverTimestamp()
            });

            // Clean up from memory
            await this._cleanupSession(userId);

            return { success: true, message: 'Connection cancelled' };

        } catch (error) {
            console.error(`[WhatsApp] Error cancelling session:`, error);
            return { success: false, error: error.message };
        }
    }

    /**
     * Get current session status from memory
     */
    getSessionStatus(userId) {
        const session = this.activeSessions.get(userId);
        const qrCode = this.qrCodes.get(userId);

        if (!session) {
            return { status: 'disconnected' };
        }

        return {
            status: session.status,
            phone: session.phone,
            name: session.name,
            qrCode: qrCode || null
        };
    }

    /**
     * Get WhatsApp groups for a connected user
     */
    async getGroups(userId) {
        const session = this.activeSessions.get(userId);

        if (!session || session.status !== 'connected') {
            throw new Error('Not connected');
        }

        const chats = await session.client.getChats();
        const groups = chats
            .filter(chat => chat.isGroup)
            .map(chat => ({
                id: chat.id._serialized,
                name: chat.name,
                participantCount: chat.participants ? chat.participants.length : 0
            }));

        return groups;
    }

    /**
     * Start heartbeat monitoring for a session
     */
    _startHeartbeat(userId) {
        // Clear any existing heartbeat
        this._stopHeartbeat(userId);

        const interval = setInterval(async () => {
            await this._checkSessionHealth(userId);
        }, CONFIG.HEARTBEAT_INTERVAL);

        this.heartbeatIntervals.set(userId, interval);
        console.log(`[WhatsApp] Heartbeat started for ${userId}`);
    }

    /**
     * Stop heartbeat monitoring
     */
    _stopHeartbeat(userId) {
        if (this.heartbeatIntervals.has(userId)) {
            clearInterval(this.heartbeatIntervals.get(userId));
            this.heartbeatIntervals.delete(userId);
        }
    }

    /**
     * Check session health
     */
    async _checkSessionHealth(userId) {
        const session = this.activeSessions.get(userId);

        if (!session || !session.client) {
            console.log(`[WhatsApp] No session found for ${userId} during heartbeat`);
            this._stopHeartbeat(userId);
            return;
        }

        try {
            const clientState = await session.client.getState();
            console.log(`[WhatsApp] Heartbeat for ${userId}: ${clientState}`);

            if (clientState === 'CONNECTED') {
                // Update last heartbeat in Firestore
                await this.db.collection('whatsappSessions').doc(userId).update({
                    lastHeartbeat: admin.firestore.FieldValue.serverTimestamp()
                });
            } else if (clientState === 'UNPAIRED' || clientState === 'UNLAUNCHED') {
                console.log(`[WhatsApp] Unhealthy state for ${userId}, scheduling reconnect`);
                this._scheduleReconnect(userId, session.companyId);
            }
        } catch (err) {
            console.error(`[WhatsApp] Heartbeat error for ${userId}:`, err.message);

            if (err.message?.includes('ECONNREFUSED') ||
                err.message?.includes('Protocol error') ||
                err.message?.includes('Session closed')) {
                console.log(`[WhatsApp] Connection issue detected, scheduling reconnect`);
                this._scheduleReconnect(userId, session.companyId);
            }
        }
    }

    /**
     * Schedule reconnection with exponential backoff
     */
    _scheduleReconnect(userId, companyId) {
        // Don't schedule if already scheduled
        if (this.reconnectTimeouts.has(userId)) {
            console.log(`[WhatsApp] Reconnect already scheduled for ${userId}`);
            return;
        }

        const attempts = this.reconnectAttempts.get(userId) || 0;

        if (attempts >= CONFIG.MAX_RECONNECT_ATTEMPTS) {
            console.log(`[WhatsApp] Max reconnect attempts reached for ${userId}`);
            this._updateFirestoreStatus(userId, {
                status: 'disconnected',
                disconnectReason: 'Max reconnect attempts reached. Please reconnect manually.'
            });
            this._cleanupSession(userId);
            return;
        }

        this.reconnectAttempts.set(userId, attempts + 1);

        // Exponential backoff
        const delay = Math.min(
            CONFIG.RECONNECT_BASE_DELAY * Math.pow(2, attempts),
            CONFIG.RECONNECT_MAX_DELAY
        );

        console.log(`[WhatsApp] Scheduling reconnect for ${userId} in ${delay}ms (attempt ${attempts + 1})`);

        const timeout = setTimeout(async () => {
            this.reconnectTimeouts.delete(userId);

            try {
                // Clean up old client first
                const oldSession = this.activeSessions.get(userId);
                if (oldSession && oldSession.client) {
                    try {
                        await oldSession.client.destroy();
                    } catch (e) {
                        // Ignore destroy errors
                    }
                    this.activeSessions.delete(userId);
                }

                // Try to restore session
                await this.startSession(userId, companyId);
            } catch (err) {
                console.error(`[WhatsApp] Reconnect failed for ${userId}:`, err.message);
                // Will try again on next heartbeat or event
            }
        }, delay);

        this.reconnectTimeouts.set(userId, timeout);
    }

    /**
     * Update Firestore status
     */
    async _updateFirestoreStatus(userId, data) {
        try {
            await this.db
                .collection('whatsappSessions')
                .doc(userId)
                .set(data, { merge: true });
        } catch (error) {
            console.error('[WhatsApp] Firestore update error:', error);
        }
    }

    /**
     * Clean up session from memory
     */
    async _cleanupSession(userId) {
        this._stopHeartbeat(userId);
        this.activeSessions.delete(userId);
        this.qrCodes.delete(userId);
    }

    /**
     * Delete authentication data
     */
    _deleteAuthData(userId) {
        try {
            const authPath = path.join(process.cwd(), '.wwebjs_auth', `session-${userId}`);
            if (fs.existsSync(authPath)) {
                console.log(`[WhatsApp] Removing auth directory for ${userId}`);
                fs.rmSync(authPath, { recursive: true, force: true });
            }
        } catch (e) {
            console.error(`[WhatsApp] Error clearing auth directory for ${userId}:`, e.message);
        }
    }

    /**
     * Restore sessions that should be active
     * called on server startup
     */
    async restoreSessions() {
        console.log('[WhatsApp] Restoring sessions...');
        try {
            // Get all sessions that were 'connected'
            const snapshot = await this.db.collection('whatsappSessions')
                .where('status', '==', 'connected')
                .get();

            if (snapshot.empty) {
                console.log('[WhatsApp] No active sessions to restore.');
                return;
            }

            console.log(`[WhatsApp] Found ${snapshot.size} sessions to restore.`);

            for (const doc of snapshot.docs) {
                const userId = doc.id;
                const data = doc.data();

                if (data.companyId) {
                    console.log(`[WhatsApp] Restoring session for ${userId}...`);
                    // We don't await this to allow parallel restoration
                    this.startSession(userId, data.companyId).catch(err => {
                        console.error(`[WhatsApp] Failed to restore session for ${userId}:`, err.message);
                    });
                }
            }
        } catch (error) {
            console.error('[WhatsApp] Error restoring sessions:', error);
        }
    }

    /**
     * Cleanup all sessions on server shutdown
     * Only destroys the client instance, leaves DB status as is so we can restore on restart
     */
    async cleanup() {
        console.log('[WhatsApp] Cleaning up all sessions...');

        const userIds = Array.from(this.activeSessions.keys());

        for (const userId of userIds) {
            try {
                const session = this.activeSessions.get(userId);
                if (session && session.client) {
                    await session.client.destroy();
                }
                this.activeSessions.delete(userId);
                this._stopHeartbeat(userId);
            } catch (error) {
                console.error(`[WhatsApp] Error cleaning up session for ${userId}:`, error);
            }
        }
    }
}

module.exports = WhatsAppSessionManager;