import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import '../../core/config/app_config.dart';
import '../models/storage_model.dart';

/// Storage Service
///
/// Handles all storage API communication
class StorageService {
  final String? companyId;

  StorageService({this.companyId});

  /// Get headers with company context
  Map<String, String> get _headers {
    final headers = <String, String>{};
    if (companyId != null) {
      headers['x-company-id'] = companyId!;
    }
    return headers;
  }

  /// List files with optional prefix (folder path)
  Future<List<StorageFile>> listFiles({String prefix = ''}) async {
    try {
      print('[StorageService] Listing files with prefix: "$prefix"');
      final uri = Uri.parse(
        AppConfig.storageListEndpoint,
      ).replace(queryParameters: {'prefix': prefix, 'maxKeys': '1000'});

      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> filesJson = data['files'] ?? [];
        return filesJson.map((json) => StorageFile.fromJson(json)).toList();
      } else {
        print(
          '[StorageService] List error: ${response.statusCode} - ${response.body}',
        );
        throw Exception(
          'Failed to list files: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      print('[StorageService] List exception: $e');
      throw Exception('Error listing files: $e');
    }
  }

  /// Upload a file
  Future<void> uploadFile(PlatformFile file, {String folder = ''}) async {
    try {
      print(
        '[StorageService] Uploading file: ${file.name} to folder: "$folder"',
      );
      var request = http.MultipartRequest(
        'POST',
        Uri.parse(AppConfig.storageUploadEndpoint),
      );

      request.headers.addAll(_headers);

      // Add folder field
      request.fields['folder'] = folder;

      // Add file
      if (file.bytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            file.bytes!,
            filename: file.name,
          ),
        );
      } else if (file.path != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'file',
            file.path!,
            filename: file.name,
          ),
        );
      } else {
        throw Exception('File has no content (bytes or path)');
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200) {
        String errorMessage = 'Failed to upload file';
        try {
          final bodyFn = jsonDecode(response.body);
          if (bodyFn['error'] != null) {
            errorMessage = bodyFn['error'];
          } else {
            errorMessage = response.body;
          }
        } catch (_) {
          errorMessage = response.body.isNotEmpty
              ? response.body
              : 'Status ${response.statusCode}';
        }
        print('[StorageService] Upload error: $errorMessage');
        throw Exception(errorMessage);
      }
      print('[StorageService] Upload success');
    } catch (e) {
      print('[StorageService] Upload exception: $e');
      throw Exception('Error uploading file: $e');
    }
  }

  /// Create a folder
  Future<void> createFolder(String name) async {
    try {
      print('[StorageService] Creating folder: "$name"');
      final headers = _headers;
      headers['Content-Type'] = 'application/json';

      final response = await http.post(
        Uri.parse(AppConfig.storageFolderEndpoint),
        headers: headers,
        body: jsonEncode({'name': name}),
      );

      if (response.statusCode != 200) {
        print('[StorageService] Create folder error: ${response.body}');
        throw Exception('Failed to create folder: ${response.body}');
      }
      print('[StorageService] Folder created');
    } catch (e) {
      print('[StorageService] Create folder exception: $e');
      throw Exception('Error creating folder: $e');
    }
  }

  /// Delete a file
  Future<void> deleteFile(String key) async {
    try {
      print('[StorageService] Deleting file: "$key"');
      // Encode key to safe URL string (preserving slashes)
      final encodedKey = Uri.encodeFull(key);
      final url = AppConfig.storageDeleteEndpoint(encodedKey);

      final response = await http.delete(Uri.parse(url), headers: _headers);

      if (response.statusCode != 200) {
        print('[StorageService] Delete file error: ${response.body}');
        throw Exception('Failed to delete file: ${response.body}');
      }
      print('[StorageService] File deleted');
    } catch (e) {
      print('[StorageService] Delete file exception: $e');
      throw Exception('Error deleting file: $e');
    }
  }

  /// Delete a folder (recursive)
  Future<void> deleteFolder(String name) async {
    try {
      print('[StorageService] Deleting folder: "$name"');
      final encodedName = Uri.encodeFull(name);
      final url = AppConfig.storageDeleteFolderEndpoint(encodedName);

      final response = await http.delete(Uri.parse(url), headers: _headers);

      if (response.statusCode != 200) {
        print('[StorageService] Delete folder error: ${response.body}');
        throw Exception('Failed to delete folder: ${response.body}');
      }
      print('[StorageService] Folder deleted');
    } catch (e) {
      print('[StorageService] Delete folder exception: $e');
      throw Exception('Error deleting folder: $e');
    }
  }

  /// Get download URL (presigned)
  Future<String> getDownloadUrl(String key) async {
    try {
      print('[StorageService] Getting download URL for: "$key"');
      final encodedKey = Uri.encodeFull(key);

      // Use presigned download URL for direct browser access
      final uri = Uri.parse(
        AppConfig.storagePresignedDownloadEndpoint(encodedKey),
      );

      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('[StorageService] Got download URL: ${data['presignedUrl']}');
        return data['presignedUrl'];
      } else {
        print('[StorageService] Failed to get presigned URL: ${response.body}');
        // Fallback to direct download endpoint
        return AppConfig.storageDownloadEndpoint(encodedKey);
      }
    } catch (e) {
      print('[StorageService] Get download URL exception: $e');
      // Fallback to direct download endpoint
      return AppConfig.storageDownloadEndpoint(Uri.encodeFull(key));
    }
  }

  /// Rename a file or folder
  Future<void> renameFile(String key, String newName) async {
    try {
      print('[StorageService] Renaming "$key" to "$newName"');
      final headers = _headers;
      headers['Content-Type'] = 'application/json';

      final response = await http.post(
        Uri.parse(AppConfig.storageRenameEndpoint),
        headers: headers,
        body: jsonEncode({'key': key, 'newName': newName}),
      );

      if (response.statusCode != 200) {
        final data = jsonDecode(response.body);
        print('[StorageService] Rename error: ${data['error']}');
        throw Exception(data['error'] ?? 'Failed to rename');
      }
      print('[StorageService] Rename success');
    } catch (e) {
      print('[StorageService] Rename exception: $e');
      throw Exception('Error renaming: $e');
    }
  }

  /// Move a file or folder to a new destination
  Future<void> moveFile(String key, String destination) async {
    try {
      print('[StorageService] Moving "$key" to "$destination"');
      final headers = _headers;
      headers['Content-Type'] = 'application/json';

      final response = await http.post(
        Uri.parse(AppConfig.storageMoveEndpoint),
        headers: headers,
        body: jsonEncode({'key': key, 'destination': destination}),
      );

      if (response.statusCode != 200) {
        final data = jsonDecode(response.body);
        print('[StorageService] Move error: ${data['error']}');
        throw Exception(data['error'] ?? 'Failed to move');
      }
      print('[StorageService] Move success');
    } catch (e) {
      print('[StorageService] Move exception: $e');
      throw Exception('Error moving: $e');
    }
  }

  /// Get all folders (for move dialog)
  Future<List<Map<String, dynamic>>> getFolders() async {
    try {
      print('[StorageService] Getting folders');
      final response = await http.get(
        Uri.parse(AppConfig.storageFoldersEndpoint),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> foldersJson = data['folders'] ?? [];
        return foldersJson.cast<Map<String, dynamic>>();
      } else {
        print('[StorageService] Get folders error: ${response.body}');
        throw Exception('Failed to get folders');
      }
    } catch (e) {
      print('[StorageService] Get folders exception: $e');
      throw Exception('Error getting folders: $e');
    }
  }
}
