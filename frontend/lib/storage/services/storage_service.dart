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
      final uri = Uri.parse(
        AppConfig.storageListEndpoint,
      ).replace(queryParameters: {'prefix': prefix, 'maxKeys': '1000'});

      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> filesJson = data['files'] ?? [];
        return filesJson.map((json) => StorageFile.fromJson(json)).toList();
      } else {
        throw Exception(
          'Failed to list files: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Error listing files: $e');
    }
  }

  /// Upload a file
  Future<void> uploadFile(PlatformFile file, {String folder = ''}) async {
    try {
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
        throw Exception(errorMessage);
      }
    } catch (e) {
      throw Exception('Error uploading file: $e');
    }
  }

  /// Create a folder
  Future<void> createFolder(String name) async {
    try {
      final headers = _headers;
      headers['Content-Type'] = 'application/json';

      final response = await http.post(
        Uri.parse(AppConfig.storageFolderEndpoint),
        headers: headers,
        body: jsonEncode({'name': name}),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to create folder: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error creating folder: $e');
    }
  }

  /// Delete a file
  Future<void> deleteFile(String key) async {
    try {
      final url = AppConfig.storageDeleteEndpoint(key);
      final response = await http.delete(Uri.parse(url), headers: _headers);

      if (response.statusCode != 200) {
        throw Exception('Failed to delete file: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error deleting file: $e');
    }
  }

  /// Delete a folder (recursive)
  Future<void> deleteFolder(String name) async {
    try {
      final url = AppConfig.storageDeleteFolderEndpoint(name);
      final response = await http.delete(Uri.parse(url), headers: _headers);

      if (response.statusCode != 200) {
        throw Exception('Failed to delete folder: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error deleting folder: $e');
    }
  }

  /// Get download URL (presigned)
  Future<String> getDownloadUrl(String key) async {
    try {
      // Use presigned download URL for direct browser access
      final uri = Uri.parse(AppConfig.storagePresignedDownloadEndpoint(key));

      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['presignedUrl'];
      } else {
        throw Exception('Failed to get download link');
      }
    } catch (e) {
      // Fallback to direct download endpoint
      return AppConfig.storageDownloadEndpoint(key);
    }
  }
}
