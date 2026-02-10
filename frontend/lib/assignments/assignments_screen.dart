import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import '../../core/theme/app_theme.dart';
import '../../core/models/team_member.dart';
import '../../auth/services/team_service.dart';
import 'data/models/assignment.dart';
import 'data/services/assignment_service.dart';
import 'widgets/assignment_card.dart';
import 'widgets/add_assignment_dialog.dart';

// Helper extensions
extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}

class AssignmentsScreen extends StatefulWidget {
  const AssignmentsScreen({super.key});

  @override
  State<AssignmentsScreen> createState() => _AssignmentsScreenState();
}

class _AssignmentsScreenState extends State<AssignmentsScreen> {
  TeamMember? _currentMember;
  bool _isLoading = true;
  List<Assignment> _assignments = [];
  Timer? _refreshTimer;

  String _searchQuery = '';
  AssignmentStatus? _statusFilter;

  @override
  void initState() {
    super.initState();
    _fetchMemberInfo();
    // Refresh assignments every 30 seconds for rudimentary real-time feel
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadAssignments(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchMemberInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Assuming TeamService exists in urbox or similar
      final member = await TeamService.getMember(user.uid);
      if (mounted) {
        setState(() {
          _currentMember = member;
        });
        _loadAssignments();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadAssignments() async {
    if (_currentMember == null) return;

    try {
      final showAll =
          _currentMember!.role == 'owner' ||
          _currentMember!.role == 'admin'; // Adjust role check

      final list = await AssignmentService.getAssignments(
        _currentMember!.companyId,
        memberId: showAll ? null : _currentMember!.id,
      );

      if (mounted) {
        setState(() {
          _assignments = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Load assignments error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAddDialog() async {
    if (_currentMember == null) return;

    final result = await showDialog(
      context: context,
      builder: (context) => AddAssignmentDialog(
        companyId: _currentMember!.companyId,
        currentMember: _currentMember!,
      ),
    );

    // Refresh if added
    if (result == true) {
      // Dialog should return true on success if modified to do so
      _loadAssignments();
    } else {
      // Just refresh anyway
      _loadAssignments();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_currentMember == null) {
      return const Scaffold(
        body: Center(child: Text('User profile not found')),
      );
    }

    final showAll =
        _currentMember!.role == 'owner' || _currentMember!.role == 'admin';

    // Filter locally
    var displayList = _assignments.where((a) {
      if (_statusFilter != null && a.status != _statusFilter) return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        return a.title.toLowerCase().contains(q) ||
            a.description.toLowerCase().contains(q) ||
            a.assignedToName.toLowerCase().contains(q);
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Row(
        children: [
          // Main Content
          Expanded(
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Assignments',
                                    style: AppTheme.headingMd,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                showAll
                                    ? 'Manage team tasks and deadlines'
                                    : 'Your assigned tasks',
                                style: AppTheme.bodyMd.copyWith(
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          ElevatedButton.icon(
                            onPressed: _showAddDialog,
                            icon: const Icon(Icons.add, size: 20),
                            label: const Text('New Assignment'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildFilters(),
                    ],
                  ),
                ),

                // Grid
                Expanded(
                  child: displayList.isEmpty
                      ? Center(child: Text('No assignments found'))
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final crossAxisCount = (constraints.maxWidth / 300)
                                .floor()
                                .clamp(2, 5);
                            return GridView.builder(
                              padding: const EdgeInsets.all(24),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: crossAxisCount,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                    childAspectRatio: 1.5,
                                  ),
                              itemCount: displayList.length,
                              itemBuilder: (context, index) {
                                final assignment = displayList[index];
                                return AssignmentCard(
                                  assignment: assignment,
                                  isOwner: showAll,
                                  onStatusChanged: (newStatus) async {
                                    // Optimistic update
                                    setState(() {
                                      // Complex to update object in list in place immutably without copyWith but here we reload
                                    });
                                    await AssignmentService.updateStatus(
                                      assignment.id,
                                      newStatus.name,
                                    );
                                    _loadAssignments();
                                  },
                                  onDelete: showAll
                                      ? () async {
                                          await AssignmentService.deleteAssignment(
                                            assignment.id,
                                          );
                                          _loadAssignments();
                                        }
                                      : null,
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Row(
      children: [
        // Search
        Expanded(
          child: TextField(
            onChanged: (val) => setState(() => _searchQuery = val),
            decoration: InputDecoration(
              hintText: 'Search assignments...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.grey.shade50,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 0,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        // Status Filter
        DropdownButtonHideUnderline(
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: DropdownButton<AssignmentStatus?>(
              value: _statusFilter,
              hint: const Text('All Statuses'),
              onChanged: (val) => setState(() => _statusFilter = val),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All Statuses'),
                ),
                ...AssignmentStatus.values.map((status) {
                  return DropdownMenuItem(
                    value: status,
                    child: Text(
                      status.name
                          .split('_')
                          .map((w) => w.capitalize())
                          .join(' '),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
