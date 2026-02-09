import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'folder_tree_selector.dart';
import '../models/storage_model.dart';
import '../services/storage_service.dart';
import '../../auth/services/auth_service.dart';

/// Storage Screen
///
/// Clean, minimalistic file browser with folder navigation and file management
class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  StorageService? _storageService;
  List<StorageFile> _files = [];
  bool _isLoading = true;
  String _currentPath = '';
  String? _companyId;

  // Selection mode
  Set<String> _selectedItems = {};

  // Upload tracking
  List<UploadItem> _uploadTasks = [];
  bool _isUploadsMinimized = false;

  // View mode
  bool _isGridView = false; // Default to list view
  StorageFile? _previewFile;
  bool _isLoadingPreview = false;
  String? _previewUrl;

  /// Breadcrumb navigation parts
  List<String> get _breadcrumbs {
    if (_currentPath.isEmpty) return [];
    final path = _currentPath.endsWith('/')
        ? _currentPath.substring(0, _currentPath.length - 1)
        : _currentPath;
    return path.split('/');
  }

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final userResponse = await AuthService.getUserProfile(user.uid);

      if (userResponse['success'] != true) {
        throw Exception(userResponse['error'] ?? 'Failed to load user profile');
      }

      final userData = userResponse['user'] as Map<String, dynamic>;
      final companyId = userData['companyId'] as String?;

      if (companyId != null && companyId.isNotEmpty) {
        setState(() {
          _companyId = companyId;
          _storageService = StorageService(companyId: companyId);
        });
        await _loadFiles();
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        _showError('Error loading profile: $e');
      }
    }
  }

  Future<void> _loadFiles() async {
    if (_storageService == null) return;

    setState(() => _isLoading = true);
    try {
      final files = await _storageService!.listFiles(prefix: _currentPath);
      files.sort((a, b) {
        if (a.isFolder && !b.isFolder) return -1;
        if (!a.isFolder && b.isFolder) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      setState(() {
        _files = files;
        _isLoading = false;
        _selectedItems.clear();
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        _showError('Error loading files: $e');
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF059669),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }

  // ============================================================================
  // NAVIGATION
  // ============================================================================

  void _navigateToFolder(String folderName) {
    if (_isLoading) return;
    setState(() {
      _currentPath += '$folderName/';
      _isLoading = true;
      _previewFile = null;
      _previewUrl = null;
    });
    _loadFiles();
  }

  void _jumpToBreadcrumb(int index) {
    final parts = _breadcrumbs;
    String newPath = '';
    for (int i = 0; i <= index; i++) {
      newPath += '${parts[i]}/';
    }

    if (newPath == _currentPath) return;

    setState(() {
      _currentPath = newPath;
      _isLoading = true;
      _previewFile = null;
      _previewUrl = null;
    });
    _loadFiles();
  }

  void _goHome() {
    if (_currentPath.isEmpty) return;
    setState(() {
      _currentPath = '';
      _isLoading = true;
      _previewFile = null;
      _previewUrl = null;
    });
    _loadFiles();
  }

  // ============================================================================
  // FILE OPERATIONS
  // ============================================================================

  Future<void> _uploadFile() async {
    if (_storageService == null) return;

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        withData: true,
        allowMultiple: true,
      );

      if (result != null) {
        if (mounted) setState(() => _isUploadsMinimized = false);

        for (final file in result.files) {
          final taskId =
              DateTime.now().millisecondsSinceEpoch.toString() + file.name;
          final task = UploadItem(
            id: taskId,
            name: file.name,
            status: UploadStatus.uploading,
          );

          if (mounted) {
            setState(() {
              _uploadTasks.add(task);
            });
          }

          _performUpload(task, file);
        }
      }
    } catch (e) {
      if (mounted) {
        _showError('Pick file failed: $e');
      }
    }
  }

  Future<void> _performUpload(UploadItem task, PlatformFile file) async {
    try {
      await _storageService!.uploadFile(file, folder: _currentPath);

      if (mounted) {
        setState(() {
          task.status = UploadStatus.success;
        });
        _loadFiles();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          task.status = UploadStatus.error;
          task.errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _CleanDialog(
        title: 'New Folder',
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: 'Enter folder name',
            hintStyle: TextStyle(color: Colors.grey.shade400),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(
                color: Color(0xFF3B82F6),
                width: 1.5,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
          autofocus: true,
          onSubmitted: (val) => Navigator.pop(context, val),
        ),
        primaryLabel: 'Create',
        onPrimary: () => Navigator.pop(context, controller.text),
      ),
    );

    if (name != null && name.isNotEmpty) {
      setState(() => _isLoading = true);
      try {
        if (_storageService != null) {
          final newFolderPath = _currentPath + name;
          await _storageService!.createFolder(newFolderPath);
          _showSuccess('Folder created');
          await _loadFiles();
        }
      } catch (e) {
        if (mounted) {
          _showError('Create folder failed: $e');
        }
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _renameItem(StorageFile item) async {
    print('[StorageScreen] Requested rename for: ${item.name} (${item.key})');
    final controller = TextEditingController(text: item.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => _CleanDialog(
        title: 'Rename',
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: 'Enter new name',
            hintStyle: TextStyle(color: Colors.grey.shade400),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(
                color: Color(0xFF3B82F6),
                width: 1.5,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
          autofocus: true,
          onSubmitted: (val) => Navigator.pop(context, val),
        ),
        primaryLabel: 'Rename',
        onPrimary: () => Navigator.pop(context, controller.text),
      ),
    );

    print('[StorageScreen] Rename dialog returned: "$newName"');

    if (newName != null && newName.isNotEmpty && newName != item.name) {
      setState(() => _isLoading = true);
      try {
        if (_storageService != null) {
          print('[StorageScreen] Calling service.renameFile');
          await _storageService!.renameFile(item.key, newName);
          _showSuccess('Renamed successfully');
          await _loadFiles();
        }
      } catch (e) {
        print('[StorageScreen] Rename failed: $e');
        if (mounted) {
          _showError('Rename failed: $e');
        }
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _moveItem(StorageFile item) async {
    if (_storageService == null) return;

    print('[StorageScreen] Requested move for: ${item.name}');
    setState(() => _isLoading = true);

    List<Map<String, dynamic>> folders = [];
    try {
      folders = await _storageService!.getFolders();
    } catch (e) {
      folders = [
        {'key': '', 'name': 'Root'},
      ];
    }

    setState(() => _isLoading = false);

    final availableFolders = folders.where((f) {
      final folderKey = f['key'] as String;
      if (item.isFolder && folderKey.startsWith(item.key)) return false;
      return true;
    }).toList();

    if (!mounted) return;

    String? selectedFolder;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => _CleanDialog(
          title: 'Move to',
          content: Container(
            constraints: const BoxConstraints(maxHeight: 300, minWidth: 300),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: FolderTreeSelector(
              folders: availableFolders,
              initialSelection: selectedFolder,
              onSelect: (key) {
                setDialogState(() => selectedFolder = key);
              },
            ),
          ),
          primaryLabel: 'Move',
          primaryEnabled: selectedFolder != null,
          onPrimary: () => Navigator.pop(context, selectedFolder),
        ),
      ),
    );

    if (result != null) {
      // Check if moving to the same folder
      if (result == _currentPath) {
        return;
      }

      setState(() => _isLoading = true);
      try {
        await _storageService!.moveFile(item.key, result);
        _showSuccess('Moved successfully');
        await _loadFiles();
      } catch (e) {
        if (mounted) {
          _showError('Move failed: $e');
        }
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteItem(StorageFile item) async {
    print('[StorageScreen] Requested delete for: ${item.name}');
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => _CleanDialog(
        title: 'Delete ${item.isFolder ? 'folder' : 'file'}?',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete "${item.name}"?',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.grey.shade700,
              ),
            ),
            if (item.isFolder) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFFDC2626),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'All contents will be permanently deleted.',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFFDC2626),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        primaryLabel: 'Delete',
        primaryColor: const Color(0xFFDC2626),
        onPrimary: () => Navigator.pop(context, true),
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        if (_storageService != null) {
          if (item.isFolder) {
            await _storageService!.deleteFolder(item.key);
          } else {
            await _storageService!.deleteFile(item.key);
          }
          _showSuccess('Deleted successfully');
          await _loadFiles();
        }
      } catch (e) {
        if (mounted) {
          _showError('Delete failed: $e');
        }
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _downloadFile(StorageFile item) async {
    if (_storageService == null) return;

    try {
      final url = await _storageService!.getDownloadUrl(item.key);
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url));
      } else {
        throw 'Could not launch $url';
      }
    } catch (e) {
      if (mounted) {
        _showError('Download failed: $e');
      }
    }
  }

  Future<void> _onFileSelected(StorageFile item) async {
    if (item.isFolder) {
      _navigateToFolder(item.name);
      return;
    }

    setState(() {
      _previewFile = item;
      _isLoadingPreview = true;
      _previewUrl = null;
    });

    if (_storageService != null) {
      try {
        final url = await _storageService!.getDownloadUrl(item.key);
        if (mounted) {
          setState(() {
            _previewUrl = url;
            _isLoadingPreview = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoadingPreview = false;
          });
          // _showError('Failed to load preview');
        }
      }
    }
  }

  void _closePreview() {
    setState(() {
      _previewFile = null;
      _previewUrl = null;
    });
  }

  Widget _buildPreviewSidebar() {
    if (_previewFile == null) return const SizedBox.shrink();

    return Container(
      // width: 350, // Removed fixed width
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _previewFile!.name,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade900,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _closePreview,
                  color: Colors.grey.shade500,
                  splashRadius: 20,
                  tooltip: 'Close details',
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Preview Area
          Expanded(
            child: _isLoadingPreview
                ? const Center(child: CircularProgressIndicator())
                : _previewUrl == null
                ? const Center(child: Text('Preview not available'))
                : _buildFilePreview(
                    _previewFile!,
                    _previewUrl!,
                    headers: _storageService?.headers,
                  ),
          ),

          const Divider(height: 1),

          // Details
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Details',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade900,
                  ),
                ),
                const SizedBox(height: 12),
                _detailRow('Type', _previewFile!.extension.toUpperCase()),
                const SizedBox(height: 8),
                _detailRow('Size', _previewFile!.formattedSize),
                const SizedBox(height: 8),
                _detailRow(
                  'Modified',
                  _previewFile!.lastModified.toString().split('.')[0],
                ),
              ],
            ),
          ),

          // Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _downloadFile(_previewFile!),
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Download'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          // TODO: Rename
                          _renameItem(_previewFile!);
                        },
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Rename'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey.shade700,
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          _deleteItem(_previewFile!);
                          _closePreview();
                        },
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: Color(0xFFDC2626),
                        ),
                        label: const Text(
                          'Delete',
                          style: TextStyle(color: Color(0xFFDC2626)),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFDC2626),
                          alignment: Alignment.centerLeft,
                          side: BorderSide(
                            color: const Color(0xFFDC2626).withOpacity(0.3),
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilePreview(
    StorageFile file,
    String url, {
    Map<String, String>? headers,
  }) {
    final ext = file.extension;

    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) {
      return Container(
        color: const Color(0xFFF9FAFB),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Image.network(
            url,
            headers: headers,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const CircularProgressIndicator();
            },
            errorBuilder: (context, error, stackTrace) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.broken_image_rounded,
                  size: 48,
                  color: Colors.grey,
                ),
                const SizedBox(height: 8),
                Text(
                  'Could not load image',
                  style: TextStyle(color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ),
      );
    } else if (ext == 'pdf') {
      return HtmlWidget(
        '<iframe src="$url" style="width:100%; height:100%; border:none;"></iframe>',
      );
    } else if (['doc', 'docx'].contains(ext)) {
      final gdocUrl =
          'https://docs.google.com/gview?embedded=true&url=${Uri.encodeComponent(url)}';
      return HtmlWidget(
        '<iframe src="$gdocUrl" style="width:100%; height:100%; border:none;"></iframe>',
      );
    }

    return Container(
      color: const Color(0xFFF9FAFB),
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_getFileIcon(ext), size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'Preview not available',
            style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _downloadFile(file),
            child: const Text('Download to view'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade500),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.grey.shade800,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_companyId == null && !_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_off_outlined,
              size: 48,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            Text(
              'No company selected',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Column(
            children: [
              _buildHeader(),
              _buildToolbar(),
              if (_isLoading)
                const LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
                ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: _previewFile != null ? 1 : 10,
                      child: _buildContent(),
                    ),
                    if (_previewFile != null)
                      Expanded(flex: 1, child: _buildPreviewSidebar()),
                  ],
                ),
              ),
            ],
          ),
          if (_uploadTasks.isNotEmpty)
            Positioned(bottom: 16, right: 16, child: _buildUploadOverlay()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.folder_outlined,
              color: Colors.grey.shade700,
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            'Storage',
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade900,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                _ViewToggle(
                  icon: Icons.grid_view_rounded,
                  isActive: _isGridView,
                  onTap: () => setState(() => _isGridView = true),
                  isFirst: true,
                ),
                const SizedBox(width: 4),
                _ViewToggle(
                  icon: Icons.view_list_rounded,
                  isActive: !_isGridView,
                  onTap: () => setState(() => _isGridView = false),
                  isFirst: false,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: IconButton(
              icon: Icon(
                Icons.refresh_rounded,
                size: 20,
                color: Colors.grey.shade700,
              ),
              onPressed: _loadFiles,
              tooltip: 'Refresh',
              splashRadius: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _Breadcrumb(
                    text: 'Home',
                    isLast: _breadcrumbs.isEmpty,
                    onTap: _goHome,
                  ),
                  ..._breadcrumbs.asMap().entries.expand((entry) {
                    final index = entry.key;
                    final folder = entry.value;
                    final isLast = index == _breadcrumbs.length - 1;
                    return [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: Colors.grey.shade400,
                        ),
                      ),
                      _Breadcrumb(
                        text: folder,
                        isLast: isLast,
                        onTap: () => _jumpToBreadcrumb(index),
                      ),
                    ];
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(width: 20),
          OutlinedButton.icon(
            onPressed: _createFolder,
            icon: const Icon(Icons.create_new_folder_outlined, size: 18),
            label: const Text('New Folder'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey.shade700,
              side: BorderSide(color: Colors.grey.shade300),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              textStyle: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: _uploadFile,
            icon: const Icon(Icons.upload_file, size: 18),
            label: const Text('Upload'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              textStyle: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_files.isEmpty && !_isLoading) {
      return _buildEmptyState();
    }

    if (_isGridView) {
      return GridView.builder(
        padding: const EdgeInsets.all(24),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          childAspectRatio: 1.0, // Make items square
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: _files.length,
        itemBuilder: (context, index) {
          final item = _files[index];
          return _FileGridItem(
            item: item,
            isSelected: _previewFile?.key == item.key,
            onTap: () => _onFileSelected(item),
            onView: () => _onFileSelected(item),
            onRename: () => _renameItem(item),
            onMove: () => _moveItem(item),
            onDelete: () => _deleteItem(item),
            onDownload: () => _downloadFile(item),
          );
        },
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: _files.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: Colors.grey.shade200),
      itemBuilder: (context, index) {
        final item = _files[index];
        return _FileListItem(
          item: item,
          isSelected: _previewFile?.key == item.key,
          onTap: () => _onFileSelected(item),
          onView: () => _onFileSelected(item),
          onRename: () => _renameItem(item),
          onMove: () => _moveItem(item),
          onDelete: () => _deleteItem(item),
          onDownload: () => _downloadFile(item),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              Icons.folder_open_outlined,
              size: 56,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _currentPath.isEmpty ? 'No files yet' : 'This folder is empty',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Upload files or create folders to get started',
            style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: _createFolder,
                icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                label: const Text('New Folder'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey.shade700,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  side: BorderSide(color: Colors.grey.shade300),
                  textStyle: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _uploadFile,
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Upload Files'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                  textStyle: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUploadOverlay() {
    return Container(
      width: 320,
      constraints: BoxConstraints(maxHeight: _isUploadsMinimized ? 44 : 300),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: const Color(0xFF1F2937),
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(7),
              bottom: _isUploadsMinimized
                  ? const Radius.circular(7)
                  : Radius.zero,
            ),
            child: InkWell(
              onTap: () =>
                  setState(() => _isUploadsMinimized = !_isUploadsMinimized),
              borderRadius: BorderRadius.vertical(
                top: const Radius.circular(7),
                bottom: _isUploadsMinimized
                    ? const Radius.circular(7)
                    : Radius.zero,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.upload_file,
                      color: Colors.white70,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Uploads (${_uploadTasks.length})',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => setState(() => _uploadTasks.clear()),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white54,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      _isUploadsMinimized
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Colors.white54,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!_isUploadsMinimized)
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _uploadTasks.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: Colors.grey.shade100),
                itemBuilder: (context, index) {
                  final task = _uploadTasks[_uploadTasks.length - 1 - index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _getFileIcon(task.name),
                          size: 16,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            task.name,
                            style: GoogleFonts.inter(fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        _buildTaskStatus(task),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTaskStatus(UploadItem task) {
    switch (task.status) {
      case UploadStatus.uploading:
        return const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFF3B82F6),
          ),
        );
      case UploadStatus.success:
        return const Icon(
          Icons.check_circle,
          color: Color(0xFF059669),
          size: 16,
        );
      case UploadStatus.error:
        return Tooltip(
          message: task.errorMessage ?? 'Error',
          child: const Icon(Icons.error, color: Color(0xFFDC2626), size: 16),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  IconData _getFileIcon(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return Icons.image_outlined;
      case 'doc':
      case 'docx':
        return Icons.description_outlined;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }
}

class _CleanDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final String primaryLabel;
  final Color primaryColor;
  final bool primaryEnabled;
  final VoidCallback onPrimary;

  const _CleanDialog({
    required this.title,
    required this.content,
    required this.primaryLabel,
    this.primaryColor = const Color(0xFF3B82F6),
    this.primaryEnabled = true,
    required this.onPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ), // Square corners
      backgroundColor: Colors.white,
      elevation: 0, // Flat design
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: 300, // Smaller width
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 15, // Slightly smaller font
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade900,
              ),
            ),
            const SizedBox(height: 16),
            content,
            const SizedBox(height: 24), // More spacing for cleaner look
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey.shade500,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: const RoundedRectangleBorder(), // Square button
                  ),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  // Use TextButton for primary action too for minimal look, or a very flat ElevatedButton
                  onPressed: primaryEnabled ? onPrimary : null,
                  style: TextButton.styleFrom(
                    foregroundColor: primaryColor,
                    disabledForegroundColor: Colors.grey.shade300,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: const RoundedRectangleBorder(), // Square button
                    textStyle: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(primaryLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final bool isFirst;
  final VoidCallback onTap;

  const _ViewToggle({
    required this.icon,
    required this.isActive,
    required this.isFirst,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            size: 18,
            color: isActive ? const Color(0xFF3B82F6) : Colors.grey.shade500,
          ),
        ),
      ),
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  final String text;
  final bool isLast;
  final VoidCallback onTap;

  const _Breadcrumb({
    required this.text,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLast ? null : onTap,
        borderRadius: BorderRadius.circular(6),
        hoverColor: Colors.grey.shade100,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (text == 'Home')
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(
                    Icons.home_rounded,
                    size: 16,
                    color: isLast ? Colors.grey.shade700 : Colors.grey.shade500,
                  ),
                ),
              Text(
                text,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: isLast ? FontWeight.w600 : FontWeight.w500,
                  color: isLast ? Colors.grey.shade900 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileGridItem extends StatefulWidget {
  final StorageFile item;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onView;
  final VoidCallback onRename;
  final VoidCallback onMove;
  final VoidCallback onDelete;
  final VoidCallback onDownload;

  const _FileGridItem({
    required this.item,
    required this.isSelected,
    required this.onTap,
    required this.onView,
    required this.onRename,
    required this.onMove,
    required this.onDelete,
    required this.onDownload,
  });

  @override
  State<_FileGridItem> createState() => _FileGridItemState();
}

class _FileGridItemState extends State<_FileGridItem> {
  bool _isHovering = false;
  bool _isMenuOpen = false;
  final GlobalKey _menuKey = GlobalKey();

  Color _getFileColor(String ext) {
    switch (ext) {
      case 'pdf':
        return const Color(0xFFEF4444);
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return const Color(0xFF06B6D4);
      case 'doc':
      case 'docx':
        return const Color(0xFF3B82F6);
      case 'xls':
      case 'xlsx':
        return const Color(0xFF10B981);
      default:
        return const Color(0xFF6B7280);
    }
  }

  IconData _getFileIcon(String ext) {
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return Icons.image_outlined;
      case 'doc':
      case 'docx':
        return Icons.description_outlined;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  Future<void> _showMenu() async {
    setState(() => _isMenuOpen = true);
    try {
      final RenderBox button =
          _menuKey.currentContext!.findRenderObject()! as RenderBox;
      final RenderBox overlay =
          Navigator.of(context).overlay!.context.findRenderObject()!
              as RenderBox;
      final RelativeRect position = RelativeRect.fromRect(
        Rect.fromPoints(
          button.localToGlobal(Offset.zero, ancestor: overlay),
          button.localToGlobal(
            button.size.bottomRight(Offset.zero),
            ancestor: overlay,
          ),
        ),
        Offset.zero & overlay.size,
      );

      final isFolder = widget.item.isFolder;
      final value = await showMenu<String>(
        context: context,
        position: position,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 8,
        items: [
          if (!isFolder) ...[
            _menuItem('view', 'View', Icons.visibility_outlined),
            _menuItem('download', 'Download', Icons.download_outlined),
          ],
          _menuItem('rename', 'Rename', Icons.edit_outlined),
          _menuItem('move', 'Move to...', Icons.drive_file_move_outlined),
          const PopupMenuDivider(),
          _menuItem(
            'delete',
            'Delete',
            Icons.delete_outline,
            isDestructive: true,
          ),
        ],
      );

      if (value != null) {
        switch (value) {
          case 'view':
            widget.onView();
            break;
          case 'download':
            widget.onDownload();
            break;
          case 'rename':
            widget.onRename();
            break;
          case 'move':
            widget.onMove();
            break;
          case 'delete':
            widget.onDelete();
            break;
        }
      }
    } catch (e) {
      print('Error showing menu: $e');
    } finally {
      if (mounted) setState(() => _isMenuOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFolder = widget.item.isFolder;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: widget.isSelected
              ? const Color(0xFFEFF6FF)
              : (_isHovering || _isMenuOpen)
              ? const Color(0xFFFAFAFA)
              : Colors.white,
          borderRadius: BorderRadius.zero, // Square
          border: Border.all(
            color: widget.isSelected
                ? const Color(0xFF3B82F6)
                : _isHovering
                ? Colors.grey.shade300
                : Colors.grey.shade200,
            width: 1, // Consistent width
          ),
          boxShadow: _isHovering || widget.isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onTap,
                onDoubleTap: widget.item.isFolder ? null : widget.onView,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isFolder
                              ? const Color(0xFFFEF3C7)
                              : _getFileColor(
                                  widget.item.extension,
                                ).withOpacity(0.1),
                          borderRadius:
                              BorderRadius.zero, // Square internal icon
                        ),
                        child: Icon(
                          isFolder
                              ? Icons.folder_rounded
                              : _getFileIcon(widget.item.extension),
                          size: 32,
                          color: isFolder
                              ? const Color(0xFFF59E0B)
                              : _getFileColor(widget.item.extension),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.item.name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      if (!isFolder)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            widget.item.formattedSize,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
            ),
            if (_isHovering || widget.isSelected || _isMenuOpen)
              Positioned(
                top: 6,
                right: 6,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      key: _menuKey,
                      icon: Icon(
                        Icons.more_horiz,
                        size: 16,
                        color: Colors.grey.shade700,
                      ),
                      tooltip: 'More options',
                      splashRadius: 16,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      onPressed: _showMenu,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
    String value,
    String label,
    IconData icon, {
    bool isDestructive = false,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 36,
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: isDestructive
                ? const Color(0xFFDC2626)
                : Colors.grey.shade600,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: isDestructive
                  ? const Color(0xFFDC2626)
                  : Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }
}

class _FileListItem extends StatefulWidget {
  final StorageFile item;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onView;
  final VoidCallback onRename;
  final VoidCallback onMove;
  final VoidCallback onDelete;
  final VoidCallback onDownload;

  const _FileListItem({
    required this.item,
    required this.isSelected,
    required this.onTap,
    required this.onView,
    required this.onRename,
    required this.onMove,
    required this.onDelete,
    required this.onDownload,
  });

  @override
  State<_FileListItem> createState() => _FileListItemState();
}

class _FileListItemState extends State<_FileListItem> {
  bool _isHovering = false;
  bool _isMenuOpen = false;
  final GlobalKey _menuKey = GlobalKey();

  Color _getFileColor(String ext) {
    switch (ext) {
      case 'pdf':
        return const Color(0xFFEF4444);
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return const Color(0xFF06B6D4);
      case 'doc':
      case 'docx':
        return const Color(0xFF3B82F6);
      case 'xls':
      case 'xlsx':
        return const Color(0xFF10B981);
      default:
        return const Color(0xFF6B7280);
    }
  }

  IconData _getFileIcon(String ext) {
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return Icons.image_outlined;
      case 'doc':
      case 'docx':
        return Icons.description_outlined;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  Future<void> _showMenu() async {
    setState(() => _isMenuOpen = true);
    try {
      final RenderBox button =
          _menuKey.currentContext!.findRenderObject()! as RenderBox;
      final RenderBox overlay =
          Navigator.of(context).overlay!.context.findRenderObject()!
              as RenderBox;
      final RelativeRect position = RelativeRect.fromRect(
        Rect.fromPoints(
          button.localToGlobal(Offset.zero, ancestor: overlay),
          button.localToGlobal(
            button.size.bottomRight(Offset.zero),
            ancestor: overlay,
          ),
        ),
        Offset.zero & overlay.size,
      );

      final isFolder = widget.item.isFolder;
      final value = await showMenu<String>(
        context: context,
        position: position,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 8,
        items: [
          if (!isFolder) ...[
            _menuItem('view', 'View', Icons.visibility_outlined),
            _menuItem('download', 'Download', Icons.download_outlined),
          ],
          _menuItem('rename', 'Rename', Icons.edit_outlined),
          _menuItem('move', 'Move to...', Icons.drive_file_move_outlined),
          const PopupMenuDivider(),
          _menuItem(
            'delete',
            'Delete',
            Icons.delete_outline,
            isDestructive: true,
          ),
        ],
      );

      if (value != null) {
        switch (value) {
          case 'view':
            widget.onView();
            break;
          case 'download':
            widget.onDownload();
            break;
          case 'rename':
            widget.onRename();
            break;
          case 'move':
            widget.onMove();
            break;
          case 'delete':
            widget.onDelete();
            break;
        }
      }
    } catch (e) {
      print('Error showing menu: $e');
    } finally {
      if (mounted) setState(() => _isMenuOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFolder = widget.item.isFolder;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: widget.isSelected
              ? const Color(0xFFEFF6FF)
              : (_isHovering || _isMenuOpen)
              ? const Color(0xFFFAFAFA)
              : Colors.white,
          borderRadius: BorderRadius.zero, // Square list item
          border: Border.all(
            color: widget.isSelected
                ? const Color(0xFF3B82F6)
                : _isHovering
                ? Colors.grey.shade200
                : Colors.transparent,
            width: 1, // Consistent width
          ),
        ),
        child: Row(
          children: [
            // Content handling tap
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onTap,
                onDoubleTap: widget.item.isFolder ? null : widget.onView,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isFolder
                            ? const Color(0xFFFEF3C7)
                            : _getFileColor(
                                widget.item.extension,
                              ).withOpacity(0.1),
                        borderRadius:
                            BorderRadius.zero, // Square internal icon list
                      ),
                      child: Icon(
                        isFolder
                            ? Icons.folder_rounded
                            : _getFileIcon(widget.item.extension),
                        size: 20,
                        color: isFolder
                            ? const Color(0xFFF59E0B)
                            : _getFileColor(widget.item.extension),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        widget.item.name,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!isFolder)
                      Text(
                        widget.item.formattedSize,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Actions (independent)
            const SizedBox(width: 8),
            if (!isFolder)
              IconButton(
                icon: Icon(
                  Icons.download_outlined,
                  size: 16,
                  color: Colors.grey.shade500,
                ),
                onPressed: widget.onDownload,
                splashRadius: 16,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            IconButton(
              key: _menuKey,
              tooltip: 'More options',
              icon: Icon(
                Icons.more_horiz,
                size: 18,
                color: Colors.grey.shade600,
              ),
              iconSize: 18,
              splashRadius: 18,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: _showMenu,
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
    String value,
    String label,
    IconData icon, {
    bool isDestructive = false,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 36,
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: isDestructive
                ? const Color(0xFFDC2626)
                : Colors.grey.shade600,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: isDestructive
                  ? const Color(0xFFDC2626)
                  : Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }
}
