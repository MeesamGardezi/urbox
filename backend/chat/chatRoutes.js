const express = require('express');
const admin = require('firebase-admin');

function createChatRoutes(db) {
    const router = express.Router();

    // Middleware to verify user token
    const verifyToken = async (req, res, next) => {
        const idToken = req.headers.authorization?.split('Bearer ')[1];
        if (!idToken) {
            return res.status(401).json({ success: false, error: 'Unauthorized' });
        }

        try {
            const decodedToken = await admin.auth().verifyIdToken(idToken);
            req.user = decodedToken;

            // Fetch user role and companyId from Firestore
            const userDoc = await db.collection('users').doc(decodedToken.uid).get();
            if (!userDoc.exists) {
                return res.status(404).json({ success: false, error: 'User not found' });
            }
            const userData = userDoc.data();
            req.user.role = userData.role;
            req.user.companyId = userData.companyId;
            req.user.displayName = userData.displayName || decodedToken.email.split('@')[0];

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
            // Allow detailed check if we want 'admin' role too? 
            // Based on auth.js, 'owner' and 'member' seem to be the main roles.
            // If we want to allow members to create groups, we can remove this check.
            // But request said "admin can create groups".
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
                members: [] // Potentially use later for private groups
            };

            const docRef = await db.collection('chat_groups').add(newGroup);

            res.json({
                success: true,
                group: { id: docRef.id, ...newGroup }
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
                .orderBy('createdAt', 'desc') // Show newest first ? Or alphabetical?
                .get();

            const groups = snapshot.docs.map(doc => ({
                id: doc.id,
                ...doc.data(),
                createdAt: doc.data().createdAt?.toDate() || new Date()
            }));

            res.json({ success: true, groups });
        } catch (error) {
            console.error('Get groups error:', error);
            res.status(500).json({ success: false, error: 'Failed to fetch groups' });
        }
    });

    // Send a message to a group
    router.post('/messages', async (req, res) => {
        const { groupId, content, type } = req.body;

        if (!groupId || !content) {
            return res.status(400).json({ success: false, error: 'Group ID and content are required' });
        }

        try {
            // Verify group exists and belongs to company
            const groupDoc = await db.collection('chat_groups').doc(groupId).get();
            if (!groupDoc.exists || groupDoc.data().companyId !== req.user.companyId) {
                return res.status(404).json({ success: false, error: 'Group not found' });
            }

            const newMessage = {
                groupId,
                senderId: req.user.uid,
                senderName: req.user.displayName,
                content: content.trim(),
                type: type || 'text',
                createdAt: admin.firestore.FieldValue.serverTimestamp()
            };

            const docRef = await db.collection('chat_messages').add(newMessage);

            // Update group's updatedAt
            await db.collection('chat_groups').doc(groupId).update({
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                lastMessage: {
                    content: content.substring(0, 50),
                    senderName: req.user.displayName,
                    createdAt: new Date()
                }
            });

            res.json({
                success: true,
                message: { id: docRef.id, ...newMessage }
            });
        } catch (error) {
            console.error('Send message error:', error);
            res.status(500).json({ success: false, error: 'Failed to send message' });
        }
    });

    // Get messages for a group
    router.get('/messages/:groupId', async (req, res) => {
        const { groupId } = req.params;
        const { limit, before } = req.query; // For pagination

        try {
            // Verify group
            const groupDoc = await db.collection('chat_groups').doc(groupId).get();
            if (!groupDoc.exists || groupDoc.data().companyId !== req.user.companyId) {
                return res.status(404).json({ success: false, error: 'Group not found' });
            }

            let query = db.collection('chat_messages')
                .where('groupId', '==', groupId)
                .orderBy('createdAt', 'desc')
                .limit(parseInt(limit) || 50);

            if (before) {
                const beforeDoc = await db.collection('chat_messages').doc(before).get();
                if (beforeDoc.exists) {
                    query = query.startAfter(beforeDoc);
                }
            }

            const snapshot = await query.get();
            const messages = snapshot.docs.map(doc => ({
                id: doc.id,
                ...doc.data(),
                createdAt: doc.data().createdAt?.toDate() || new Date()
            })).reverse(); // Return in chronological order for frontend

            res.json({ success: true, messages });
        } catch (error) {
            console.error('Get messages error:', error);
            res.status(500).json({ success: false, error: 'Failed to fetch messages' });
        }
    });

    return router;
}

module.exports = createChatRoutes;
