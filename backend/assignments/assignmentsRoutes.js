/**
 * Assignments Routes - Task management for teams
 * 
 * Handles:
 * - Creating assignments (Admin only)
 * - Listing assignments (Filtered by company/user)
 * - Updating assignment status (Team members)
 * - Deleting assignments (Admin only)
 */

const express = require('express');
const admin = require('firebase-admin');

function createAssignmentsRoutes(db) {
    const router = express.Router();

    /**
     * POST /
     * Create a new assignment
     * Restricted to Admins (users with same companyId)
     */
    router.post('/', async (req, res) => {
        const {
            title,
            description,
            assignedTo, // userId of team member
            assignedBy, // userId of creator (admin)
            targetDate,
            companyId
        } = req.body;

        if (!title || !assignedTo || !assignedBy || !companyId) {
            return res.status(400).json({
                success: false,
                error: 'Missing required fields: title, assignedTo, assignedBy, companyId'
            });
        }

        try {
            // Validate creator is from same company (simple check, robust auth via middleware recommended in future)
            const creatorDoc = await db.collection('users').doc(assignedBy).get();
            if (!creatorDoc.exists || creatorDoc.data().companyId !== companyId) {
                return res.status(403).json({ success: false, error: 'Unauthorized: Creator not found or company mismatch' });
            }

            // Validate assignee is in same company
            const assigneeDoc = await db.collection('users').doc(assignedTo).get();
            if (!assigneeDoc.exists || assigneeDoc.data().companyId !== companyId) {
                return res.status(400).json({ success: false, error: 'Assignee not found in this company' });
            }

            const assignmentData = {
                title,
                description: description || '',
                assignedTo,
                assignedBy,
                assignedByName: creatorDoc.data().displayName || 'Admin',
                assignedToName: assigneeDoc.data().displayName || 'Member',
                companyId,
                status: 'pending', // pending, in_progress, completed
                targetDate: targetDate ? admin.firestore.Timestamp.fromDate(new Date(targetDate)) : null,
                assignedDate: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            };

            const docRef = await db.collection('assignments').add(assignmentData);

            res.json({
                success: true,
                id: docRef.id,
                message: 'Assignment created successfully'
            });

        } catch (error) {
            console.error('[Assignments] Create error:', error);
            res.status(500).json({ success: false, error: error.message });
        }
    });

    /**
     * GET /
     * List assignments
     * Query params: companyId (required), assignedTo (optional), status (optional)
     */
    router.get('/', async (req, res) => {
        const { companyId, assignedTo, status } = req.query;

        if (!companyId) {
            return res.status(400).json({ error: 'Missing companyId' });
        }

        try {
            let query = db.collection('assignments').where('companyId', '==', companyId);

            if (assignedTo) {
                query = query.where('assignedTo', '==', assignedTo);
            }

            if (status) {
                query = query.where('status', '==', status);
            }

            // Order by date descending (newest first)
            // Note: Firestore requires composite index for multi-field queries with sort
            // For now, sorting in memory if needed or rely on client-side sort

            const snapshot = await query.get();
            const assignments = snapshot.docs.map(doc => ({
                id: doc.id,
                ...doc.data(),
                // Convert Timestamps to ISO strings for JSON
                targetDate: doc.data().targetDate?.toDate().toISOString(),
                assignedDate: doc.data().assignedDate?.toDate().toISOString(),
                updatedAt: doc.data().updatedAt?.toDate().toISOString(),
            }));

            // Manual sort by assignedDate desc
            assignments.sort((a, b) => new Date(b.assignedDate) - new Date(a.assignedDate));

            res.json({ success: true, assignments });

        } catch (error) {
            console.error('[Assignments] List error:', error);
            res.status(500).json({ success: false, error: error.message });
        }
    });

    /**
     * PATCH /:id/status
     * Update assignment status
     */
    router.patch('/:id/status', async (req, res) => {
        const { id } = req.params;
        const { status, updatedBy } = req.body;

        if (!['pending', 'in_progress', 'completed'].includes(status)) {
            return res.status(400).json({ success: false, error: 'Invalid status' });
        }

        try {
            await db.collection('assignments').doc(id).update({
                status,
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            });

            res.json({ success: true, message: 'Status updated' });

        } catch (error) {
            console.error('[Assignments] Update status error:', error);
            res.status(500).json({ success: false, error: error.message });
        }
    });

    /**
     * DELETE /:id
     * Delete assignment
     */
    router.delete('/:id', async (req, res) => {
        const { id } = req.params;
        try {
            await db.collection('assignments').doc(id).delete();
            // TODO: Delete subcollection 'messages' as well (requires manual recursion in Firestore)
            res.json({ success: true, message: 'Assignment deleted' });
        } catch (error) {
            console.error('[Assignments] Delete error:', error);
            res.status(500).json({ success: false, error: error.message });
        }
    });

    return router;
}

module.exports = createAssignmentsRoutes;
