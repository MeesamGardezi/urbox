import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/storage_model.dart';
import '../services/storage_service.dart';
import '../../auth/services/auth_service.dart';

/// Storage Screen
///
/// File browser interface with folder navigation, upload, and file management
class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  StorageService? _storageService;
  List<StorageFile> _files = [];
  bool _isLoading = true;
  String _currentPath = ''; // e.g. "folder1/subfolder/"
  String? _companyId;

  List<UploadItem> _uploadTasks = [];
  bool _isUploadsMinimized = false;

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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading profile: $e')));
      }
    }
  }

  Future<void> _loadFiles() async {
    if (_storageService == null) return;

    setState(() => _isLoading = true);
    try {
      final files = await _storageService!.listFiles(prefix: _currentPath);
      // Sort: Folders first, then files alphabetically
      files.sort((a, b) {
        if (a.isFolder && !b.isFolder) return -1;
        if (!a.isFolder && b.isFolder) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      setState(() {
        _files = files;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading files: $e')));
      }
    }
  }

  Future<void> _uploadFile() async {
    if (_storageService == null) return;

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        withData: true, // Needed for web
        allowMultiple: true,
      );

      if (result != null) {
        // Expand overlay if hidden
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

          // Start upload without blocking UI
          _performUpload(task, file);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Pick file failed: $e')));
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
      builder: (context) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Folder Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      setState(() => _isLoading = true);
      try {
        if (_storageService != null) {
          final newFolderPath = _currentPath + name;
          await _storageService!.createFolder(newFolderPath);
          await _loadFiles();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Create folder failed: $e')));
        }
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteItem(StorageFile item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${item.isFolder ? 'Folder' : 'File'}?'),
        content: Text(
          'Are you sure you want to delete "${item.name}"? ${item.isFolder ? "\nThis will delete all contents." : ""}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
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
          await _loadFiles();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    }
  }

  void _navigateToFolder(String folderName) {
    setState(() {
      _currentPath += '$folderName/';
      _isLoading = true;
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
    });
    _loadFiles();
  }

  @override
  Widget build(BuildContext context) {
    if (_companyId == null && !_isLoading) {
      return const Center(child: Text('No company selected'));
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'Storage',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black54),
            onPressed: _loadFiles,
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Loading Indicator
              if (_isLoading)
                const LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
                ),

              // Toolbar / Breadcrumbs
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: Colors.black12)),
                ),
                child: Row(
                  children: [
                    // Breadcrumbs
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _BreadcrumbItem(
                              text: 'Home',
                              isLast: _breadcrumbs.isEmpty,
                              onTap: () {
                                if (_currentPath.isNotEmpty) {
                                  setState(() {
                                    _currentPath = '';
                                    _isLoading = true;
                                  });
                                  _loadFiles();
                                }
                              },
                            ),
                            if (_breadcrumbs.isNotEmpty)
                              const Icon(
                                Icons.chevron_right,
                                size: 16,
                                color: Colors.black38,
                              ),
                            ..._breadcrumbs.asMap().entries.map((entry) {
                              final index = entry.key;
                              final folder = entry.value;
                              final isLast = index == _breadcrumbs.length - 1;
                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _BreadcrumbItem(
                                    text: folder,
                                    isLast: isLast,
                                    onTap: () => _jumpToBreadcrumb(index),
                                  ),
                                  if (!isLast)
                                    const Icon(
                                      Icons.chevron_right,
                                      size: 16,
                                      color: Colors.black38,
                                    ),
                                ],
                              );
                            }),
                          ],
                        ),
                      ),
                    ),

                    // Actions
                    ElevatedButton.icon(
                      onPressed: _createFolder,
                      icon: const Icon(
                        Icons.create_new_folder_outlined,
                        size: 18,
                      ),
                      label: const Text('New Folder'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                        elevation: 0,
                        side: const BorderSide(color: Colors.black12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _uploadFile,
                      icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                      label: const Text('Upload'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: _files.isEmpty && !_isLoading
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.folder_open,
                              size: 64,
                              color: Colors.grey[300],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'This folder is empty',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(24),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 200,
                              childAspectRatio: 0.85,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                            ),
                        itemCount: _files.length,
                        itemBuilder: (context, index) {
                          final item = _files[index];
                          return _FileCard(
                            item: item,
                            onTap: () {
                              if (item.isFolder) {
                                _navigateToFolder(item.name);
                              } else {
                                _downloadFile(item);
                              }
                            },
                            onDelete: () => _deleteItem(item),
                            onDownload: () => _downloadFile(item),
                          );
                        },
                      ),
              ),
            ],
          ),

          // Uploads Overlay
          if (_uploadTasks.isNotEmpty)
            Positioned(
              bottom: 24,
              right: 24,
              child: _buildUploadQueueOverlay(),
            ),
        ],
      ),
    );
  }

  Widget _buildUploadQueueOverlay() {
    return Container(
      width: 320,
      constraints: BoxConstraints(maxHeight: _isUploadsMinimized ? 48 : 400),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Material(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(8),
              bottom: _isUploadsMinimized
                  ? const Radius.circular(8)
                  : Radius.zero,
            ),
            child: InkWell(
              onTap: () =>
                  setState(() => _isUploadsMinimized = !_isUploadsMinimized),
              borderRadius: BorderRadius.vertical(
                top: const Radius.circular(8),
                bottom: _isUploadsMinimized
                    ? const Radius.circular(8)
                    : Radius.zero,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Text(
                      'Uploads',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: () => setState(() => _uploadTasks.clear()),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white70,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      _isUploadsMinimized
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Colors.white70,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // List
          if (!_isUploadsMinimized)
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.all(0),
                itemCount: _uploadTasks.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: Colors.black12),
                itemBuilder: (context, index) {
                  final task = _uploadTasks[_uploadTasks.length - 1 - index];

                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _getFileIcon(task.name),
                          size: 20,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            task.name,
                            style: const TextStyle(fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 12),
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
    if (task.status == UploadStatus.uploading) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (task.status == UploadStatus.success) {
      return const Icon(Icons.check_circle, color: Colors.green, size: 18);
    } else {
      return Tooltip(
        message: task.errorMessage ?? 'Error',
        child: const Icon(Icons.error, color: Colors.red, size: 18),
      );
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
        return Icons.image;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      case 'mp3':
      case 'wav':
      case 'aac':
        return Icons.audio_file;
      case 'mp4':
      case 'mov':
      case 'avi':
        return Icons.video_file;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip;
      default:
        return Icons.insert_drive_file;
    }
  }
}

/// Breadcrumb navigation item
class _BreadcrumbItem extends StatelessWidget {
  final String text;
  final bool isLast;
  final VoidCallback onTap;

  const _BreadcrumbItem({
    required this.text,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isLast ? null : onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          text,
          style: GoogleFonts.inter(
            fontWeight: isLast ? FontWeight.w600 : FontWeight.normal,
            color: isLast ? Colors.black87 : Colors.black54,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

/// File card widget with hover effects
class _FileCard extends StatefulWidget {
  final StorageFile item;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onDownload;

  const _FileCard({
    required this.item,
    required this.onTap,
    required this.onDelete,
    required this.onDownload,
  });

  @override
  State<_FileCard> createState() => _FileCardState();
}

class _FileCardState extends State<_FileCard> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final isFolder = widget.item.isFolder;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isHovering
                  ? const Color(0xFF2563EB).withOpacity(0.5)
                  : Colors.black12,
              width: _isHovering ? 1.5 : 1,
            ),
            boxShadow: _isHovering
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: Stack(
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 16),
                  Center(
                    child: Icon(
                      isFolder ? Icons.folder : _getFileIcon(widget.item.name),
                      size: 64,
                      color: isFolder
                          ? const Color(0xFFFFCA28)
                          : _getFileColor(widget.item.extension),
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Text(
                      widget.item.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  if (!isFolder)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Text(
                        widget.item.formattedSize,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Colors.black45,
                        ),
                      ),
                    ),
                ],
              ),
              // Hover actions
              if (_isHovering)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Row(
                    children: [
                      _ActionButton(
                        icon: Icons.download_rounded,
                        onTap: widget.onDownload,
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 4),
                      _ActionButton(
                        icon: Icons.delete_outline_rounded,
                        onTap: widget.onDelete,
                        color: Colors.red,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
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
        return Icons.image;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      case 'mp3':
      case 'wav':
      case 'aac':
        return Icons.audio_file;
      case 'mp4':
      case 'mov':
      case 'avi':
        return Icons.video_file;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileColor(String ext) {
    switch (ext) {
      case 'pdf':
        return Colors.red;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return Colors.teal;
      case 'doc':
      case 'docx':
        return Colors.blue;
      case 'xls':
      case 'xlsx':
        return Colors.green;
      case 'ppt':
      case 'pptx':
        return Colors.orange;
      case 'mp3':
      case 'wav':
      case 'aac':
        return Colors.purple;
      case 'mp4':
      case 'mov':
      case 'avi':
        return Colors.pink;
      case 'zip':
      case 'rar':
      case '7z':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }
}

/// Small action button for file cards
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const _ActionButton({
    required this.icon,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.black12),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}
