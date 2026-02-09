/**
 * URBox Backend Server
 * 
 * Handles:
 * - Express server setup
 * - Firebase Admin initialization
 * - WhatsApp Session Management
 * - Route registration
 * - Middleware configuration
 * 
 * Version: 1.0.0
 */

require('dotenv').config();
const express = require('express');
const cors = require('cors');
const admin = require('firebase-admin');

// Validate required environment variables
const requiredEnvVars = [
    'ENCRYPTION_KEY',
    'ADMIN_SECRET',
    'STRIPE_SECRET_KEY',
    'STRIPE_PRICE_ID'
];

const missingEnvVars = requiredEnvVars.filter(varName => !process.env[varName]);

if (missingEnvVars.length > 0) {
    console.error('❌ Missing required environment variables:');
    missingEnvVars.forEach(varName => console.error(`   - ${varName}`));
    console.error('\n💡 Run: npm run keys');
    console.error('   Then add the keys to your .env file\n');
    process.exit(1);
}

// ============================================================================
// FIREBASE INITIALIZATION
// ============================================================================

let db;

if (!admin.apps.length) {
    try {
        const serviceAccount = require('./firebase-service-account.json');

        console.log(`\n🔧 Firebase Configuration:`);
        console.log(`   Project ID: ${serviceAccount.project_id}`);
        console.log(`   Client Email: ${serviceAccount.client_email}`);

        admin.initializeApp({
            credential: admin.credential.cert(serviceAccount),
            projectId: serviceAccount.project_id,
        });

        console.log('✓ Firebase Admin initialized');
    } catch (error) {
        console.error('❌ Failed to initialize Firebase Admin:', error.message);
        console.error('   Make sure firebase-service-account.json exists');
        process.exit(1);
    }
}

// Initialize Firestore with explicit settings
db = admin.firestore();

// Set Firestore settings to avoid gRPC issues
db.settings({
    ignoreUndefinedProperties: true,
    databaseId: 'urbox-database'
});

// ============================================================================
// FIRESTORE CONNECTION VERIFICATION
// ============================================================================

async function verifyFirestoreConnection() {
    try {
        console.log('Verifying Firestore connection...');
        // Just try to list collections - simple check that works
        await db.listCollections();
        console.log('✓ Firestore connection verified\n');
        return true;
    } catch (error) {
        console.error('\n❌ FIRESTORE CONNECTION FAILED');
        console.error('   Error code:', error.code);
        console.error('   Error message:', error.message);
        return false;
    }
}

// ============================================================================
// WHATSAPP SESSION MANAGER INITIALIZATION
// ============================================================================

const WhatsAppSessionManager = require('./whatsapp/session-manager');
const whatsappSessionManager = new WhatsAppSessionManager(db);

// Restore active sessions on startup
whatsappSessionManager.restoreSessions();

// Graceful cleanup on shutdown
process.on('SIGTERM', async () => {
    console.log('\n⚠️  SIGTERM received, cleaning up WhatsApp sessions...');
    await whatsappSessionManager.cleanup();
    process.exit(0);
});

process.on('SIGINT', async () => {
    console.log('\n⚠️  SIGINT received, cleaning up WhatsApp sessions...');
    await whatsappSessionManager.cleanup();
    process.exit(0);
});

// ============================================================================
// IMPORT ROUTES
// ============================================================================

const createAuthRoutes = require('./auth/auth');
const createTeamRoutes = require('./team/team');
const createSubscriptionRoutes = require('./core/subscription');
const createPaymentRoutes = require('./payment/payments');
const createWhatsAppRoutes = require('./whatsapp/whatsapp');
const createStorageRoutes = require('./storage/storage');
const createEmailRoutes = require('./email/emailRoutes');
const createSlackRoutes = require('./slack/slackRoutes');
const createCustomInboxRoutes = require('./custom-inbox/customInboxRoutes');
const { StorageService } = require('./storage/storage-service');

// Initialize Storage Service
const storageService = new StorageService();

// ============================================================================
// EXPRESS APP SETUP
// ============================================================================

const app = express();
const PORT = process.env.PORT || 3004;

// Middleware
app.use(cors());

// Special handling for Stripe webhook - needs raw body
app.use((req, res, next) => {
    if (req.originalUrl === '/api/payment/webhook') {
        next();
    } else {
        express.json({ limit: '10mb' })(req, res, next);
    }
});

app.use(express.urlencoded({ extended: true }));

// ============================================================================
// HEALTH CHECK
// ============================================================================

