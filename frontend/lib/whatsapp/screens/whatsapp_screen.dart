import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/whatsapp_model.dart';
import '../services/whatsapp_service.dart';
import '../../auth/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import 'dart:async';

/// WhatsApp Integration Screen
///
/// Clean, simple UI inspired by shared_mailbooox design with Messages tab
class WhatsAppScreen extends StatefulWidget {
  const WhatsAppScreen({Key? key}) : super(key: key);

  @override
  State<WhatsAppScreen> createState() => _WhatsAppScreenState();
}

class _WhatsAppScreenState extends State<WhatsAppScreen>
    with SingleTickerProviderStateMixin {
  final _whatsappService = WhatsAppService();

  String? _userId;
  String? _companyId;
  WhatsAppSessionStatus? _status;
  String? _qrCode;
  List<WhatsAppGroup> _availableGroups = [];
  List<WhatsAppGroup> _monitoredGroups = [];
  List<WhatsAppMessage> _messages = [];

  bool _isLoading = false;
  bool _isConnecting = false;
  bool _isCancelling = false;
  Timer? _pollTimer;
  Timer? _qrCountdownTimer;
  int _qrSecondsRemaining = 120;

  // Tab controller for Messages
  late TabController _tabController;
  int _selectedTab = 0; // 0: Connection, 1: Messages

  // Search & Filter State
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String? _searchQuery;
  String? _selectedGroupId;
  bool _hasMoreMessages = false;
  String? _lastDocId;
  bool _isLoadingMore = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _selectedTab = _tabController.index);
      }
    });

    _scrollController.addListener(_onScroll);

    _loadUserData();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _qrCountdownTimer?.cancel();
    _debounceTimer?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMoreMessages) {
      _loadMoreMessages();
    }
  }

  void _onSearchChanged(String value) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      setState(() {
        _searchQuery = value.trim().isEmpty ? null : value.trim();
        _messages.clear(); // Clear existing to reload
        _lastDocId = null;
      });
      _loadMessages();
    });
  }

  void _onGroupFilterChanged(String? groupId) {
    setState(() {
      _selectedGroupId = groupId;
      _messages.clear();
      _lastDocId = null;
    });
    _loadMessages();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userResponse = await AuthService.getUserProfile(user.uid);

      if (userResponse['success'] != true) {
        throw Exception(userResponse['error'] ?? 'Failed to load user profile');
      }

      final userData = userResponse['user'] as Map<String, dynamic>;

      setState(() {
        _userId = user.uid;
        _companyId = userData['companyId'] as String?;
      });

      await _refreshStatus();
    } catch (e) {
      print('Error loading user data: $e');
    }
  }

  Future<void> _refreshStatus() async {
    if (_userId == null) return;

    try {
      final status = await _whatsappService.getStatus(_userId!);

      setState(() {
        _status = status;
      });

      // If connected, load groups and messages
      if (status.isConnected) {
        await _loadMonitoredGroups();
        await _loadMessages();
      }
    } catch (e) {
      print('Error refreshing status: $e');
    }
  }

  Future<void> _connect() async {
    if (_userId == null || _companyId == null) {
      _showError('User not logged in');
      return;
    }

    setState(() {
      _isConnecting = true;
      _isLoading = true;
    });

    try {
      final result = await _whatsappService.connect(_userId!, _companyId!);

      if (result['success'] == true) {
        _startPolling();
        _showSuccess(result['message'] ?? 'Connection started');
      } else {
        _showError(result['error'] ?? 'Failed to start WhatsApp connection');
        setState(() {
          _isConnecting = false;
        });
      }
    } catch (e) {
      _showError('Error connecting: $e');
      setState(() {
        _isConnecting = false;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _qrCountdownTimer?.cancel();

    // Reset countdown
    setState(() {
      _qrSecondsRemaining = 120;
    });

    // Start countdown timer
    _qrCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !_isConnecting) {
        timer.cancel();
        return;
      }

      setState(() {
        _qrSecondsRemaining--;
      });

      if (_qrSecondsRemaining <= 0) {
        timer.cancel();
        _handleTimeout();
      }
    });

    // Poll every 2 seconds for status updates
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted || !_isConnecting) {
        timer.cancel();
        return;
      }

      await _refreshStatus();

      // If QR pending, fetch QR code
      if (_status?.needsQr == true) {
        final qr = await _whatsappService.getQrCode(_userId!);
        if (mounted) {
          setState(() {
            _qrCode = qr;
          });
        }
      } else {
        if (_qrCode != null && mounted) {
          setState(() {
            _qrCode = null;
          });
        }
      }

      // Stop polling if connected or error
      if (_status?.isConnected == true || _status?.hasError == true) {
        timer.cancel();
        _qrCountdownTimer?.cancel();
        setState(() {
          _isConnecting = false;
        });

        if (_status?.isConnected == true) {
          _showSuccess('WhatsApp connected successfully!');
          await _loadAvailableGroups();
        }
      }
    });
  }

  void _handleTimeout() {
    _pollTimer?.cancel();
    _qrCountdownTimer?.cancel();

    if (!mounted) return;

    setState(() {
      _isConnecting = false;
      _qrCode = null;
    });

    _whatsappService.cancelConnection(_userId!);
    _showError('Connection timeout. Please try again.');
  }

  Future<void> _cancelConnection() async {
    if (_userId == null || _isCancelling) return;

    setState(() => _isCancelling = true);

    try {
      _pollTimer?.cancel();
      _qrCountdownTimer?.cancel();

      await _whatsappService.cancelConnection(_userId!);
      await _refreshStatus();

      setState(() {
        _isConnecting = false;
        _qrCode = null;
      });

      _showSuccess('Connection cancelled');
    } catch (e) {
      _showError('Error cancelling: $e');
    } finally {
      setState(() => _isCancelling = false);
    }
  }

  Future<void> _disconnect() async {
    if (_userId == null) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Disconnect WhatsApp?'),
        content: const Text(
          'You will need to scan the QR code again to reconnect. Your monitored groups will be preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      await _whatsappService.disconnect(_userId!, deleteAuth: true);
      await _refreshStatus();

      setState(() {
        _availableGroups = [];
        _monitoredGroups = [];
        _messages = [];
        _qrCode = null;
      });

      _showSuccess('WhatsApp disconnected');
    } catch (e) {
      _showError('Error disconnecting: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadAvailableGroups() async {
    if (_userId == null) return;

    try {
      final groups = await _whatsappService.getGroups(_userId!);
      setState(() {
        _availableGroups = groups;
      });
    } catch (e) {
      print('Error loading groups: $e');
    }
  }

  Future<void> _loadMonitoredGroups() async {
    if (_userId == null) return;

    try {
      final groups = await _whatsappService.getMonitoredGroups(_userId!);
      setState(() {
        _monitoredGroups = groups;
      });
    } catch (e) {
      print('Error loading monitored groups: $e');
    }
  }

  Future<void> _loadMessages({bool loadMore = false}) async {
    if (_userId == null) return;
    if (loadMore && (_isLoadingMore || !_hasMoreMessages)) return;

    if (!loadMore) {
      setState(() => _isLoading = true);
    } else {
      setState(() => _isLoadingMore = true);
    }

    try {
      final result = await _whatsappService.getMessages(
        userId: _userId!,
        limit: 20,
        startAfter: loadMore ? _lastDocId : null,
        groupId: _selectedGroupId,
        searchQuery: _searchQuery,
        forceRefresh:
            !loadMore, // Force refresh on initial load/filter change, but use cache/pagination for subsequent
      );

      final newMessages = result['messages'] as List<WhatsAppMessage>;
      final hasMore = result['hasMore'] as bool;
      final lastDocId = result['lastDocId'] as String?;

      if (mounted) {
        setState(() {
          if (loadMore) {
            _messages.addAll(newMessages);
          } else {
            _messages = newMessages;
          }
          _hasMoreMessages = hasMore;
          _lastDocId = lastDocId;
        });
      }
    } catch (e) {
      print('Error loading messages: $e');
      if (mounted && !loadMore) {
        _showError('Failed to load messages');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMoreMessages() async {
    await _loadMessages(loadMore: true);
  }

  Future<void> _toggleGroupMonitoring(WhatsAppGroup group) async {
    if (_userId == null || _companyId == null) return;

    setState(() => _isLoading = true);

    try {
      final newStatus = !group.isMonitored;

      await _whatsappService.toggleMonitoring(
        userId: _userId!,
        companyId: _companyId!,
        groupId: group.id,
        groupName: group.name,
        isMonitoring: newStatus,
      );

      await _loadMonitoredGroups();
      await _loadAvailableGroups();

      _showSuccess(
        newStatus
            ? 'Now monitoring ${group.name}'
            : 'Stopped monitoring ${group.name}',
      );
    } catch (e) {
      _showError('Error updating group: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0F172A)
          : const Color(0xFFF8FAFC),
      body: _status?.isConnected == true
          ? Column(
              children: [
                const SizedBox(height: 16),
                // Custom Premium Tab Selector
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildCustomTab(
                            index: 0,
                            title: 'Connection',
                            icon: Icons.link,
                            isDark: isDark,
                          ),
                        ),
                        Expanded(
                          child: _buildCustomTab(
                            index: 1,
                            title: 'Messages',
                            icon: Icons.message_outlined,
                            isDark: isDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    physics: const BouncingScrollPhysics(),
                    children: [
                      _buildConnectionPage(isDark),
                      _buildMessagesTab(isDark),
                    ],
                  ),
                ),
              ],
            )
          : _buildConnectionPage(isDark),
    );
  }

  Widget _buildCustomTab({
    required int index,
    required String title,
    required IconData icon,
    required bool isDark,
  }) {
    final isSelected = _selectedTab == index;
    final primaryColor = const Color(0xFF128C7E);

    return GestureDetector(
      onTap: () {
        _tabController.animateTo(index);
        setState(() => _selectedTab = index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: primaryColor.withOpacity(0.3), width: 1)
              : Border.all(color: Colors.transparent),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected
                  ? primaryColor
                  : (isDark ? Colors.grey.shade500 : Colors.grey.shade400),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? primaryColor
                    : (isDark ? Colors.grey.shade500 : Colors.grey.shade400),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionPage(bool isDark) {
    return RefreshIndicator(
      onRefresh: _refreshStatus,
      color: const Color(0xFF128C7E),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(isDark),
            const SizedBox(height: 24),
            _buildConnectionCard(isDark),
            if (_status?.isConnected == true) ...[
              const SizedBox(height: 24),
              _buildConnectedInfoCard(isDark),
              const SizedBox(height: 24),
              _buildMonitoredGroupsSection(isDark),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF128C7E).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.chat, color: Color(0xFF128C7E), size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WhatsApp Integration',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                ),
              ),
              Text(
                'Connect your WhatsApp to monitor group messages',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildStatusIndicator(isDark),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getStatusTitle(),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getStatusSubtitle(),
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              _buildActionButton(isDark),
            ],
          ),
          if (_isConnecting && _status?.needsQr == true) ...[
            const SizedBox(height: 24),
            _buildQrCodeSection(isDark),
          ],
          if (_status?.hasError == true && _status?.error != null) ...[
            const SizedBox(height: 16),
            _buildErrorMessage(isDark),
          ],
          if (_isConnecting && _status?.needsQr != true) ...[
            const SizedBox(height: 16),
            _buildLoadingProgress(isDark),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(bool isDark) {
    Color color;
    IconData icon;
    bool isPulsing = false;

    if (_status?.isConnected == true) {
      color = Colors.green;
      icon = Icons.check_circle;
    } else if (_isConnecting) {
      if (_status?.needsQr == true) {
        color = const Color(0xFF128C7E);
        icon = Icons.qr_code_2;
      } else {
        color = Colors.blue;
        icon = Icons.sync;
        isPulsing = true;
      }
    } else if (_status?.hasError == true) {
      color = Colors.red;
      icon = Icons.error;
    } else {
      color = Colors.grey;
      icon = Icons.power_off;
    }

    Widget indicator = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 28),
    );

    if (isPulsing) {
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.8, end: 1.0),
        duration: const Duration(milliseconds: 800),
        builder: (context, value, child) {
          return Transform.scale(scale: value, child: child);
        },
        onEnd: () => setState(() {}),
        child: indicator,
      );
    }

    return indicator;
  }

  String _getStatusTitle() {
    if (_status?.isConnected == true) {
      return 'Connected';
    } else if (_isConnecting) {
      if (_status?.needsQr == true) {
        return 'Scan QR Code';
      } else if (_status?.status == 'authenticating') {
        return 'Authenticating...';
      }
      return 'Initializing...';
    } else if (_status?.hasError == true) {
      return 'Connection Error';
    }
    return 'Not Connected';
  }

  String _getStatusSubtitle() {
    if (_status?.isConnected == true) {
      if (_status?.phone != null) {
        return 'Connected as +${_status!.phone}';
      }
      return 'WhatsApp is connected and ready';
    } else if (_isConnecting) {
      if (_status?.needsQr == true) {
        return 'Open WhatsApp on your phone and scan the code';
      } else if (_status?.status == 'authenticating') {
        return 'Verifying your session...';
      }
      return 'Starting WhatsApp session...';
    } else if (_status?.hasError == true) {
      return _status?.error ?? 'Something went wrong';
    }
    return 'Connect to start monitoring messages';
  }

  Widget _buildActionButton(bool isDark) {
    if (_status?.isConnected == true) {
      return ElevatedButton.icon(
        onPressed: () => _disconnect(),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red.shade50,
          foregroundColor: Colors.red,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: const Icon(Icons.power_off, size: 18),
        label: const Text('Disconnect'),
      );
    }

    if (_isConnecting) {
      return OutlinedButton(
        onPressed: _isCancelling ? null : _cancelConnection,
        style: OutlinedButton.styleFrom(
          foregroundColor: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isCancelling
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Cancel'),
      );
    }

    if (_status?.hasError == true) {
      return ElevatedButton.icon(
        onPressed: _connect,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF128C7E),
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: const Icon(Icons.refresh, size: 18),
        label: const Text('Try Again'),
      );
    }

    // Disconnected state
    return ElevatedButton.icon(
      onPressed: _isLoading ? null : _connect,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF128C7E),
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: _isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.power_settings_new, size: 18),
      label: Text(_isLoading ? 'Starting...' : 'Connect'),
    );
  }

  Widget _buildQrCodeSection(bool isDark) {
    return Center(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF128C7E), width: 2),
            ),
            child: _qrCode != null && _qrCode!.isNotEmpty
                ? QrImageView(
                    data: _qrCode!,
                    version: QrVersions.auto,
                    size: 240.0,
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.H,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Color(0xFF128C7E),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Color(0xFF075E54),
                    ),
                  )
                : const SizedBox(
                    width: 240,
                    height: 240,
                    child: Center(child: CircularProgressIndicator()),
                  ),
          ),
          const SizedBox(height: 16),
          _buildQrCountdown(isDark),
          const SizedBox(height: 12),
          Text(
            'Open WhatsApp → Linked Devices → Link a Device',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrCountdown(bool isDark) {
    final minutes = _qrSecondsRemaining ~/ 60;
    final seconds = _qrSecondsRemaining % 60;
    final isExpiring = _qrSecondsRemaining < 30;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isExpiring
            ? Colors.orange.shade50
            : (isDark ? const Color(0xFF334155) : Colors.grey.shade100),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer_outlined,
            size: 16,
            color: isExpiring
                ? Colors.orange
                : (isDark ? Colors.grey.shade300 : Colors.grey.shade700),
          ),
          const SizedBox(width: 6),
          Text(
            'Expires in ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isExpiring
                  ? Colors.orange.shade800
                  : (isDark ? Colors.grey.shade300 : Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorMessage(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _status?.error ?? 'An error occurred',
              style: TextStyle(color: Colors.red.shade800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingProgress(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1E40AF).withOpacity(0.2)
            : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _status?.status == 'authenticating'
                  ? 'Verifying your session...'
                  : 'Starting WhatsApp...',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.blue.shade200 : Colors.blue.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectedInfoCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Account Information',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoRow(
            Icons.phone,
            'Phone Number',
            '+${_status?.phone ?? 'Unknown'}',
            isDark,
          ),
          Divider(height: 24, color: isDark ? Colors.grey.shade700 : null),
          _buildInfoRow(
            Icons.person,
            'Account Name',
            _status?.name ?? 'Unknown',
            isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, bool isDark) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF128C7E).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFF128C7E), size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMonitoredGroupsSection(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Monitored Groups',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _showManageGroupsDialog(isDark),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF128C7E),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.settings, size: 16),
                label: const Text('Manage'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_monitoredGroups.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.group_off_outlined,
                      size: 48,
                      color: isDark
                          ? Colors.grey.shade600
                          : Colors.grey.shade300,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No groups monitored',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Click Manage to select groups to monitor',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.grey.shade500
                            : Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              children: _monitoredGroups.map((group) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(
                      0xFF128C7E,
                    ).withOpacity(isDark ? 0.1 : 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF128C7E).withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF128C7E).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.groups,
                          color: Color(0xFF128C7E),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          group.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF1E293B),
                          ),
                        ),
                      ),
                      Icon(
                        Icons.check_circle,
                        color: Colors.green.shade400,
                        size: 20,
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  void _showManageGroupsDialog(bool isDark) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Manage Groups',
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF1E293B),
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: FutureBuilder(
            future: _loadAvailableGroups(),
            builder: (context, snapshot) {
              if (_availableGroups.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.groups_outlined,
                        size: 48,
                        color: isDark
                            ? Colors.grey.shade600
                            : Colors.grey.shade400,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No groups available',
                        style: TextStyle(
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () async {
                          await _loadAvailableGroups();
                          setState(() {});
                        },
                        child: const Text('Refresh'),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                itemCount: _availableGroups.length,
                itemBuilder: (context, index) {
                  final group = _availableGroups[index];
                  final isMonitored = _monitoredGroups.any(
                    (g) => g.id == group.id,
                  );

                  return ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isMonitored
                            ? Colors.green.withOpacity(0.1)
                            : const Color(0xFF128C7E).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isMonitored ? Icons.check_circle : Icons.group,
                        color: isMonitored
                            ? Colors.green
                            : const Color(0xFF128C7E),
                        size: 20,
                      ),
                    ),
                    title: Text(
                      group.name,
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                      ),
                    ),
                    subtitle: Text(
                      '${group.participantCount ?? 0} participants',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                    trailing: Switch(
                      value: isMonitored,
                      activeColor: const Color(0xFF128C7E),
                      onChanged: (value) async {
                        await _toggleGroupMonitoring(group);
                        if (context.mounted) {
                          Navigator.pop(context);
                          _showManageGroupsDialog(isDark);
                        }
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesTab(bool isDark) {
    return Column(
      children: [
        // Search and Filter Header
        Container(
          padding: const EdgeInsets.all(16),
          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
          child: Row(
            children: [
              // Search Bar
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search messages...',
                    hintStyle: TextStyle(
                      color: isDark
                          ? Colors.grey.shade500
                          : Colors.grey.shade400,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: isDark
                          ? Colors.grey.shade500
                          : Colors.grey.shade400,
                    ),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 0,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Group Filter
              // Group Filter
              Expanded(
                flex: 1,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return DropdownMenu<String?>(
                      width: constraints.maxWidth,
                      initialSelection: _selectedGroupId,
                      onSelected: _onGroupFilterChanged,
                      dropdownMenuEntries: [
                        const DropdownMenuEntry<String?>(
                          value: null,
                          label: 'All Groups',
                        ),
                        ..._monitoredGroups.map((group) {
                          return DropdownMenuEntry<String?>(
                            value: group.id,
                            label: group.name,
                          );
                        }),
                      ],
                      inputDecorationTheme: InputDecorationTheme(
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF1E293B)
                            : Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        hintStyle: TextStyle(
                          fontSize: 14,
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                      ),
                      textStyle: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      menuStyle: MenuStyle(
                        backgroundColor: MaterialStateProperty.all(
                          isDark ? const Color(0xFF1E293B) : Colors.white,
                        ),
                        surfaceTintColor: MaterialStateProperty.all(
                          isDark ? const Color(0xFF1E293B) : Colors.white,
                        ),
                      ),
                      trailingIcon: Icon(
                        Icons.filter_list,
                        size: 20,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                      selectedTrailingIcon: Icon(
                        Icons.filter_list,
                        size: 20,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // Messages List
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              _messages.clear();
              _lastDocId = null;
              await _loadMessages(loadMore: false);
            },
            color: const Color(0xFF128C7E),
            child: _messages.isEmpty && !_isLoading
                ? SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Container(
                      height: 400,
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 64,
                            color: isDark
                                ? Colors.grey.shade600
                                : Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery != null
                                ? 'No matches found'
                                : 'No messages yet',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                            ),
                          ),
                          if (_searchQuery != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Try adjusting your search or filter',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark
                                    ? Colors.grey.shade500
                                    : Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: _messages.length + (_isLoadingMore ? 1 : 0),
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      if (index == _messages.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }

                      final message = _messages[index];

                      return Card(
                        elevation: 0,
                        color: isDark ? const Color(0xFF1E293B) : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isDark
                                ? Colors.grey.shade800
                                : Colors.grey.shade200,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Header: Group Name and Time
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.group,
                                          size: 14,
                                          color: Colors.grey.shade500,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            message.groupName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: isDark
                                                  ? Colors.grey.shade300
                                                  : Colors.grey.shade700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    _formatTime(message.timestamp),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              // Sender Info
                              Row(
                                children: [
                                  Text(
                                    message.isFromMe
                                        ? 'You'
                                        : message.senderName,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF128C7E),
                                    ),
                                  ),
                                  if (message.isFromMe) ...[
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.check_circle,
                                      size: 12,
                                      color: Colors.green.shade400,
                                    ),
                                  ],
                                ],
                              ),

                              const SizedBox(height: 4),

                              // Message Body / Media
                              if (message.hasMedia)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 4),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.black26
                                        : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.image,
                                        size: 14,
                                        color: Colors.grey.shade600,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '[${message.mediaType ?? "Media"}]',
                                        style: TextStyle(
                                          fontStyle: FontStyle.italic,
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                              if (message.body.isNotEmpty)
                                Text(
                                  message.body,
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.4,
                                    color: isDark
                                        ? Colors.grey.shade200
                                        : Colors.black87,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
