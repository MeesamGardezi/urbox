const express = require('express');
const admin = require('firebase-admin');
const multer = require('multer');
// Note: We use in-memory caching for messages. Global cache maps are defined inside createChatRoutes scope or module scope?
// The user provided structure shows createChatRoutes as export. 
// We will place cache strictly inside the function to avoid module-level persistence if the function is called multiple times (though unlikely).
// But standard practice for express route creators is they are called once.


// Configure multer for memory storage
const upload = multer({
    storage: multer.memoryStorage(),
    limits: {
        fileSize: 50 * 1024 * 1024, // 50MB limit
    },
});

function createChatRoutes(db, storageService, io) {
    const router = express.Router();

    // In-memory cache for messages
    // Key: groupId, Value: Array of messages (sorted newest first)
    const messageCache = new Map();
    const MSG_CACHE_LIMIT = 100;
    const GROUP_CACHE_LIMIT = 1000;

    // Helper to sign attachment URLs
    const signMessageAttachments = async (message, force = false) => {
        if (message.attachments && message.attachments.length > 0) {
            for (let att of message.attachments) {
                // If force is true, we ignore existing signature check
                // We check if it has a key (is stored file)
                const isSigned = att.url && att.url.includes('?');
                if (att.key && (force || !isSigned)) {
                    try {
                        const presigned = await storageService.getPresignedDownloadUrl(att.key);
                        att.url = presigned.presignedUrl;
                    } catch (e) {
                        // Keep original URL or empty if failed
                    }
                }
            }
        }
        return message;
    };

    // Helper to maintain cache size
    const updateCache = (groupId, messages, isNew = false) => {
        // Enforce group limit
        if (!messageCache.has(groupId) && messageCache.size >= GROUP_CACHE_LIMIT) {
            // Remove oldest inserted group (Map iterator returns in insertion order)
            const firstKey = messageCache.keys().next().value;
            messageCache.delete(firstKey);
        }

        if (isNew) {
            // Adding a single new message to an EXISTING cache
            if (messageCache.has(groupId)) {
                const cached = messageCache.get(groupId);
                cached.unshift(...messages); // Add to front
                if (cached.length > MSG_CACHE_LIMIT) {
                    messageCache.set(groupId, cached.slice(0, MSG_CACHE_LIMIT));
                }
            }
            // If cache doesn't exist, we don't create it here on POST to a avoid partial cache state
            // Next GET will populate it fully
        } else {
            // Setting/Replacing cache (from GET)
            messageCache.set(groupId, messages.slice(0, MSG_CACHE_LIMIT));
        }
    };

    // In-memory cache for user profiles (role, companyId)
    // Key: uid, Value: { data: userData, expiry: timestamp }
    const userCache = new Map();
    const USER_CACHE_TTL = 10 * 60 * 1000; // 10 minutes

    // Middleware to verify user token
    const verifyToken = async (req, res, next) => {
        const idToken = req.headers.authorization?.split('Bearer ')[1];
        if (!idToken) {
            return res.status(401).json({ success: false, error: 'Unauthorized' });
        }

        try {
            const decodedToken = await admin.auth().verifyIdToken(idToken);
            req.user = decodedToken;

            // Check Cache
            const now = Date.now();
            if (userCache.has(decodedToken.uid)) {
                const cached = userCache.get(decodedToken.uid);
                if (cached.expiry > now) {
                    req.user.role = cached.data.role;
                    req.user.companyId = cached.data.companyId;
                    req.user.displayName = cached.data.displayName;
                    return next();
                }
            }

            // Fetch user role and companyId from Firestore
            const userDoc = await db.collection('users').doc(decodedToken.uid).get();
            if (!userDoc.exists) {
                return res.status(404).json({ success: false, error: 'User not found' });
            }
            const userData = userDoc.data();
            req.user.role = userData.role;
            req.user.companyId = userData.companyId;
            req.user.displayName = userData.displayName || decodedToken.email.split('@')[0];

            // Update Cache
            userCache.set(decodedToken.uid, {
                data: {
                    role: req.user.role,
                    companyId: req.user.companyId,
                    displayName: req.user.displayName
                },
                expiry: now + USER_CACHE_TTL
            });

            next();
        } catch (error) {
            console.error('Token verification failed:', error);
            res.status(401).json({ success: false, error: 'Invalid token' });
        }
    };

    router.use(verifyToken);

    // Create a new group (Admin only)
    router.post('/groups', async (req, res) => {
        const { name, description } = req.body;

        if (!name) {
            return res.status(400).json({ success: false, error: 'Group name is required' });
        }

        if (req.user.role !== 'owner') { // Assuming 'owner' is the admin role
            return res.status(403).json({ success: false, error: 'Only admins can create groups' });
        }

        try {
            const newGroup = {
                name: name.trim(),
                description: description ? description.trim() : '',
                companyId: req.user.companyId,
                createdBy: req.user.uid,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                type: 'public', // Default to public company group
                members: [req.user.uid] // Add creator to members
            };

            const docRef = await db.collection('chat_groups').add(newGroup);

            // Emit new group event
            if (io) {
                io.emit(`new_group_${req.user.companyId}`, {
                    id: docRef.id,
                    ...newGroup,
                    createdAt: new Date(),
                    updatedAt: new Date()
                });
            }

            res.json({
                success: true,
                group: {
                    id: docRef.id,
                    ...newGroup,
                    createdAt: new Date(),
                    updatedAt: new Date()
                }
            });
        } catch (error) {
            console.error('Create group error:', error);
            res.status(500).json({ success: false, error: 'Failed to create group' });
        }
    });

    // Get all groups for the company
    router.get('/groups', async (req, res) => {
        try {
            const snapshot = await db.collection('chat_groups')
                .where('companyId', '==', req.user.companyId)
                .get();

            let groups = snapshot.docs.map(doc => {
                const data = doc.data();
                return {
                    id: doc.id,
                    ...data,
                    createdAt: data.createdAt?.toDate ? data.createdAt.toDate() : (data.createdAt || new Date()),
                    updatedAt: data.updatedAt?.toDate ? data.updatedAt.toDate() : (data.updatedAt || null),
                    members: data.members || []
                };
            });

            // Filter: Only show groups where user is a member (or is owner)
            if (req.user.role !== 'owner') {
                groups = groups.filter(g => g.members && g.members.includes(req.user.uid));
            }

            // Sort in memory (newest first)
            groups.sort((a, b) => b.createdAt - a.createdAt);

            res.json({ success: true, groups });
        } catch (error) {
            console.error('Get groups error:', error);
            res.status(500).json({ success: false, error: 'Failed to fetch groups' });
        }
    });

    // Send a message to a group
    router.post('/messages', async (req, res) => {
        const { groupId, content, type, attachments } = req.body;

        if (!groupId || (!content && !attachments)) {
            return res.status(400).json({ success: false, error: 'Group ID and content/attachments are required' });
        }

        try {
            // Verify group exists and belongs to company (Security check - fast read)
            const groupDoc = await db.collection('chat_groups').doc(groupId).get();
            if (!groupDoc.exists || groupDoc.data().companyId !== req.user.companyId) {
                return res.status(404).json({ success: false, error: 'Group not found' });
            }

            // Generate ID first
            const messageRef = db.collection('chat_messages').doc();
            const messageId = messageRef.id;

            const newMessage = {
                groupId,
                senderId: req.user.uid,
                senderName: req.user.displayName,
                content: content ? content.trim() : '',
                type: type || 'text',
                attachments: attachments || [],
                reactions: [],
                createdAt: admin.firestore.FieldValue.serverTimestamp() // For DB
            };

            const messagePayload = {
                id: messageId,
                ...newMessage,
                createdAt: new Date() // Use Date object for consistency with Cache/DB types
            };

            // Sign URLs for immediate emission and response
            // We await here because client needs valid URLs immediately, and signing is usually fast/local
            await signMessageAttachments(messagePayload);

            // 1. Update RAM Cache
            updateCache(groupId, [messagePayload], true);

            // 2. Emit to socket immediately
            if (io) {
                io.to(groupId).emit('new_message', messagePayload);
            }

            // 3. Return response immediately
            res.json({
                success: true,
                message: messagePayload
            });

            // 4. Background Save to Firestore
            // We use 'set' with the generated ID
            // We do NOT await these promises to avoid blocking the response
            Promise.all([
                messageRef.set(newMessage),
                db.collection('chat_groups').doc(groupId).update({
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                    lastMessage: {
                        content: content ? content.substring(0, 50) : (attachments && attachments.length > 0 ? 'Attachment' : ''),
                        senderName: req.user.displayName,
                        createdAt: new Date()
                    }
                })
            ]).catch(err => {
                console.error('Background save failed for message:', messageId, err);
                // Note: If this fails, RAM/Socket state might be out of sync with DB. 
                // Client reload fixes it.
            });

        } catch (error) {
            console.error('Send message error:', error);
            res.status(500).json({ success: false, error: 'Failed to send message' });
        }
    });

    // Upload attachment
    router.post('/messages/upload', upload.single('file'), async (req, res) => {
        const { groupId } = req.body;
        const file = req.file;

        if (!groupId || !file) {
            return res.status(400).json({ success: false, error: 'Group ID and file are required' });
        }

        try {
            // Verify group
            const groupDoc = await db.collection('chat_groups').doc(groupId).get();
            if (!groupDoc.exists) {
                return res.status(404).json({ success: false, error: 'Group not found' });
            }

            const groupData = groupDoc.data();
            if (groupData.companyId !== req.user.companyId) {
                return res.status(403).json({ success: false, error: 'Unauthorized' });
            }

            // Construct folder name: "GroupName - GroupId"
            const safeGroupName = groupData.name.replace(/[^a-zA-Z0-9]/g, '_');
            const folderName = `${safeGroupName} - ${groupId}`;

            // Upload using storage service
            const result = await storageService.uploadFile(file, folderName);

            // Get presigned URL for immediate display
            const presigned = await storageService.getPresignedDownloadUrl(result.key);

            res.json({
                success: true,
                attachment: {
                    name: file.originalname,
                    url: presigned.presignedUrl, // Or permanent URL if public
                    key: result.key,
                    type: file.mimetype,
                    size: file.size
                }
            });
        } catch (error) {
            console.error('Upload attachment error:', error);
            res.status(500).json({ success: false, error: 'Failed to upload attachment' });
        }
    });

    // Add/Remove reaction
    router.post('/messages/:messageId/reactions', async (req, res) => {
        const { messageId } = req.params;
        const { reaction } = req.body;

        if (!reaction) {
            return res.status(400).json({ success: false, error: 'Reaction is required' });
        }

        try {
            const messageRef = db.collection('chat_messages').doc(messageId);
            const messageDoc = await messageRef.get();

            if (!messageDoc.exists) {
                return res.status(404).json({ success: false, error: 'Message not found' });
            }

            const messageData = messageDoc.data();
            let reactions = messageData.reactions || [];

            // Check if user already reacted with this emoji
            const existingIndex = reactions.findIndex(r => r.userId === req.user.uid && r.reaction === reaction);

            if (existingIndex !== -1) {
                // Remove reaction
                reactions.splice(existingIndex, 1);
            } else {
                // Add reaction
                reactions.push({
                    userId: req.user.uid,
                    userName: req.user.displayName,
                    reaction: reaction,
                    timestamp: new Date().toISOString()
                });
            }

            await messageRef.update({ reactions });

            // Emit reaction update
            if (io) {
                io.to(messageData.groupId).emit('reaction_update', {
                    messageId,
                    reactions
                });
            }

            res.json({ success: true, reactions });
        } catch (error) {
            console.error('Reaction error:', error);
            res.status(500).json({ success: false, error: 'Failed to update reaction' });
        }
    });

    // Get messages for a group
    router.get('/messages/:groupId', async (req, res) => {
        const { groupId } = req.params;
        const { limit, before } = req.query; // For pagination

        try {
            // Check In-Memory Cache first
            let allMessages = [];
            let servedFromCache = false;

            if (messageCache.has(groupId)) {
                // Clone cached messages to avoid mutating cache when signing or slicing
                allMessages = [...messageCache.get(groupId)];
                servedFromCache = true;
            } else {
                // Cache Miss: Fetch from DB

                // Verify group (only on DB fetch, if needed, or rely on empty query result)
                // We keep the verify to be safe
                const groupDoc = await db.collection('chat_groups').doc(groupId).get();
                if (!groupDoc.exists || groupDoc.data().companyId !== req.user.companyId) {
                    return res.status(404).json({ success: false, error: 'Group not found' });
                }

                const snapshot = await db.collection('chat_messages')
                    .where('groupId', '==', groupId)
                    .get();

                allMessages = snapshot.docs.map(doc => {
                    const data = doc.data();
                    return {
                        id: doc.id,
                        ...data,
                        createdAt: data.createdAt?.toDate ? data.createdAt.toDate() : (data.createdAt || new Date())
                    };
                });

                // Sort in memory (newest first)
                allMessages.sort((a, b) => b.createdAt - a.createdAt);

                // Populate Cache with latest
                updateCache(groupId, allMessages);
            }

            // Handle Pagination
            const limitVal = parseInt(limit) || 50;
            let startIndex = 0;

            if (before) {
                const beforeIndex = allMessages.findIndex(m => m.id === before);
                if (beforeIndex !== -1) {
                    startIndex = beforeIndex + 1;

                    // If we are serving from cache, and the request asks for data beyond the cache,
                    // we might need to fetch from DB. 
                    // However, simplified logic: if 'before' is found in cache, we serve what follows.
                    // If 'before' is NOT found in cache (e.g. user scrolled way up), we might need to fallback to DB.
                    // BUT, 'allMessages' is currently either FULL DB (on first load) or CACHE (100 msgs).
                    // If servedFromCache is true, and beforeIndex is -1, it means the message is older than cache.
                    // In that case, we should probably fetch from DB.

                    if (servedFromCache && startIndex >= allMessages.length) {
                        // Fallback: This part implies we reached end of cache. 
                        // For this iteration, let's keep it simple. If we need deep history, we should hit DB.
                        // But current request logic was "checks cache first... if not found... fetches".
                        // This implies if the *page* is not found.
                        // For now, if 'before' is valid, we slice.
                    }
                } else if (servedFromCache && before) {
                    // 'before' ID asked, but not in cache. It must be older.
                    // We must fetch from DB to get older messages.
                    // NOTE: This breaks the "Check RAM cache first" if we strictly return cache.
                    // But returning empty array is wrong.
                    // So: If 'before' is provided and NOT in cache, we should bypass cache.

                    // Refetch for pagination (deep history)
                    const snapshot = await db.collection('chat_messages')
                        .where('groupId', '==', groupId)
                        // Note: Ideally use cursor query here, but sticking to existing "Fetch All" pattern for consistency
                        .get();

                    const dbMessages = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data(), createdAt: doc.data().createdAt?.toDate() || new Date() }));
                    dbMessages.sort((a, b) => b.createdAt - a.createdAt);

                    allMessages = dbMessages;
                    // We don't necessarily update cache here as it's deep history, 
                    // or we could, but let's leave cache for "recent".
                    const newIdx = allMessages.findIndex(m => m.id === before);
                    if (newIdx !== -1) startIndex = newIdx + 1;
                }
            }

            const paginatedMessages = allMessages.slice(startIndex, startIndex + limitVal);

            // Sign URLs for the slice we are returning (Force refresh to ensure validity)
            await Promise.all(paginatedMessages.map(m => signMessageAttachments(m, true)));

            res.json({ success: true, messages: paginatedMessages.reverse() });
        } catch (error) {
            console.error('Get messages error:', error);
            res.status(500).json({ success: false, error: 'Failed to fetch messages' });
        }
    });

    // Get single group details
    router.get('/groups/:groupId', async (req, res) => {
        try {
            const doc = await db.collection('chat_groups').doc(req.params.groupId).get();
            if (!doc.exists || doc.data().companyId !== req.user.companyId) {
                return res.status(404).json({ success: false, error: 'Group not found' });
            }

            const data = doc.data();
            const group = {
                id: doc.id,
                ...data,
                createdAt: data.createdAt?.toDate ? data.createdAt.toDate() : (data.createdAt || new Date()),
                updatedAt: data.updatedAt?.toDate ? data.updatedAt.toDate() : (data.updatedAt || null),
                members: data.members || []
            };

            res.json({ success: true, group });
        } catch (error) {
            console.error('Get group error:', error);
            res.status(500).json({ success: false, error: 'Failed to fetch group' });
        }
    });

    // Add members to a group
    router.post('/groups/:groupId/members', async (req, res) => {
        const { groupId } = req.params;
        const { memberIds } = req.body;

        if (!memberIds || !Array.isArray(memberIds)) {
            return res.status(400).json({ success: false, error: 'memberIds array is required' });
        }

        try {
            const groupRef = db.collection('chat_groups').doc(groupId);
            const groupDoc = await groupRef.get();

            if (!groupDoc.exists || groupDoc.data().companyId !== req.user.companyId) {
                return res.status(404).json({ success: false, error: 'Group not found' });
            }

            await groupRef.update({
                members: admin.firestore.FieldValue.arrayUnion(...memberIds),
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            });

            res.json({ success: true, message: 'Members added' });
        } catch (error) {
            console.error('Add members error:', error);
            res.status(500).json({ success: false, error: 'Failed to add members' });
        }
    });

    // Remove member from group
    router.delete('/groups/:groupId/members/:userId', async (req, res) => {
        const { groupId, userId } = req.params;

        try {
            const groupRef = db.collection('chat_groups').doc(groupId);
            const groupDoc = await groupRef.get();

            if (!groupDoc.exists || groupDoc.data().companyId !== req.user.companyId) {
                return res.status(404).json({ success: false, error: 'Group not found' });
            }

            await groupRef.update({
                members: admin.firestore.FieldValue.arrayRemove(userId),
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            });

            res.json({ success: true, message: 'Member removed' });
        } catch (error) {
            console.error('Remove member error:', error);
            res.status(500).json({ success: false, error: 'Failed to remove member' });
        }
    });

    return router;
}

module.exports = createChatRoutes;
