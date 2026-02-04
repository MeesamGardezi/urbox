/**
 * Authentication Routes - NO INDEX VERSION
 * 
 * Completely removed all compound queries
 * Everything filtered in code
 */

const express = require('express');
const admin = require('firebase-admin');

function createAuthRoutes(db) {
    const router = express.Router();

    router.post('/signup', async (req, res) => {
        const { email, password, displayName, companyName } = req.body;

        if (!email || !password) {
            return res.status(400).json({
                success: false,
                error: 'Email and password are required'
            });
        }

        try {
            let validInvite = null;
            const now = new Date();
            const normalizedEmail = email.toLowerCase();

            // Check for pending invites - handle missing collection gracefully
            try {
                const allInvites = await db.collection('pendingInvites').get();

                for (const doc of allInvites.docs) {
                    const inviteData = doc.data();

                    if (inviteData.email !== normalizedEmail) continue;
                    if (inviteData.status !== 'pending') continue;

                    const expiresAt = inviteData.expiresAt?.toDate ?
                        inviteData.expiresAt.toDate() :
                        new Date(inviteData.expiresAt);

                    if (expiresAt <= now) continue;

                    validInvite = { doc, data: inviteData };
                    break;
                }
            } catch (inviteError) {
                console.log('[Auth] Pending invites check skipped:', inviteError.message);
                // Continue without invite - user will create new company
            }

            // Create Firebase Auth user
            let userRecord;
            try {
                userRecord = await admin.auth().createUser({
                    email: normalizedEmail,
                    password: password,
                    displayName: displayName || email.split('@')[0]
                });
            } catch (authError) {
                if (authError.code === 'auth/email-already-exists') {
                    return res.status(400).json({
                        success: false,
                        error: 'An account with this email already exists'
                    });
                }
                throw authError;
            }

            let companyId;
            let role;
            let assignedInboxIds = [];

            if (validInvite) {
                // Join existing company
                companyId = validInvite.data.companyId;
                role = 'member';
                assignedInboxIds = validInvite.data.assignedInboxIds || [];

                try {
                    await validInvite.doc.ref.delete();
                } catch (deleteError) {
                    console.log('[Auth] Failed to delete invite:', deleteError.message);
                }

                console.log(`[Auth] User ${email} joined company ${companyId} via invite`);
            } else {
                // Create new company
                if (!companyName) {
                    await admin.auth().deleteUser(userRecord.uid);
                    return res.status(400).json({
                        success: false,
                        error: 'Company name is required for new signups'
                    });
                }

                const companyRef = await db.collection('companies').add({
                    name: companyName.trim(),
                    ownerId: userRecord.uid,
                    plan: 'free',
                    isFree: true,
                    isProFree: false,
                    subscriptionStatus: 'none',
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                    updatedAt: admin.firestore.FieldValue.serverTimestamp()
                });

                companyId = companyRef.id;
                role = 'owner';

                console.log(`[Auth] Created new company: ${companyId} for user ${email}`);
            }

            // Create user profile
            await db.collection('users').doc(userRecord.uid).set({
                email: normalizedEmail,
                displayName: displayName?.trim() || email.split('@')[0],
                companyId: companyId,
                role: role,
                assignedInboxIds: assignedInboxIds,
                status: 'active',
                mfaEnabled: false,
                emailNotifications: true,
                pushNotifications: true,
                preferences: {},
                activeSessions: [],
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            });

            // Generate custom token
            const customToken = await admin.auth().createCustomToken(userRecord.uid);

            res.json({
                success: true,
                customToken: customToken,
                userId: userRecord.uid,
                companyId: companyId,
                role: role,
                message: role === 'owner' ? 'Account created successfully!' : 'Welcome to the team!'
            });

        } catch (error) {
            console.error('[Auth] Signup error:', error);
            console.error('[Auth] Error stack:', error.stack);
            res.status(500).json({
                success: false,
                error: error.message || 'Failed to create account'
            });
        }
    });

    router.post('/login', async (req, res) => {
        const { email, password } = req.body;

        if (!email || !password) {
            return res.status(400).json({
                success: false,
                error: 'Email and password are required'
            });
        }

        try {
            const userRecord = await admin.auth().getUserByEmail(email.toLowerCase());
            const userDoc = await db.collection('users').doc(userRecord.uid).get();

            if (!userDoc.exists) {
                return res.status(404).json({
                    success: false,
                    error: 'User profile not found'
                });
            }

            const userData = userDoc.data();

            if (userData.status !== 'active') {
                return res.status(403).json({
                    success: false,
                    error: 'Account is suspended. Contact support.'
                });
            }

            await db.collection('users').doc(userRecord.uid).update({
                lastLoginAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            });

            const customToken = await admin.auth().createCustomToken(userRecord.uid);

            res.json({
                success: true,
                customToken: customToken,
                userId: userRecord.uid,
                companyId: userData.companyId,
                role: userData.role
            });

        } catch (error) {
            console.error('[Auth] Login error:', error);
            if (error.code === 'auth/user-not-found') {
                return res.status(404).json({
                    success: false,
                    error: 'No account found with this email'
                });
            }
            res.status(500).json({
                success: false,
                error: 'Login failed'
            });
        }
    });

    router.post('/update-profile', async (req, res) => {
        const { userId, displayName, phoneNumber, timezone, language } = req.body;

        if (!userId) {
            return res.status(400).json({
                success: false,
                error: 'User ID is required'
            });
        }

        try {
            const updateData = {
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            };

            if (displayName) updateData.displayName = displayName.trim();
            if (phoneNumber) updateData.phoneNumber = phoneNumber.trim();
            if (timezone) updateData.timezone = timezone;
            if (language) updateData.language = language;

            await db.collection('users').doc(userId).update(updateData);

            res.json({
                success: true,
                message: 'Profile updated successfully'
            });

        } catch (error) {
            console.error('[Auth] Update profile error:', error);
            res.status(500).json({
                success: false,
                error: 'Failed to update profile'
            });
        }
    });

    router.post('/update-preferences', async (req, res) => {
        const { userId, preferences, emailNotifications, pushNotifications } = req.body;

        if (!userId) {
            return res.status(400).json({
                success: false,
                error: 'User ID is required'
            });
        }

        try {
            const updateData = {
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            };

            if (preferences) updateData.preferences = preferences;
            if (typeof emailNotifications === 'boolean') updateData.emailNotifications = emailNotifications;
            if (typeof pushNotifications === 'boolean') updateData.pushNotifications = pushNotifications;

            await db.collection('users').doc(userId).update(updateData);

            res.json({
                success: true,
                message: 'Preferences updated'
            });

        } catch (error) {
            console.error('[Auth] Update preferences error:', error);
            res.status(500).json({
                success: false,
                error: 'Failed to update preferences'
            });
        }
    });

    router.post('/delete-account', async (req, res) => {
        const { userId } = req.body;

        if (!userId) {
            return res.status(400).json({
                success: false,
                error: 'User ID is required'
            });
        }

        try {
            // Delete from Authentication
            await admin.auth().deleteUser(userId);

            // Delete from Firestore
            await db.collection('users').doc(userId).delete();

            // Note: We are keeping the company even if the owner deletes their account
            // to prevent data loss for other members. A better approach might be
            // to transfer ownership or archive the company.

            res.json({
                success: true,
                message: 'Account deleted successfully'
            });

        } catch (error) {
            console.error('[Auth] Delete account error:', error);
            res.status(500).json({
                success: false,
                error: 'Failed to delete account'
            });
        }
    });

    router.post('/change-password', async (req, res) => {
        const { userId, newPassword } = req.body;

        if (!userId || !newPassword) {
            return res.status(400).json({
                success: false,
                error: 'User ID and new password are required'
            });
        }

        if (newPassword.length < 6) {
            return res.status(400).json({
                success: false,
                error: 'Password must be at least 6 characters'
            });
        }

        try {
            await admin.auth().updateUser(userId, {
                password: newPassword
            });

            res.json({
                success: true,
                message: 'Password updated successfully'
            });

        } catch (error) {
            console.error('[Auth] Change password error:', error);
            res.status(500).json({
                success: false,
                error: error.message || 'Failed to update password'
            });
        }
    });

    router.get('/test', async (req, res) => {
        try {
            const allDocs = await db.collection('pendingInvites').get();
            res.json({
                success: true,
                count: allDocs.size,
                docs: allDocs.docs.map(d => d.id)
            });
        } catch (error) {
            res.json({
                success: false,
                error: error.message,
                code: error.code
            });
        }
    });

    router.get('/user/:userId', async (req, res) => {
        const { userId } = req.params;

        try {
            const doc = await db.collection('users').doc(userId).get();

            if (!doc.exists) {
                return res.status(404).json({
                    success: false,
                    error: 'User not found'
                });
            }

            const userData = doc.data();

            res.json({
                success: true,
                user: {
                    id: doc.id,
                    email: userData.email,
                    displayName: userData.displayName,
                    companyId: userData.companyId,
                    role: userData.role,
                    status: userData.status,
                    assignedInboxIds: userData.assignedInboxIds || [],
                    mfaEnabled: userData.mfaEnabled || false,
                    phoneNumber: userData.phoneNumber,
                    timezone: userData.timezone,
                    language: userData.language,
                    createdAt: userData.createdAt,
                    lastLoginAt: userData.lastLoginAt,
                    emailNotifications: userData.emailNotifications,
                    pushNotifications: userData.pushNotifications,
                    preferences: userData.preferences
                }
            });

        } catch (error) {
            console.error('[Auth] Get user error:', error);
            res.status(500).json({
                success: false,
                error: 'Failed to get user profile'
            });
        }
    });

    return router;
}

module.exports = createAuthRoutes;