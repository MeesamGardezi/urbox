/**
 * Encryption Service
 * 
 * Handles encryption/decryption of sensitive data (IMAP passwords, OAuth tokens)
 * Uses AES-256-GCM for authenticated encryption
 * 
 * Security features:
 * - Random IV for each encryption
 * - Authentication tag to prevent tampering
 * - 256-bit encryption key
 */

const crypto = require('crypto');

class EncryptionService {
    constructor() {
        // Load encryption key from environment
        this.encryptionKey = process.env.ENCRYPTION_KEY;

        if (!this.encryptionKey) {
            throw new Error('ENCRYPTION_KEY environment variable is required. Run: npm run generate-keys');
        }

        // Convert hex string to buffer
        this.keyBuffer = Buffer.from(this.encryptionKey, 'hex');

        // Verify key length (must be 32 bytes for AES-256)
        if (this.keyBuffer.length !== 32) {
            throw new Error('ENCRYPTION_KEY must be 64 hex characters (32 bytes). Run: npm run generate-keys');
        }

        // Use AES-256-GCM (Galois/Counter Mode) for authenticated encryption
        this.algorithm = 'aes-256-gcm';

        console.log('[Encryption] Service initialized successfully ✓');
    }

    /**
     * Encrypt sensitive data
     * @param {string} plaintext - The data to encrypt
     * @returns {string|null} - Encrypted data in format: iv:authTag:ciphertext (all hex)
     */
    encrypt(plaintext) {
        if (!plaintext) return null;

        try {
            // Generate random IV (Initialization Vector) - 16 bytes
            const iv = crypto.randomBytes(16);

            // Create cipher with key and IV
            const cipher = crypto.createCipheriv(this.algorithm, this.keyBuffer, iv);

            // Encrypt the plaintext
            let encrypted = cipher.update(plaintext, 'utf8', 'hex');
            encrypted += cipher.final('hex');

            // Get authentication tag (ensures data integrity)
            const authTag = cipher.getAuthTag();

            // Return format: iv:authTag:encrypted (all in hex)
            // This format allows us to extract all components during decryption
            return `${iv.toString('hex')}:${authTag.toString('hex')}:${encrypted}`;
        } catch (error) {
            console.error('[Encryption] Error encrypting data:', error.message);
            throw new Error('Encryption failed');
        }
    }

    /**
     * Decrypt sensitive data
     * @param {string} encryptedData - The encrypted string (iv:authTag:ciphertext)
     * @returns {string|null} - Original plaintext
     */
    decrypt(encryptedData) {
        if (!encryptedData) return null;

        try {
            // Split the encrypted data into components
            const parts = encryptedData.split(':');

            if (parts.length !== 3) {
                throw new Error('Invalid encrypted data format. Expected: iv:authTag:ciphertext');
            }

            // Extract components
            const iv = Buffer.from(parts[0], 'hex');
            const authTag = Buffer.from(parts[1], 'hex');
            const encrypted = parts[2];

            // Create decipher
            const decipher = crypto.createDecipheriv(this.algorithm, this.keyBuffer, iv);

            // Set authentication tag (verifies data integrity)
            decipher.setAuthTag(authTag);

            // Decrypt
            let decrypted = decipher.update(encrypted, 'hex', 'utf8');
            decrypted += decipher.final('utf8');

            return decrypted;
        } catch (error) {
            console.error('[Encryption] Error decrypting data:', error.message);
            throw new Error('Decryption failed - data may be corrupted or key is incorrect');
        }
    }

    /**
     * One-way hash for password verification (not for encryption)
     * Use this when you need to verify data without decrypting
     * @param {string} data - Data to hash
     * @returns {string} - SHA-256 hash (hex)
     */
    hash(data) {
        return crypto.createHash('sha256').update(data).digest('hex');
    }

    /**
     * Generate a secure random token
     * Useful for invite tokens, session IDs, etc.
     * @param {number} bytes - Number of random bytes (default: 32)
     * @returns {string} - Random token (hex)
     */
    generateToken(bytes = 32) {
        return crypto.randomBytes(bytes).toString('hex');
    }

    /**
     * Static method to generate a new encryption key
     * Use this to create your ENCRYPTION_KEY
     * @returns {string} - 64 character hex string (32 bytes)
     */
    static generateKey() {
        return crypto.randomBytes(32).toString('hex');
    }
}

// Export singleton instance
module.exports = new EncryptionService();