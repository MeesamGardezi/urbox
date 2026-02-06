/**
 * Storage Routes
 * 
 * RESTful API endpoints for file storage operations
 * All operations are scoped to a company via x-company-id header
 */

const express = require('express');
const multer = require('multer');
const path = require('path');

// Multer setup for file uploads (500MB limit)
const upload = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: 500 * 1024 * 1024 },
});

function createStorageRoutes(storageService, db) {
    const router = express.Router();

    // =========================================================================
    // MIDDLEWARE: Company Context
    // =========================================================================

    /**
     * Middleware to extract/validate companyId from header
     * All storage operations are scoped to a company's folder
     */
    const companyMiddleware = async (req, res, next) => {
        const companyId = req.headers['x-company-id'];

        if (!companyId) {
            return res.status(401).json({
                success: false,
                error: "Access denied. Company context required (x-company-id header)."
            });
        }

        // Verify company exists in Firestore
        try {
            const companyDoc = await db.collection('companies').doc(companyId).get();
            if (!companyDoc.exists) {
                return res.status(404).json({
                    success: false,
                    error: "Company not found"
                });
            }
        } catch (error) {
            console.error('[Storage] Company verification error:', error);
            // Continue anyway - company ID is valid format
        }

        // Add company helpers to request
        req.companyId = companyId;
        req.companyPrefix = `${companyId}/`;

        // Helper to prefix keys with company folder
        req.toAbsoluteKey = (key) => {
            const cleanKey = key.startsWith('/') ? key.substring(1) : key;
            return `${req.companyPrefix}${cleanKey}`;
        };

        // Helper to strip company prefix from keys
        req.toRelativeKey = (key) => {
            if (key.startsWith(req.companyPrefix)) {
                return key.substring(req.companyPrefix.length);
            }
            return key;
        };

        next();
    };

    router.use(companyMiddleware);

    // =========================================================================
    // ROUTES
    // =========================================================================

    /**
     * POST /upload
     * Upload a file to the company's storage
     * 
     * Body (multipart/form-data):
     *   - file: The file to upload
     *   - folder: Optional subfolder path (e.g., "documents/2024")
     */
    router.post('/upload', (req, res) => {
        upload.single('file')(req, res, async (err) => {
            if (err instanceof multer.MulterError) {
                return res.status(400).json({
                    success: false,
                    error: `Upload error: ${err.message}`
                });
            } else if (err) {
                return res.status(500).json({
                    success: false,
                    error: `Unknown upload error: ${err.message}`
                });
            }

            try {
                if (!req.file) {
                    return res.status(400).json({
                        success: false,
                        error: "No file provided"
                    });
                }

                const relativeFolder = req.body.folder || req.query.folder || "";
                const absoluteFolder = req.toAbsoluteKey(relativeFolder);

                const result = await storageService.uploadFile(req.file, absoluteFolder);
                result.key = req.toRelativeKey(result.key);

                res.json(result);
            } catch (serviceErr) {
                console.error('[Storage] Upload route error:', serviceErr);
                res.status(500).json({
                    success: false,
                    error: serviceErr.message
                });
            }
        });
    });

    /**
     * GET /download/:key(*)
     * Download a file by key
     * Uses regex to capture full path including slashes
     */
    router.get(/^\/download\/(.*)/, async (req, res) => {
        try {
            const relativeKey = req.params[0];
            if (!relativeKey) {
                return res.status(400).json({
                    success: false,
                    error: "No file key provided"
                });
            }

            const absoluteKey = req.toAbsoluteKey(relativeKey);
            const response = await storageService.downloadFile(absoluteKey);

            // Set response headers
            res.setHeader("Content-Type", response.ContentType || "application/octet-stream");
            res.setHeader("Content-Disposition", `attachment; filename="${path.basename(relativeKey)}"`);

            // Stream file to response
            response.Body.pipe(res);
        } catch (err) {
            if (err.name === "NoSuchKey") {
                return res.status(404).json({
                    success: false,
                    error: "File not found"
                });
            }
            console.error('[Storage] Download route error:', err);
            res.status(500).json({
                success: false,
                error: err.message
            });
        }
    });

    /**
     * DELETE /delete/:key(*)
     * Delete a file by key
     */
    router.delete(/^\/delete\/(.*)/, async (req, res) => {
        try {
            const relativeKey = req.params[0];
            if (!relativeKey) {
                return res.status(400).json({
                    success: false,
                    error: "No file key provided"
                });
            }

            const absoluteKey = req.toAbsoluteKey(relativeKey);
            const result = await storageService.deleteFile(absoluteKey);
            result.key = relativeKey;

            res.json(result);
        } catch (err) {
            console.error('[Storage] Delete route error:', err);
            res.status(500).json({
                success: false,
                error: err.message
            });
        }
    });

    /**
     * GET /list
     * List files and folders
     * 
     * Query params:
     *   - prefix: Folder path to list (default: root)
     *   - maxKeys: Maximum items to return (default: 1000)
     */
    router.get('/list', async (req, res) => {
        try {
            const relativePrefix = req.query.prefix || "";
            const absolutePrefix = req.toAbsoluteKey(relativePrefix);
            const maxKeys = parseInt(req.query.maxKeys) || 1000;

            const result = await storageService.listFiles(absolutePrefix, maxKeys);

            // Auto-create company folder if listing root and empty
            if (relativePrefix === "" && result.count === 0) {
                await storageService.createFolder(req.companyPrefix);
            }

            // Convert keys to relative paths
            result.files = result.files.map(f => ({
                ...f,
                key: req.toRelativeKey(f.key)
            }));

            // Filter out the company folder itself
            result.files = result.files.filter(f => f.key !== "" && f.key !== "/");
            result.prefix = relativePrefix;

            res.json(result);
        } catch (err) {
            console.error('[Storage] List route error:', err);
            res.status(500).json({
                success: false,
                error: err.message
            });
        }
    });

    /**
     * POST /folder
     * Create a new folder
     * 
     * Body:
     *   - name: Folder name/path (e.g., "Documents" or "Documents/2024")
     */
    router.post('/folder', async (req, res) => {
        try {
            const { name } = req.body;
            if (!name) {
                return res.status(400).json({
                    success: false,
                    error: "Folder name is required"
                });
            }

            const absoluteName = req.toAbsoluteKey(name);
            const result = await storageService.createFolder(absoluteName);
            result.folder = req.toRelativeKey(result.folder);

            res.json(result);
        } catch (err) {
            console.error('[Storage] Create folder route error:', err);
            res.status(500).json({
                success: false,
                error: err.message
            });
        }
    });

    /**
     * DELETE /folder/:name(*)
     * Delete a folder and all its contents recursively
     */
    router.delete(/^\/folder\/(.*)/, async (req, res) => {
        try {
            const relativeName = req.params[0];
            if (!relativeName) {
                return res.status(400).json({
                    success: false,
                    error: "Folder name is required"
                });
            }

            const absoluteName = req.toAbsoluteKey(relativeName);
            const result = await storageService.deleteFolder(absoluteName);
            result.folder = relativeName;

            res.json(result);
        } catch (err) {
            console.error('[Storage] Delete folder route error:', err);
            res.status(500).json({
                success: false,
                error: err.message
            });
        }
    });

    /**
     * GET /presigned/upload
     * Get a presigned URL for direct upload to storage
     * 
     * Query params:
     *   - key: File path/name
     *   - contentType: MIME type (optional)
     */
    router.get('/presigned/upload', async (req, res) => {
        try {
            const { key, contentType } = req.query;
            if (!key) {
                return res.status(400).json({
                    success: false,
                    error: "File key is required"
                });
            }

            const absoluteKey = req.toAbsoluteKey(key);
            const result = await storageService.getPresignedUploadUrl(absoluteKey, contentType);
            result.key = key; // Return relative key

            res.json(result);
        } catch (err) {
            console.error('[Storage] Presigned upload route error:', err);
            res.status(500).json({
                success: false,
                error: err.message
            });
        }
    });

    /**
     * GET /presigned/download/:key(*)
     * Get a presigned URL for direct download from storage
     */
    router.get(/^\/presigned\/download\/(.*)/, async (req, res) => {
        try {
            const relativeKey = req.params[0];
            if (!relativeKey) {
                return res.status(400).json({
                    success: false,
                    error: "File key is required"
                });
            }

            const absoluteKey = req.toAbsoluteKey(relativeKey);
            const result = await storageService.getPresignedDownloadUrl(absoluteKey);
            result.key = relativeKey;

            res.json(result);
        } catch (err) {
            console.error('[Storage] Presigned download route error:', err);
            res.status(500).json({
                success: false,
                error: err.message
            });
        }
    });

    /**
     * POST /rename
     * Rename a file or folder
     * 
     * Body:
     *   - key: Current file/folder key
     *   - newName: New name for the file/folder
     */
    router.post('/rename', async (req, res) => {
        try {
            const { key, newName } = req.body;

            if (!key || !newName) {
                return res.status(400).json({
                    success: false,
                    error: "Both 'key' and 'newName' are required"
                });
            }

            // Validate new name (no slashes, not empty)
            if (newName.includes('/') || newName.trim() === '') {
                return res.status(400).json({
                    success: false,
                    error: "Invalid new name. Name cannot contain slashes or be empty."
                });
            }

            const absoluteKey = req.toAbsoluteKey(key);
            const result = await storageService.renameFile(absoluteKey, newName);

            // Convert keys back to relative
            result.oldKey = req.toRelativeKey(result.oldKey);
            result.newKey = req.toRelativeKey(result.newKey);

            res.json(result);
        } catch (err) {
            console.error('[Storage] Rename route error:', err);
            res.status(500).json({
                success: false,
                error: err.message
            });
        }
    });

    /**
     * POST /move
     * Move a file or folder to a new location
     * 
     * Body:
     *   - key: Current file/folder key
     *   - destination: Destination folder path
     */
    router.post('/move', async (req, res) => {
        try {
            const { key, destination } = req.body;

            if (!key) {
                return res.status(400).json({
                    success: false,
                    error: "'key' is required"
                });
            }

            // destination can be empty (move to root)
            const absoluteKey = req.toAbsoluteKey(key);
            const absoluteDestination = destination
                ? req.toAbsoluteKey(destination)
                : req.companyPrefix;

            const result = await storageService.moveFile(absoluteKey, absoluteDestination);

            // Convert keys back to relative
            result.sourceKey = req.toRelativeKey(result.sourceKey);
            result.destinationKey = req.toRelativeKey(result.destinationKey);

            res.json(result);
        } catch (err) {
            console.error('[Storage] Move route error:', err);
            res.status(500).json({
                success: false,
                error: err.message
            });
        }
    });

    /**
     * GET /folders
     * List all folders (for move dialog)
     * 
     * Query params:
     *   - prefix: Optional prefix to start from
     */
    router.get('/folders', async (req, res) => {
        try {
            const absolutePrefix = req.companyPrefix;
            const folders = await storageService.getFolders(absolutePrefix);

            // Convert to relative paths and add root
            const relativeFolders = folders.map(f => ({
                ...f,
                key: req.toRelativeKey(f.key),
            })).filter(f => f.key !== '' && f.key !== '/');

            // Add root option
            relativeFolders.unshift({
                key: '',
                name: 'Root',
            });

            res.json({
                success: true,
                folders: relativeFolders,
            });
        } catch (err) {
            console.error('[Storage] Folders route error:', err);
            res.status(500).json({
                success: false,
                error: err.message
            });
        }
    });

    return router;
}

module.exports = createStorageRoutes;
