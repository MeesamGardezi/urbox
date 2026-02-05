/**
 * Storage Service
 * 
 * Handles file operations with Cloudflare R2 (S3-compatible)
 * Supports: upload, download, delete, list, folders, presigned URLs
 */

const {
    S3Client,
    GetObjectCommand,
    DeleteObjectCommand,
    ListObjectsV2Command,
    PutObjectCommand,
} = require("@aws-sdk/client-s3");
const { getSignedUrl } = require("@aws-sdk/s3-request-presigner");
const { Upload } = require("@aws-sdk/lib-storage");
const path = require("path");

class StorageService {
    constructor() {
        // Support both R2 and AWS S3 configuration
        const isR2 = process.env.R2_ENDPOINT || process.env.CLOUDFLARE_R2_ENDPOINT;

        this.bucketName = process.env.R2_BUCKET_NAME || process.env.AWS_BUCKET_NAME;

        if (isR2) {
            // Cloudflare R2 configuration
            this.s3Client = new S3Client({
                region: "auto",
                endpoint: process.env.R2_ENDPOINT || process.env.CLOUDFLARE_R2_ENDPOINT,
                credentials: {
                    accessKeyId: process.env.R2_ACCESS_KEY_ID || process.env.AWS_ACCESS_KEY_ID,
                    secretAccessKey: process.env.R2_SECRET_ACCESS_KEY || process.env.AWS_SECRET_ACCESS_KEY,
                },
            });
            console.log('[Storage] Configured for Cloudflare R2');
        } else {
            // AWS S3 configuration
            this.s3Client = new S3Client({
                region: process.env.AWS_REGION || "us-east-1",
                credentials: {
                    accessKeyId: process.env.AWS_ACCESS_KEY_ID,
                    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
                },
            });
            console.log('[Storage] Configured for AWS S3');
        }
    }

    /**
     * uploadFile
     * Uploads a file buffer to storage using @aws-sdk/lib-storage
     * Works for both small and large files (multipart)
     */
    async uploadFile(file, folder = "") {
        try {
            if (!file) {
                throw new Error("No file provided");
            }

            // Ensure no double slashes if folder already ends with /
            let cleanFolder = folder;
            if (cleanFolder.endsWith('/')) {
                cleanFolder = cleanFolder.slice(0, -1);
            }
            const key = cleanFolder ? `${cleanFolder}/${file.originalname}` : file.originalname;

            // Use @aws-sdk/lib-storage for reliable uploads
            const upload = new Upload({
                client: this.s3Client,
                params: {
                    Bucket: this.bucketName,
                    Key: key,
                    Body: file.buffer,
                    ContentType: file.mimetype,
                },
                queueSize: 4,
                partSize: 1024 * 1024 * 5, // 5MB parts
                leavePartsOnError: false,
            });

            await upload.done();

            console.log(`[Storage] File uploaded: ${key}`);

            return {
                success: true,
                message: "File uploaded successfully",
                key: key,
                size: file.size,
                contentType: file.mimetype,
            };
        } catch (error) {
            console.error("[Storage] Upload error:", error);
            throw error;
        }
    }

    /**
     * downloadFile
     * Returns the S3 response object (Body is a stream)
     */
    async downloadFile(key) {
        try {
            const command = new GetObjectCommand({
                Bucket: this.bucketName,
                Key: key,
            });

            const response = await this.s3Client.send(command);
            return response;
        } catch (error) {
            console.error("[Storage] Download error:", error);
            throw error;
        }
    }

    /**
     * deleteFile
     * Deletes a file by key
     */
    async deleteFile(key) {
        try {
            const command = new DeleteObjectCommand({
                Bucket: this.bucketName,
                Key: key,
            });

            await this.s3Client.send(command);

            console.log(`[Storage] File deleted: ${key}`);

            return {
                success: true,
                message: "File deleted successfully",
                key: key,
            };
        } catch (error) {
            console.error("[Storage] Delete error:", error);
            throw error;
        }
    }

