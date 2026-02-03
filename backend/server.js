/**
 * Shared Mailbox - Main Server
 * 
 * Handles:
 * - Express server setup
 * - Firebase Admin initialization
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
    console.error('\n💡 Run: npm run generate-keys');
    console.error('   Then add the keys to your .env file\n');
    process.exit(1);
}

// Initialize Firebase Admin
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
    databaseId: 'default'
});

// Function to verify Firestore connection
async function verifyFirestoreConnection() {
    console.log('\n🔍 Verifying Firestore connection...');

    try {
        // Try a simple write/read to verify connection
        const testDocRef = db.collection('_connection_test').doc('test');

        await testDocRef.set({
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            test: true
        });

        const testDoc = await testDocRef.get();

        if (testDoc.exists) {
            console.log('✓ Firestore connection verified successfully!');
            // Clean up test document
            await testDocRef.delete();
            return true;
        } else {
            console.error('❌ Firestore test document was not created');
            return false;
        }
    } catch (error) {
        console.error('❌ Firestore connection failed!');
        console.error(`   Error Code: ${error.code}`);
        console.error(`   Error Message: ${error.message}`);

        if (error.code === 5 || error.message.includes('NOT_FOUND')) {
            console.error('\n💡 SOLUTION: The Firestore database does not exist.');
            console.error('   1. Go to Firebase Console: https://console.firebase.google.com');
            console.error('   2. Select your project');
            console.error('   3. Click "Firestore Database" in the sidebar');
            console.error('   4. Click "Create database"');
            console.error('   5. Choose a location and security rules');
            console.error('   6. Restart this server\n');
        } else if (error.code === 7 || error.message.includes('PERMISSION_DENIED')) {
            console.error('\n💡 SOLUTION: Permission denied.');
            console.error('   1. Check your Firestore security rules');
            console.error('   2. Verify the service account has correct permissions');
            console.error('   3. In Firebase Console > Project Settings > Service Accounts');
            console.error('   4. Ensure the service account has "Firebase Admin SDK" role\n');
        }

        return false;
    }
}

// Import routes
const createAuthRoutes = require('./auth/auth');
const createTeamRoutes = require('./team/team');
const createSubscriptionRoutes = require('./core/subscription');
const createPaymentRoutes = require('./payment/payments');

// Create Express app
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

// Health check endpoint with Firestore status
app.get('/health', async (req, res) => {
    let firestoreStatus = 'unknown';

    try {
        // Quick Firestore check
        await db.collection('_health').doc('check').get();
        firestoreStatus = 'connected';
    } catch (error) {
        firestoreStatus = `error: ${error.code || error.message}`;
    }

    res.json({
        status: 'healthy',
        timestamp: new Date().toISOString(),
        version: '1.0.0',
        environment: process.env.NODE_ENV || 'development',
        firestore: firestoreStatus
    });
});

// Register routes
app.use('/api/auth', createAuthRoutes(db));
app.use('/api/team', createTeamRoutes(db));
app.use('/api/subscription', createSubscriptionRoutes(db));
app.use('/api/payment', createPaymentRoutes(db));

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

// Start server with Firestore verification
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
        console.log('         SHARED MAILBOX BACKEND');
        console.log('==========================================================');
        console.log(`✓ Server running on port ${PORT}`);
        console.log(`✓ Environment: ${process.env.NODE_ENV || 'development'}`);
        console.log(`✓ App URL: ${process.env.APP_URL || 'http://localhost:8080'}`);
        console.log(`✓ Firestore: Connected`);
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
        console.log('\n🔐 Admin endpoints:');
        console.log('   POST /api/subscription/admin/grant-pro-free');
        console.log('   POST /api/subscription/admin/revoke-pro-free');
        console.log('   GET  /api/subscription/admin/list-pro-free');
        console.log('\n==========================================================\n');
    });
}

// Start the server
startServer();

// Graceful shutdown
process.on('SIGTERM', () => {
    console.log('\n⚠️  SIGTERM received, shutting down gracefully...');
    process.exit(0);
});

process.on('SIGINT', () => {
    console.log('\n⚠️  SIGINT received, shutting down gracefully...');
    process.exit(0);
});