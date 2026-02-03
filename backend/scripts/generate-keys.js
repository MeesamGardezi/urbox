#!/usr/bin/env node
/**
 * Generate Encryption Keys Script
 * 
 * Run this once to generate your ENCRYPTION_KEY and ADMIN_SECRET
 * Then add them to your .env file
 */

const crypto = require('crypto');

console.log('\n==========================================================');
console.log('         SHARED MAILBOX - KEY GENERATION');
console.log('==========================================================\n');

// Generate Encryption Key (32 bytes = 64 hex chars for AES-256)
const encryptionKey = crypto.randomBytes(32).toString('hex');
console.log('📦 ENCRYPTION_KEY (for encrypting IMAP passwords):');
console.log('----------------------------------------------------------');
console.log(encryptionKey);
console.log('----------------------------------------------------------\n');

// Generate Admin Secret (32 bytes in base64)
const adminSecret = crypto.randomBytes(32).toString('base64');
console.log('🔐 ADMIN_SECRET (for granting pro-free access):');
console.log('----------------------------------------------------------');
console.log(adminSecret);
console.log('----------------------------------------------------------\n');

console.log('⚠️  IMPORTANT:');
console.log('   1. Copy these values to your .env file');
console.log('   2. NEVER commit these keys to version control');
console.log('   3. Keep them secure and backed up');
console.log('   4. These keys are used to encrypt sensitive data\n');

console.log('📝 Add to your .env file:');
console.log('==========================================================');
console.log(`ENCRYPTION_KEY=${encryptionKey}`);
console.log(`ADMIN_SECRET=${adminSecret}`);
console.log('==========================================================\n');