    /**
     * listFiles
     * Lists files with optional prefix (folder path)
     * Uses S3 delimiter to simulate folder structure
     */
    async listFiles(prefix = "", maxKeys = 1000) {
        try {
            const command = new ListObjectsV2Command({
                Bucket: this.bucketName,
                Prefix: prefix,
                MaxKeys: maxKeys,
                Delimiter: "/",
            });

            const response = await this.s3Client.send(command);

            // Map files from Contents
            const files = (response.Contents || []).map((item) => ({
                key: item.Key,
                size: item.Size,
                lastModified: item.LastModified,
                etag: item.ETag,
                isFolder: false,
            }));

            // Map folders from CommonPrefixes
            const folders = (response.CommonPrefixes || []).map((item) => ({
                key: item.Prefix,
                size: 0,
                lastModified: new Date(),
                etag: null,
                isFolder: true,
            }));

            // Deduplicate: prefer folder entries over file entries with same key
            const uniqueItems = new Map();

            [...folders, ...files].forEach(item => {
                if (item.key !== prefix) {
                    if (!uniqueItems.has(item.key)) {
                        uniqueItems.set(item.key, item);
                    } else if (item.isFolder) {
                        uniqueItems.set(item.key, item);
                    }
                }
            });

            return {
                success: true,
                count: uniqueItems.size,
                prefix: prefix,
                files: Array.from(uniqueItems.values()),
            };
        } catch (error) {
            console.error("[Storage] List error:", error);
            throw error;
        }
    }

    /**
     * createFolder
     * Creates a zero-byte object ending in / to represent a folder
     */
    async createFolder(name) {
        try {
            const folderKey = name.endsWith("/") ? name : `${name}/`;

            const command = new PutObjectCommand({
                Bucket: this.bucketName,
                Key: folderKey,
                Body: "",
            });

            await this.s3Client.send(command);

            console.log(`[Storage] Folder created: ${folderKey}`);

            return {
                success: true,
                message: "Folder created successfully",
                folder: folderKey,
            };
        } catch (error) {
            console.error("[Storage] Create folder error:", error);
            throw error;
        }
    }

    /**
     * deleteFolder
     * Recursively deletes a folder and all its contents
     */
    async deleteFolder(folderName) {
        try {
            const folderPrefix = folderName.endsWith("/") ? folderName : `${folderName}/`;

            // List all objects with this prefix
            const listCommand = new ListObjectsV2Command({
                Bucket: this.bucketName,
                Prefix: folderPrefix,
            });

            const listResponse = await this.s3Client.send(listCommand);
            const objects = listResponse.Contents || [];

            if (objects.length === 0) {
                return { success: true, message: "Folder already empty or not found" };
            }

            // Delete all objects in parallel
            const deletePromises = objects.map((obj) => {
                const deleteCommand = new DeleteObjectCommand({
                    Bucket: this.bucketName,
                    Key: obj.Key,
                });
                return this.s3Client.send(deleteCommand);
            });

            await Promise.all(deletePromises);

            console.log(`[Storage] Folder deleted: ${folderPrefix} (${objects.length} items)`);

            return {
                success: true,
                message: "Folder and contents deleted successfully",
                folder: folderPrefix,
                deletedCount: objects.length,
            };
        } catch (error) {
            console.error("[Storage] Delete folder error:", error);
            throw error;
        }
    }

    /**
     * getPresignedUploadUrl
     * Generates a presigned URL for direct client uploads
     */
    async getPresignedUploadUrl(key, contentType) {
        try {
            const command = new PutObjectCommand({
                Bucket: this.bucketName,
                Key: key,
                ContentType: contentType || "application/octet-stream",
            });

            const url = await getSignedUrl(this.s3Client, command, {
                expiresIn: 3600, // 1 hour
            });

            return {
                success: true,
                presignedUrl: url,
                key: key,
                expiresIn: 3600,
            };
        } catch (error) {
            console.error("[Storage] Presigned upload error:", error);
            throw error;
        }
    }

    /**
     * getPresignedDownloadUrl
     * Generates a presigned URL for direct client downloads
     */
    async getPresignedDownloadUrl(key) {
        try {
            const command = new GetObjectCommand({
                Bucket: this.bucketName,
                Key: key,
            });

            const url = await getSignedUrl(this.s3Client, command, {
                expiresIn: 3600, // 1 hour
            });

            return {
                success: true,
                presignedUrl: url,
                key: key,
                expiresIn: 3600,
            };
        } catch (error) {
            console.error("[Storage] Presigned download error:", error);
            throw error;
        }
    }
}

module.exports = { StorageService };
