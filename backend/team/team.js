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
const nodemailer = require('nodemailer');

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
        try {
            // Check if SMTP is configured
            if (!process.env.SMTP_USER || !process.env.SMTP_PASS) {
                console.log('[Team] SMTP not configured, skipping email');
                return false;
            }

            const transporter = nodemailer.createTransporter({
                host: process.env.SMTP_HOST,
                port: parseInt(process.env.SMTP_PORT),
                secure: false,
                auth: {
                    user: process.env.SMTP_USER,
                    pass: process.env.SMTP_PASS
                }
            });

            const inviteUrl = getInviteUrl(token);
            const inboxText = inboxCount > 0
                ? `You'll have access to ${inboxCount} shared inbox${inboxCount > 1 ? 'es' : ''}.`
                : 'Inboxes will be assigned to you after you join.';

            await transporter.sendMail({
                from: process.env.SMTP_USER,
                to: to,
                subject: `${inviterName} invited you to join ${companyName}`,
                html: `
                    <h2>You've been invited to join ${companyName}</h2>
                    <p>${inviterName} has invited you to join their team on Shared Mailbox.</p>
                    <p>${inboxText}</p>
                    <p><a href="${inviteUrl}" style="display: inline-block; padding: 12px 24px; background-color: #6366F1; color: white; text-decoration: none; border-radius: 6px;">Accept Invitation</a></p>
                    <p>Or copy this link: ${inviteUrl}</p>
                    <p style="color: #666; font-size: 12px;">This invitation expires in 7 days.</p>
                `
            });

            return true;
        } catch (error) {
            console.error('[Team] Email send error:', error);
            return false;
        }
    }

    return router;
}

module.exports = createTeamRoutes;