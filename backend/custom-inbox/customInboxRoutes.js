const express = require('express');
const admin = require('firebase-admin');

function createCustomInboxRoutes(db) {
    const router = express.Router();
    const collectionName = 'customInboxes';

    // Get all custom inboxes for a company
    router.get('/company/:companyId', async (req, res) => {
        try {
            const { companyId } = req.params;
            const snapshot = await db.collection(collectionName)
                .where('companyId', '==', companyId)
                .get();

            const inboxes = snapshot.docs.map(doc => {
                const data = doc.data();
                return {
                    id: doc.id,
                    ...data,
                    createdAt: data.createdAt?.toDate ? data.createdAt.toDate().toISOString() : data.createdAt,
                    updatedAt: data.updatedAt?.toDate ? data.updatedAt.toDate().toISOString() : data.updatedAt
                };
            });

            // Sort by createdAt
            inboxes.sort((a, b) => {
                const dateA = new Date(a.createdAt || 0);
                const dateB = new Date(b.createdAt || 0);
                return dateA - dateB;
            });

            res.json(inboxes);
        } catch (error) {
            console.error('Error fetching custom inboxes:', error);
            res.status(500).json({ error: error.message });
        }
    });

    // Create a new custom inbox
    router.post('/', async (req, res) => {
        try {
            const {
                name,
                companyId,
                accountIds = [],
                whatsappGroupIds = [],
                slackChannelIds = [],
                accountFilters = {},
                color = 0xFF6366F1
            } = req.body;

            const newInbox = {
                name,
                companyId,
                accountIds,
                whatsappGroupIds,
                slackChannelIds,
                accountFilters,
                color,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            };

            const docRef = await db.collection(collectionName).add(newInbox);
            const now = new Date().toISOString();
            const responseInbox = {
                ...newInbox,
                id: docRef.id,
                createdAt: now,
                updatedAt: now
            };

            res.status(201).json(responseInbox);
        } catch (error) {
            console.error('Error creating custom inbox:', error);
            res.status(500).json({ error: error.message });
        }
    });

    // Update an existing custom inbox
    router.put('/:id', async (req, res) => {
        try {
            const { id } = req.params;
            const updates = req.body;
            delete updates.id; // Prevent updating ID
            delete updates.createdAt; // Prevent updating createdAt

            updates.updatedAt = admin.firestore.FieldValue.serverTimestamp();

            await db.collection(collectionName).doc(id).update(updates);
            res.json({ success: true });
        } catch (error) {
            console.error('Error updating custom inbox:', error);
            res.status(500).json({ error: error.message });
        }
    });

    // Delete a custom inbox
    router.delete('/:id', async (req, res) => {
        try {
            const { id } = req.params;
            const docRef = db.collection(collectionName).doc(id);
            const doc = await docRef.get();

            if (!doc.exists) {
                return res.status(404).json({ error: 'Inbox not found' });
            }

            const companyId = doc.data().companyId;

            // Start a batch to delete the inbox and update references in users/invites
            const batch = db.batch();

            // 1. Remove from users
            const usersSnapshot = await db.collection('users')
                .where('companyId', '==', companyId)
                .where('assignedInboxIds', 'array-contains', id)
                .get();

            usersSnapshot.forEach(userDoc => {
                batch.update(userDoc.ref, {
                    assignedInboxIds: admin.firestore.FieldValue.arrayRemove(id)
                });
            });

            // 2. Remove from pending invites
            const invitesSnapshot = await db.collection('pendingInvites')
                .where('companyId', '==', companyId)
                .where('assignedInboxIds', 'array-contains', id)
                .get();

            invitesSnapshot.forEach(inviteDoc => {
                batch.update(inviteDoc.ref, {
                    assignedInboxIds: admin.firestore.FieldValue.arrayRemove(id)
                });
            });

            // 3. Delete the inbox itself
            batch.delete(docRef);

            await batch.commit();

            res.json({ success: true });
        } catch (error) {
            console.error('Error deleting custom inbox:', error);
            res.status(500).json({ error: error.message });
        }
    });

    return router;
}

module.exports = createCustomInboxRoutes;
