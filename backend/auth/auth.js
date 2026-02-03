/**
 * Authentication Routes
 * 
 * Handles:
 * - User signup (with company creation or invite acceptance)
 * - User login
 * - Password management
 * - Team invitations
 * 
 * Security:
 * - Firebase Auth for password management
 * - Firestore for user profiles
 * - Backend-only company creation
 */

const express = require('express');
const admin = require('firebase-admin');
const encryptionService = require('../core/services/encryption-service');

function createAuthRoutes(db) {
    const router = express.Router();

    /**
     * POST /signup
     * Create new user account
     * - If invite exists: Join as team member
     * - If no invite: Create new company as owner
     */
    router.post('/signup', async (req, res) => {
        const { email, password, displayName, companyName } = req.body;

        if (!email || !password) {
            return res.status(400).json({
                success: false,
                error: 'Email and password are required'
            });
        }

        try {
            // Check for pending invite
            const pendingInviteQuery = await db.collection('pendingInvites')
                .where('email', '==', email.toLowerCase())
                .limit(1)
                .get();

            // Create Firebase Auth user
            let userRecord;
            try {
                userRecord = await admin.auth().createUser({
                    email: email.toLowerCase(),
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

            if (!pendingInviteQuery.empty) {
                // Join existing company as team member
                const invite = pendingInviteQuery.docs[0];
                const inviteData = invite.data();

                companyId = inviteData.companyId;
                role = 'member';
                assignedInboxIds = inviteData.assignedInboxIds || [];

                // Delete the pending invite
                await invite.ref.delete();

                console.log(`[Auth] User ${email} joined company ${companyId} via invite`);
            } else {
                // Create new company
                if (!companyName) {
                    // Rollback user creation
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

            // Create user profile in Firestore
            await db.collection('users').doc(userRecord.uid).set({
                email: email.toLowerCase(),
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

            // Generate custom token for immediate sign-in
            const customToken = await admin.auth().createCustomToken(userRecord.uid);

            res.json({
                success: true,
                customToken: customToken,
                userId: userRecord.uid,
                companyId: companyId,
                role: role,
                message: role === 'owner'
                    ? 'Account created successfully!'
                    : 'Welcome to the team!'
            });

        } catch (error) {
            console.error('[Auth] Signup error:', error);
            res.status(500).json({
                success: false,
                error: error.message || 'Failed to create account'
            });
        }
    });

    /**
     * POST /login
     * Login existing user (verification only - actual auth handled by Firebase)
     * This endpoint is optional - Firebase can handle login directly
     */
    router.post('/login', async (req, res) => {
        const { email, password } = req.body;

        if (!email || !password) {
            return res.status(400).json({
                success: false,
                error: 'Email and password are required'
            });
        }

        try {
            // Verify user exists and is active
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

            // Update last login timestamp
            await db.collection('users').doc(userRecord.uid).update({
                lastLoginAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            });

            // Generate custom token
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

    /**
     * POST /update-profile
     * Update user profile information
     */
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

    /**
     * GET /user/:userId
     * Get user profile
     */
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
                    lastLoginAt: userData.lastLoginAt
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