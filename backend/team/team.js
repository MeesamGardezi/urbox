/**
 * Team Management Routes
 * 
 * Handles:
 * - Sending team invitations
 * - Checking for pending invitations
 * - Accepting invitations
 * - Managing team members
 * - Updating member permissions
 */

const express = require('express');
const admin = require('firebase-admin');
const emailService = require('../core/services/email-service');

function createTeamRoutes(db) {
    const router = express.Router();

    /**
     * POST /invite
     * Send invitation to join team
     */
    router.post('/invite', async (req, res) => {
        const { email, companyId, invitedBy, assignedInboxIds = [] } = req.body;

        if (!email || !companyId || !invitedBy) {
            return res.status(400).json({
                success: false,
                error: 'Missing required fields: email, companyId, invitedBy'
            });
        }

        try {
            // Validate inviter is from the same company
            const inviterDoc = await db.collection('users').doc(invitedBy).get();

            if (!inviterDoc.exists) {
                return res.status(404).json({
                    success: false,
                    error: 'Inviter not found'
                });
            }

            const inviterData = inviterDoc.data();

            if (inviterData.companyId !== companyId) {
                return res.status(403).json({
                    success: false,
                    error: 'Unauthorized: Company mismatch'
                });
            }

            // Check if user already exists
            const existingUsers = await db.collection('users')
                .where('email', '==', email.toLowerCase())
                .get();

            if (!existingUsers.empty) {
                return res.status(400).json({
                    success: false,
                    error: 'A user with this email already exists'
                });
            }

            // Check for existing pending invite
            const existingInvites = await db.collection('pendingInvites')
                .where('email', '==', email.toLowerCase())
                .where('companyId', '==', companyId)
                .get();

            // Generate invite token
            const inviteToken = generateInviteToken();
            const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000); // 7 days

            // Get company info
            const companyDoc = await db.collection('companies').doc(companyId).get();
            const companyName = companyDoc.exists ? companyDoc.data().name : 'the team';

            const inviteData = {
                email: email.toLowerCase(),
                companyId: companyId,
                companyName: companyName,
                role: 'member',
                assignedInboxIds: assignedInboxIds,
                status: 'pending',
                invitedBy: invitedBy,
                inviterName: inviterData.displayName || inviterData.email,
                inviteToken: inviteToken,
                expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            };

            let inviteId;

            if (!existingInvites.empty) {
                // Update existing invite
                inviteId = existingInvites.docs[0].id;
                await existingInvites.docs[0].ref.update({
                    ...inviteData,
                    updatedAt: admin.firestore.FieldValue.serverTimestamp()
                });
            } else {
                // Create new invite
                const docRef = await db.collection('pendingInvites').add(inviteData);
                inviteId = docRef.id;
            }

            // Send invitation email
            const emailSent = await sendInvitationEmail({
                to: email,
                inviterName: inviterData.displayName || inviterData.email,
                companyName: companyName,
                token: inviteToken,
                inboxCount: assignedInboxIds.length
            });

            console.log(`[Team] Invitation sent to ${email} for company ${companyId}`);

            res.json({
                success: true,
                inviteToken: inviteToken,
                emailSent: emailSent,
                message: emailSent
                    ? `Invitation sent to ${email}`
                    : `Invite created. Share this link: ${getInviteUrl(inviteToken)}`
            });

        } catch (error) {
            console.error('[Team] Invite error:', error);
            res.status(500).json({
                success: false,
                error: error.message || 'Failed to send invitation'
            });
        }
    });

    /**
     * POST /check-invite
     * Check if an email has a pending invitation
     * Uses simpler query to avoid Firestore index requirements
     */
    router.post('/check-invite', async (req, res) => {
        const { email } = req.body;

        if (!email) {
            return res.json({
                hasPendingInvite: false,
                error: 'Email is required'
            });
        }

        try {
            // Get all pending invites for this email
            const inviteQuery = await db.collection('pendingInvites')
                .where('email', '==', email.toLowerCase())
                .get();

            if (inviteQuery.empty) {
                return res.json({
                    hasPendingInvite: false
                });
            }

            // Filter in code for status and expiration
            let validInvite = null;
            const now = new Date();

            for (const doc of inviteQuery.docs) {
                const invite = doc.data();

                // Check status
                if (invite.status !== 'pending') continue;

                // Check expiration
                const expiresAt = invite.expiresAt?.toDate ?
                    invite.expiresAt.toDate() :
                    new Date(invite.expiresAt);

                if (expiresAt < now) continue;

                // Found valid invite
                validInvite = invite;
                break;
            }

            if (!validInvite) {
                return res.json({
                    hasPendingInvite: false
                });
            }

            res.json({
                hasPendingInvite: true,
                companyName: validInvite.companyName || 'Your Team',
                inviterName: validInvite.inviterName || 'Team Owner',
                token: validInvite.inviteToken
            });

        } catch (error) {
            console.error('[Team] Check invite error:', error);
            // Return false instead of error to not disrupt signup flow
            res.json({
                hasPendingInvite: false
            });
        }
    });

    /**
     * GET /invite/:token
     * Get invitation details
     */
    router.get('/invite/:token', async (req, res) => {
        const { token } = req.params;

        try {
            const inviteQuery = await db.collection('pendingInvites')
                .where('inviteToken', '==', token)
                .limit(1)
                .get();

            if (inviteQuery.empty) {
                return res.status(404).json({
                    success: false,
                    error: 'Invitation not found or has been used'
                });
            }

            const invite = inviteQuery.docs[0].data();

            // Check if expired
            const expiresAt = invite.expiresAt.toDate ? invite.expiresAt.toDate() : new Date(invite.expiresAt);
            if (expiresAt < new Date()) {
                return res.status(410).json({
                    success: false,
                    error: 'This invitation has expired. Please request a new invitation.'
                });
            }

            res.json({
                email: invite.email,
                companyName: invite.companyName,
                inviterName: invite.inviterName,
                assignedInboxIds: invite.assignedInboxIds || [],
                expiresAt: expiresAt.toISOString()
            });

        } catch (error) {
            console.error('[Team] Get invite error:', error);
            res.status(500).json({
                success: false,
                error: 'Failed to load invitation'
            });
        }
    });

    /**
     * POST /accept-invite
     * Accept invitation and create account
     */
    router.post('/accept-invite', async (req, res) => {
        const { token, password, displayName } = req.body;

        if (!token || !password) {
            return res.status(400).json({
                success: false,
                error: 'Token and password are required'
            });
        }

        try {
            // Find invite
            const inviteQuery = await db.collection('pendingInvites')
                .where('inviteToken', '==', token)
                .limit(1)
                .get();

            if (inviteQuery.empty) {
                return res.status(404).json({
                    success: false,
                    error: 'Invitation not found'
                });
            }

            const inviteDoc = inviteQuery.docs[0];
            const invite = inviteDoc.data();

            // Check if expired
            const expiresAt = invite.expiresAt.toDate ? invite.expiresAt.toDate() : new Date(invite.expiresAt);
            if (expiresAt < new Date()) {
                return res.status(410).json({
                    success: false,
                    error: 'This invitation has expired. Please request a new invitation.'
                });
            }

            // Create Firebase Auth user
            let userRecord;
            try {
                userRecord = await admin.auth().createUser({
                    email: invite.email,
                    password: password,
                    displayName: displayName?.trim() || invite.email.split('@')[0]
                });
            } catch (authError) {
                if (authError.code === 'auth/email-already-exists') {
                    userRecord = await admin.auth().getUserByEmail(invite.email);
                    await admin.auth().updateUser(userRecord.uid, { password });
                } else {
                    throw authError;
                }
            }

            // Create user document
            await db.collection('users').doc(userRecord.uid).set({
                email: invite.email,
                displayName: displayName?.trim() || invite.email.split('@')[0],
                companyId: invite.companyId,
                role: 'member',
                assignedInboxIds: invite.assignedInboxIds || [],
                status: 'active',
                invitedBy: invite.invitedBy,
                mfaEnabled: false,
                emailNotifications: true,
                pushNotifications: true,
                preferences: {},
                activeSessions: [],
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            });

            // Delete the pending invite
            await inviteDoc.ref.delete();

            // Generate custom token for immediate sign-in
            const customToken = await admin.auth().createCustomToken(userRecord.uid);

            console.log(`[Team] User ${invite.email} joined company ${invite.companyId}`);

            res.json({
                success: true,
                customToken: customToken,
                userId: userRecord.uid,
                message: `Welcome to ${invite.companyName}!`
            });

        } catch (error) {
            console.error('[Team] Accept invite error:', error);
            res.status(500).json({
                success: false,
                error: error.message || 'Failed to create account'
            });
        }
    });

    /**
     * POST /update-member-inboxes
     * Update assigned inboxes for a team member
     */
    router.post('/update-member-inboxes', async (req, res) => {
        const { memberId, inboxIds } = req.body;

        if (!memberId || !Array.isArray(inboxIds)) {
            return res.status(400).json({
                success: false,
                error: 'Missing memberId or inboxIds array'
            });
        }

        try {
            await db.collection('users').doc(memberId).update({
                assignedInboxIds: inboxIds,
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            });

            res.json({
                success: true,
                message: 'Inbox assignments updated'
            });

        } catch (error) {
            console.error('[Team] Update inboxes error:', error);
            res.status(500).json({
                success: false,
                error: error.message
            });
        }
    });

    /**
     * GET /members/:companyId
     * Get all team members for a company
     */
    router.get('/members/:companyId', async (req, res) => {
        const { companyId } = req.params;

        if (!companyId) {
            return res.status(400).json({
                success: false,
                error: 'Missing companyId'
            });
        }

        try {
            const usersSnapshot = await db.collection('users')
                .where('companyId', '==', companyId)
                .get();

            const members = usersSnapshot.docs.map(doc => ({
                id: doc.id,
                ...doc.data(),
                createdAt: doc.data().createdAt?.toDate?.()?.toISOString() || null,
                updatedAt: doc.data().updatedAt?.toDate?.()?.toISOString() || null
            }));

            // Sort by role (owner first) then by email
            members.sort((a, b) => {
                if (a.role === 'owner' && b.role !== 'owner') return -1;
                if (a.role !== 'owner' && b.role === 'owner') return 1;
                return a.email.localeCompare(b.email);
            });

            res.json({
                success: true,
                members: members
            });

        } catch (error) {
            console.error('[Team] Get members error:', error);
            res.status(500).json({
                success: false,
                error: error.message
            });
        }
    });

    /**
     * GET /pending-invites/:companyId
     * Get all pending invitations for a company
     */
    router.get('/pending-invites/:companyId', async (req, res) => {
        const { companyId } = req.params;

        if (!companyId) {
            return res.status(400).json({
                success: false,
                error: 'Missing companyId'
            });
        }

        try {
            const invitesSnapshot = await db.collection('pendingInvites')
                .where('companyId', '==', companyId)
                .get();

            const invites = invitesSnapshot.docs.map(doc => ({
                id: doc.id,
                ...doc.data(),
                expiresAt: doc.data().expiresAt?.toDate?.()?.toISOString() || null,
                createdAt: doc.data().createdAt?.toDate?.()?.toISOString() || null,
                updatedAt: doc.data().updatedAt?.toDate?.()?.toISOString() || null
            }));

            res.json({
                success: true,
                invites: invites
            });

        } catch (error) {
            console.error('[Team] Get pending invites error:', error);
            res.status(500).json({
                success: false,
                error: error.message
            });
        }
    });

    /**
     * GET /invite-token/:inviteId
     * Get invite token for a pending invitation (for copy link functionality)
     */
    router.get('/invite-token/:inviteId', async (req, res) => {
        const { inviteId } = req.params;

        if (!inviteId) {
            return res.status(400).json({
                success: false,
                error: 'Missing inviteId'
            });
        }

        try {
            const inviteDoc = await db.collection('pendingInvites').doc(inviteId).get();

            if (!inviteDoc.exists) {
                return res.status(404).json({
                    success: false,
                    error: 'Invite not found'
                });
            }

            const inviteData = inviteDoc.data();

            res.json({
                success: true,
                token: inviteData.inviteToken,
                inviteLink: getInviteUrl(inviteData.inviteToken)
            });

        } catch (error) {
            console.error('[Team] Get invite token error:', error);
            res.status(500).json({
                success: false,
                error: error.message
            });
        }
    });

    /**
     * DELETE /cancel-invite/:inviteId
     * Cancel a pending invitation
     */
    router.delete('/cancel-invite/:inviteId', async (req, res) => {
        const { inviteId } = req.params;

        if (!inviteId) {
            return res.status(400).json({
                success: false,
                error: 'Missing inviteId'
            });
        }

        try {
            await db.collection('pendingInvites').doc(inviteId).delete();

            res.json({
                success: true,
                message: 'Invitation cancelled'
            });

        } catch (error) {
            console.error('[Team] Cancel invite error:', error);
            res.status(500).json({
                success: false,
                error: error.message
            });
        }
    });

    /**
     * POST /resend-invite
     * Resend invitation email for a pending invite
     */
    router.post('/resend-invite', async (req, res) => {
        const { inviteId } = req.body;

        if (!inviteId) {
            return res.status(400).json({ success: false, error: 'Missing inviteId' });
        }

        try {
            const inviteDoc = await db.collection('pendingInvites').doc(inviteId).get();

            if (!inviteDoc.exists) {
                return res.status(404).json({ success: false, error: 'Invite not found' });
            }

            const invite = inviteDoc.data();

            // Generate new token and extend expiry
            const newToken = generateInviteToken();
            const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);

            await inviteDoc.ref.update({
                inviteToken: newToken,
                expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            });

            // Send email
            const emailSent = await sendInvitationEmail({
                to: invite.email,
                inviterName: invite.inviterName,
                companyName: invite.companyName,
                token: newToken,
                inboxCount: invite.assignedInboxIds?.length || 0
            });

            res.json({
                success: true,
                emailSent,
                message: emailSent
                    ? `Invitation resent to ${invite.email}`
                    : `New invite link generated. Share: ${getInviteUrl(newToken)}`
            });

        } catch (error) {
            console.error('[Team] Resend invite error:', error);
            res.status(500).json({ success: false, error: error.message });
        }
    });

    /**
     * POST /remove-member
     * Remove a team member from the company
     */
    router.post('/remove-member', async (req, res) => {
        const { memberId } = req.body;

        if (!memberId) {
            return res.status(400).json({
                success: false,
                error: 'Missing memberId'
            });
        }

        try {
            const memberDoc = await db.collection('users').doc(memberId).get();

            if (!memberDoc.exists) {
                return res.status(404).json({
                    success: false,
                    error: 'Member not found'
                });
            }

            const memberData = memberDoc.data();

            // Prevent removing owners
            if (memberData.role === 'owner') {
                return res.status(403).json({
                    success: false,
                    error: 'Cannot remove company owner'
                });
            }

            // Get company name for email
            let companyName = 'your team';
            try {
                const companyDoc = await db.collection('companies').doc(memberData.companyId).get();
                if (companyDoc.exists) {
                    companyName = companyDoc.data().name;
                }
            } catch (e) {
                console.log('[Team] Failed to fetch company name for email', e);
            }

            // Send notification email
            try {
                await emailService.sendMemberRemovedNotification({
                    to: memberData.email,
                    companyName: companyName
                });
            } catch (e) {
                console.log('[Team] Failed to send removal email:', e);
            }

            // Delete the member
            await memberDoc.ref.delete();

            console.log(`[Team] Member ${memberData.email} removed from company ${memberData.companyId}`);

            res.json({
                success: true,
                message: `Member ${memberData.email} has been removed`
            });

        } catch (error) {
            console.error('[Team] Remove member error:', error);
            res.status(500).json({
                success: false,
                error: error.message
            });
        }
    });

    /**
     * POST /disable-member
     * Disable a team member's access
     */
    router.post('/disable-member', async (req, res) => {
        const { memberId } = req.body;

        if (!memberId) {
            return res.status(400).json({
                success: false,
                error: 'Missing memberId'
            });
        }

        try {
            const memberDoc = await db.collection('users').doc(memberId).get();

            if (!memberDoc.exists) {
                return res.status(404).json({
                    success: false,
                    error: 'Member not found'
                });
            }

            const memberData = memberDoc.data();

            // Prevent disabling owners
            if (memberData.role === 'owner') {
                return res.status(403).json({
                    success: false,
                    error: 'Cannot disable company owner'
                });
            }

            await memberDoc.ref.update({
                status: 'disabled',
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            });

            console.log(`[Team] Member ${memberData.email} disabled`);

            res.json({
                success: true,
                message: `Member ${memberData.email} has been disabled`
            });

        } catch (error) {
            console.error('[Team] Disable member error:', error);
            res.status(500).json({
                success: false,
                error: error.message
            });
        }
    });

    /**
     * POST /enable-member
     * Re-enable a team member's access
     */
    router.post('/enable-member', async (req, res) => {
        const { memberId } = req.body;

        if (!memberId) {
            return res.status(400).json({
                success: false,
                error: 'Missing memberId'
            });
        }

        try {
            await db.collection('users').doc(memberId).update({
                status: 'active',
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            });

            res.json({
                success: true,
                message: 'Member has been enabled'
            });

        } catch (error) {
            console.error('[Team] Enable member error:', error);
            res.status(500).json({
                success: false,
                error: error.message
            });
        }
    });

    // Helper functions

    function generateInviteToken() {
        const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
        const segments = [];
        for (let s = 0; s < 3; s++) {
            let segment = '';
            for (let i = 0; i < 6; i++) {
                segment += chars.charAt(Math.floor(Math.random() * chars.length));
            }
            segments.push(segment);
        }
        return segments.join('-');
    }

    function getInviteUrl(token) {
        const baseUrl = process.env.APP_URL || 'http://localhost:8080';
        return `${baseUrl}/auth?invite=${token}`;
    }

    async function sendInvitationEmail({ to, inviterName, companyName, token, inboxCount }) {
        return emailService.sendTeamInvitation({
            to,
            inviterName,
            companyName,
            inviteLink: getInviteUrl(token),
            inboxCount
        });
    }

    return router;
}

module.exports = createTeamRoutes;