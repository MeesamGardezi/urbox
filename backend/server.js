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
if (!admin.apps.length) {
    try {
        const serviceAccount = require('./firebase-service-account.json');

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

const db = admin.firestore();

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

// Health check endpoint
app.get('/health', (req, res) => {
    res.json({
        status: 'healthy',
        timestamp: new Date().toISOString(),
        version: '1.0.0',
        environment: process.env.NODE_ENV || 'development'
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

// Start server
app.listen(PORT, () => {
    console.log('\n==========================================================');
    console.log('         SHARED MAILBOX BACKEND');
    console.log('==========================================================');
    console.log(`✓ Server running on port ${PORT}`);
    console.log(`✓ Environment: ${process.env.NODE_ENV || 'development'}`);
    console.log(`✓ App URL: ${process.env.APP_URL || 'http://localhost:8080'}`);
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

// Graceful shutdown
process.on('SIGTERM', () => {
    console.log('\n⚠️  SIGTERM received, shutting down gracefully...');
    process.exit(0);
});

process.on('SIGINT', () => {
    console.log('\n⚠️  SIGINT received, shutting down gracefully...');
    process.exit(0);
});