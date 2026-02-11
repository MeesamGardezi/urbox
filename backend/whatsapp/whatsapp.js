/**
 * WhatsApp REST API Routes
 * 
 * Pure REST API endpoints (no Socket.IO)
 * Frontend polls these endpoints on page load/refresh only
 */

const express = require('express');
const admin = require('firebase-admin');

function createWhatsAppRoutes(db, sessionManager) {
    const router = express.Router();

    /**
     * GET /status
     * Get WhatsApp connection status for a user
     */
    router.get('/status', async (req, res) => {
        const { userId } = req.query;

        if (!userId) {
            return res.status(400).json({
                success: false,
                error: 'Missing userId parameter'
            });
        }

        try {
            // First try to get from memory (fastest)
            const memoryStatus = sessionManager.getSessionStatus(userId);

            // If connected in memory, return immediately
            if (memoryStatus.status === 'connected' || memoryStatus.status === 'qr_pending') {
                return res.json({
                    success: true,
                    data: memoryStatus
                });
            }

            // Otherwise, check Firestore for persistent state
            const doc = await db.collection('whatsappSessions').doc(userId).get();

            if (!doc.exists) {
                return res.json({
                    success: true,
                    data: { status: 'disconnected' }
                });
            }

            const firestoreData = doc.data();

            res.json({
                success: true,
                data: {
                    status: firestoreData.status || 'disconnected',
                    phone: firestoreData.phone || null,
                    name: firestoreData.name || null,
                    connectedAt: firestoreData.connectedAt || null,
                    lastSync: firestoreData.lastSync || null
                }
            });

        } catch (error) {
            console.error('[WhatsApp API] Status error:', error);
            res.status(500).json({
                success: false,
                error: error.message
            });
        }
    });

    /**
     * GET /qr
     * Get QR code for scanning (if status is qr_pending)
     */
    router.get('/qr', async (req, res) => {
        const { userId } = req.query;

        if (!userId) {
            return res.status(400).json({
                success: false,
                error: 'Missing userId parameter'
            });
        }

        try {
            const status = sessionManager.getSessionStatus(userId);

            if (status.status === 'qr_pending' && status.qrCode) {
                return res.json({
                    success: true,
                    qrCode: status.qrCode
                });
            }

            // Fallback to Firestore
            const doc = await db.collection('whatsappSessions').doc(userId).get();

            if (doc.exists && doc.data().qrCode) {
                return res.json({
                    success: true,
                    qrCode: doc.data().qrCode
                });
            }

            res.json({
                success: false,
                error: 'No QR code available'
            });

        } catch (error) {
            console.error('[WhatsApp API] QR error:', error);
            res.status(500).json({
                success: false,
                error: error.message
            });
        }
    });

    /**
     * POST /connect
     * Start a new WhatsApp session
     */
    router.post('/connect', async (req, res) => {
        const { userId, companyId } = req.body;

        if (!userId || !companyId) {
            return res.status(400).json({
                success: false,
                error: 'Missing required fields: userId, companyId'
            });
        }

        try {
            const result = await sessionManager.startSession(userId, companyId);
            res.json(result);

        } catch (error) {
            console.error('[WhatsApp API] Connect error:', error);
            res.status(500).json({
                success: false,
                error: error.message
            });
        }
    });

    /**
     * POST /disconnect
     * Stop WhatsApp session
     */
    router.post('/disconnect', async (req, res) => {
        const { userId, deleteAuth = true } = req.body;

        if (!userId) {
            return res.status(400).json({
                success: false,
                error: 'Missing userId'
            });
        }

        try {
            const result = await sessionManager.stopSession(userId, deleteAuth);
            res.json(result);

        } catch (error) {
            console.error('[WhatsApp API] Disconnect error:', error);
            res.status(500).json({
                success: false,
                error: error.message
            });
        }
    });

    /**
     * POST /cancel
     * Cancel a pending WhatsApp connection (during QR scanning)
     * Does NOT delete auth data - just stops the current session
     */
    router.post('/cancel', async (req, res) => {
        const { userId } = req.body;

        if (!userId) {
            return res.status(400).json({
                success: false,
                error: 'Missing userId'
            });
        }

        try {
            console.log(`[WhatsApp API] Cancelling connection for ${userId}`);
            const result = await sessionManager.cancelSession(userId);
            res.json(result);

        } catch (error) {
            console.error('[WhatsApp API] Cancel error:', error);
            res.status(500).json({
                success: false,
                error: error.message
            });
        }
    });

    /**
     * GET /groups
     * Get list of WhatsApp groups for connected user
     */
    router.get('/groups', async (req, res) => {
        const { userId } = req.query;

        if (!userId) {
            return res.status(400).json({
                success: false,
                error: 'Missing userId parameter'
            });
        }

        try {
            const groups = await sessionManager.getGroups(userId);

            res.json({
                success: true,
                groups
            });

        } catch (error) {
            console.error('[WhatsApp API] Groups error:', error);

            if (error.message === 'Not connected') {
                return res.status(400).json({
                    success: false,
                    error: 'WhatsApp not connected'
                });
            }

            res.status(500).json({
                success: false,
                error: error.message
            });
        }
    });

    /**
     * POST /monitor
     * Toggle monitoring for a specific group
     */
    router.post('/monitor', async (req, res) => {
        const { userId, companyId, groupId, groupName, isMonitoring } = req.body;

        if (!userId || !companyId || !groupId || !groupName) {
            return res.status(400).json({
                success: false,
                error: 'Missing required fields'
            });
        }

        try {
            // Check if group monitoring entry already exists
            const existing = await db
                .collection('whatsappGroups')
                .where('userId', '==', userId)
                .where('groupId', '==', groupId)
                .limit(1)
                .get();

            if (!existing.empty) {
                // Update existing
                const doc = existing.docs[0];
                await doc.ref.update({
                    isMonitoring: isMonitoring,
                    groupName: groupName,
                    updatedAt: admin.firestore.FieldValue.serverTimestamp()
                });
            } else {
                // Create new
                await db.collection('whatsappGroups').add({
                    userId,
                    companyId,
                    groupId,
                    groupName,
                    isMonitoring: isMonitoring,
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                    updatedAt: admin.firestore.FieldValue.serverTimestamp()
                });
            }

            console.log(`[WhatsApp] ${isMonitoring ? 'Enabled' : 'Disabled'} monitoring for group ${groupName}`);

            res.json({ success: true });

        } catch (error) {
            console.error('[WhatsApp API] Monitor error:', error);
            res.status(500).json({
                success: false,
                error: error.message
            });
        }
    });

    /**
     * GET /monitored
     * Get list of monitored groups for a user
     */
    router.get('/monitored', async (req, res) => {
        const { userId, companyId } = req.query;

        if (!userId) {
            return res.status(400).json({
                success: false,
                error: 'Missing userId parameter'
            });
        }

        try {
            const snapshot = await db
                .collection('whatsappGroups')
                .where('userId', '==', userId)
                .where('isMonitoring', '==', true)
                .get();

            const groups = snapshot.docs.map(doc => ({
                id: doc.id,
                ...doc.data()
            }));

            res.json({
                success: true,
                groups
            });

        } catch (error) {
            console.error('[WhatsApp API] Monitored groups error:', error);
            res.status(500).json({
                success: false,
                error: error.message
            });
        }
    });

    /**
     * GET /messages
     * Get messages with pagination (called on page load/refresh only)
     * Supports filtering by groupId and text search
     */
    router.get('/messages', async (req, res) => {
        const { userId, companyId, groupId, limit = 50, startAfter, searchQuery } = req.query;

        if (!userId && !companyId) {
            return res.status(400).json({
                success: false,
                error: 'Missing userId or companyId parameter'
            });
        }

        try {
            // Fetch messages by userId OR companyId
            let query = db.collection('whatsappMessages');

            if (companyId) {
                // Fetch by companyId (for team members)
                query = query.where('companyId', '==', companyId);
            } else {
                // Fetch by userId (for owner/backward compatibility)
                query = query.where('userId', '==', userId);
            }

            const snapshot = await query.get();

            let allMessages = snapshot.docs.map(doc => ({
                id: doc.id,
                ...doc.data()
            }));

            // Filter by specific group if provided
            if (groupId) {
                allMessages = allMessages.filter(msg => msg.groupId === groupId);
            }

            // Filter by search query if provided
            if (searchQuery) {
                const query = searchQuery.toLowerCase();
                allMessages = allMessages.filter(msg =>
                    (msg.body && msg.body.toLowerCase().includes(query)) ||
                    (msg.senderName && msg.senderName.toLowerCase().includes(query)) ||
                    (msg.senderNumber && msg.senderNumber.toLowerCase().includes(query)) ||
                    (msg.groupName && msg.groupName.toLowerCase().includes(query))
                );
            }

            // Sort by timestamp desc
            allMessages.sort((a, b) => {
                const timeA = a.timestamp && typeof a.timestamp.toMillis === 'function' ? a.timestamp.toMillis() : 0;
                const timeB = b.timestamp && typeof b.timestamp.toMillis === 'function' ? b.timestamp.toMillis() : 0;
                return timeB - timeA;
            });

            // Pagination - start after a specific document
            let startIndex = 0;
            if (startAfter) {
                const foundIndex = allMessages.findIndex(msg => msg.id === startAfter);
                if (foundIndex !== -1) {
                    startIndex = foundIndex + 1;
                }
            }

            const limitVal = parseInt(limit);
            const slicedMessages = allMessages.slice(startIndex, startIndex + limitVal);
            const hasMore = allMessages.length > (startIndex + limitVal);
            const lastDocId = slicedMessages.length > 0 ? slicedMessages[slicedMessages.length - 1].id : null;

            const messages = slicedMessages.map(msg => ({
                ...msg,
                // Convert Firestore timestamp to ISO string for JSON
                timestamp: msg.timestamp && typeof msg.timestamp.toDate === 'function' ? msg.timestamp.toDate().toISOString() : null,
                createdAt: msg.createdAt && typeof msg.createdAt.toDate === 'function' ? msg.createdAt.toDate().toISOString() : null
            }));

            res.json({
                success: true,
                messages,
                hasMore,
                lastDocId
            });

        } catch (error) {
            console.error('[WhatsApp API] Messages error:', error);
            res.status(500).json({
                success: false,
                error: error.message
            });
        }
    });

    /**
     * GET /messages/count
     * Get unread message count (for badge)
     */
    router.get('/messages/count', async (req, res) => {
        const { userId, since } = req.query;

        if (!userId) {
            return res.status(400).json({
                success: false,
                error: 'Missing userId parameter'
            });
        }

        try {
            // Count messages since a specific timestamp
            // Perform in memory to avoid composite index requirement
            if (since) {
                const snapshot = await db.collection('whatsappMessages')
                    .where('userId', '==', userId)
                    .get();

                const sinceTime = new Date(since).getTime();

                const count = snapshot.docs.reduce((acc, doc) => {
                    const ts = doc.data().timestamp;
                    const time = ts && typeof ts.toMillis === 'function' ? ts.toMillis() : 0;
                    return time > sinceTime ? acc + 1 : acc;
                }, 0);

                res.json({
                    success: true,
                    count
                });
            } else {
                // Simple count is supported without composite index
                const snapshot = await db.collection('whatsappMessages')
                    .where('userId', '==', userId)
                    .count()
                    .get();

                res.json({
                    success: true,
                    count: snapshot.data().count
                });
            }

        } catch (error) {
            console.error('[WhatsApp API] Count error:', error);
            res.status(500).json({
                success: false,
                error: error.message
            });
        }
    });

    return router;
}

module.exports = createWhatsAppRoutes;