app.get('/health', async (req, res) => {
    let firestoreStatus = 'unknown';
    let whatsappStatus = 'unknown';

    try {
        await db.collection('_health').doc('check').get();
        firestoreStatus = 'connected';
    } catch (error) {
        firestoreStatus = `error: ${error.code || error.message}`;
    }

    // Check active WhatsApp sessions
    const activeSessions = whatsappSessionManager.activeSessions.size;
    whatsappStatus = `${activeSessions} active session${activeSessions !== 1 ? 's' : ''}`;

    res.json({
        status: 'healthy',
        timestamp: new Date().toISOString(),
        version: '1.0.0',
        environment: process.env.NODE_ENV || 'development',
        firestore: firestoreStatus,
        whatsapp: whatsappStatus
    });
});

// ============================================================================
// REGISTER ROUTES
// ============================================================================

app.use('/api/auth', createAuthRoutes(db));
app.use('/api/team', createTeamRoutes(db));
app.use('/api/subscription', createSubscriptionRoutes(db));
app.use('/api/payment', createPaymentRoutes(db));
app.use('/api/whatsapp', createWhatsAppRoutes(db, whatsappSessionManager));
app.use('/api/storage', createStorageRoutes(storageService, db));
app.use('/api/email', createEmailRoutes(db));
app.use('/api/slack', createSlackRoutes(db));
app.use('/api/custom-inbox', createCustomInboxRoutes(db));

// ============================================================================
// ERROR HANDLERS
// ============================================================================

// 404 handler
app.use((req, res) => {
    res.status(404).json({
        success: false,
        error: 'Endpoint not found',
        path: req.path
    });
});

// Error handler
app.use((err, req, res, next) => {
    console.error('❌ Server error:', err);
    res.status(500).json({
        success: false,
        error: 'Internal server error',
        message: process.env.NODE_ENV === 'development' ? err.message : undefined
    });
});

// ============================================================================
// START SERVER
// ============================================================================

async function startServer() {
    // Verify Firestore connection before starting
    const firestoreOk = await verifyFirestoreConnection();

    if (!firestoreOk) {
        console.error('\n❌ Server startup aborted due to Firestore connection failure.');
        console.error('   Please fix the Firestore configuration and try again.\n');
        process.exit(1);
    }

    app.listen(PORT, () => {
        console.log('\n==========================================================');
        console.log('              URBOX BACKEND');
        console.log('==========================================================');
        console.log(`✓ Server running on port ${PORT}`);
        console.log(`✓ Environment: ${process.env.NODE_ENV || 'development'}`);
        console.log(`✓ App URL: ${process.env.APP_URL || 'http://localhost:8080'}`);
        console.log(`✓ Firestore: Connected`);
        console.log(`✓ WhatsApp: Session Manager Active`);
        console.log('\n📡 Available endpoints:');
        console.log('   GET  /health');
        console.log('   POST /api/auth/signup');
        console.log('   POST /api/auth/login');
        console.log('   POST /api/team/invite');
        console.log('   POST /api/team/accept-invite');
        console.log('   GET  /api/subscription/check-access');
        console.log('   GET  /api/subscription/plan');
        console.log('   POST /api/payment/create-checkout-session');
        console.log('   POST /api/payment/create-portal-session');
        console.log('\n📱 WhatsApp endpoints:');
        console.log('   GET  /api/whatsapp/status');
        console.log('   GET  /api/whatsapp/qr');
        console.log('   POST /api/whatsapp/connect');
        console.log('   POST /api/whatsapp/disconnect');
        console.log('   POST /api/whatsapp/cancel');
        console.log('   GET  /api/whatsapp/groups');
        console.log('   POST /api/whatsapp/monitor');
        console.log('   GET  /api/whatsapp/monitored');
        console.log('   GET  /api/whatsapp/messages');
        console.log('\n🔐 Admin endpoints:');
        console.log('   POST /api/subscription/admin/grant-pro-free');
        console.log('   POST /api/subscription/admin/revoke-pro-free');
        console.log('   GET  /api/subscription/admin/list-pro-free');
        console.log('\n📁 Storage endpoints:');
        console.log('   GET  /api/storage/list');
        console.log('   POST /api/storage/upload');
        console.log('   GET  /api/storage/download/*');
        console.log('   DELETE /api/storage/delete/*');
        console.log('   POST /api/storage/folder');
        console.log('   DELETE /api/storage/folder/*');
        console.log('   POST /api/storage/rename');
        console.log('   POST /api/storage/move');
        console.log('   GET  /api/storage/folders');
        console.log('   GET  /api/storage/presigned/upload');
        console.log('   GET  /api/storage/presigned/download/*');
        console.log('\n==========================================================\n');
    });
}

// Start the server
startServer();