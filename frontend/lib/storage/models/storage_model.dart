/// Storage File Model
///
/// Represents a file or folder in the storage system
class StorageFile {
  final String key;
  final int size;
  final DateTime lastModified;
  final String? etag;
  final bool isFolder;

  StorageFile({
    required this.key,
    required this.size,
    required this.lastModified,
    this.etag,
    this.isFolder = false,
  });

  factory StorageFile.fromJson(Map<String, dynamic> json) {
    return StorageFile(
      key: json['key'] ?? '',
      size: json['size'] ?? 0,
      lastModified:
          DateTime.tryParse(json['lastModified'] ?? '') ?? DateTime.now(),
      etag: json['etag'],
      isFolder: json['isFolder'] ?? json['key']?.endsWith('/') ?? false,
    );
  }

  /// Get the display name (last part of the path)
  String get name {
    final parts = key.split('/');
    if (isFolder) {
      // For folder "a/b/", parts are ["a", "b", ""]
      // We want "b"
      return parts.length > 1 ? parts[parts.length - 2] : parts[0];
    }
    return parts.last;
  }

  /// Get file extension (lowercase)
  String get extension {
    if (isFolder) return '';
    final parts = name.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : '';
  }

  /// Get formatted file size
  String get formattedSize {
    if (isFolder) return '';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

/// Upload status enum
enum UploadStatus { pending, uploading, success, error }

/// Upload task item for tracking upload progress
class UploadItem {
  final String id;
  final String name;
  UploadStatus status;
  String? errorMessage;

  UploadItem({
    required this.id,
    required this.name,
    this.status = UploadStatus.pending,
    this.errorMessage,
  });
}
