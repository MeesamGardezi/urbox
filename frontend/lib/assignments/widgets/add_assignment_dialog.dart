import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/models/team_member.dart';
import '../data/models/assignment.dart';
import '../data/services/assignment_service.dart';
import '../../auth/services/team_service.dart';

class AddAssignmentDialog extends StatefulWidget {
  final String companyId;
  final TeamMember currentMember;

  const AddAssignmentDialog({
    super.key,
    required this.companyId,
    required this.currentMember,
  });

  @override
  State<AddAssignmentDialog> createState() => _AddAssignmentDialogState();
}

class _AddAssignmentDialogState extends State<AddAssignmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _searchController = TextEditingController();

  DateTime? _targetDate;
  TeamMember? _selectedMember;
  List<TeamMember> _teamMembers = [];
  List<TeamMember> _filteredMembers = [];
  bool _isLoading = true;
  bool _isSaving = false;
  bool _showDropdown = false;

  final FocusNode _searchFocusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _loadTeamMembers();
    _searchController.addListener(_filterMembers);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Future<void> _loadTeamMembers() async {
    // Corrected to use Future-based call or adapt to stream if needed, assuming getActiveMembers or similar exists
    try {
      // Assuming getTeamMembers returns a Stream, we take the first emission
      final members = await TeamService.getTeamMembers(widget.companyId).first;
      if (mounted) {
        setState(() {
          _teamMembers = members.where((m) => m.isActive).toList();
          _filteredMembers = _teamMembers;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filterMembers() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredMembers = _teamMembers.where((m) {
        return m.name.toLowerCase().contains(query) ||
            m.email.toLowerCase().contains(query);
      }).toList();
    });
    _updateOverlay();
  }

  void _showOverlay() {
    _removeOverlay();
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
    setState(() => _showDropdown = true);
  }

  void _updateOverlay() {
    _overlayEntry?.markNeedsBuild();
  }

  OverlayEntry _createOverlayEntry() {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    return OverlayEntry(
      builder: (context) => Positioned(
        width: size.width - 48,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 56),
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: _filteredMembers.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No members found'),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _filteredMembers.length,
                      itemBuilder: (context, index) {
                        final member = _filteredMembers[index];
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: AppTheme.primary.withOpacity(0.1),
                            child: Text(
                              member.name.isNotEmpty
                                  ? member.name[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          title: Text(member.name),
                          subtitle: Text(
                            member.email,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          onTap: () => _selectMember(member),
                        );
                      },
                    ),
            ),
          ),
        ),
      ),
    );
  }

  void _selectMember(TeamMember member) {
    setState(() {
      _selectedMember = member;
      _searchController.text = member.name;
      _showDropdown = false;
    });
    _removeOverlay();
    _searchFocusNode.unfocus();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: AppTheme.primary),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _targetDate = picked);
    }
  }

  Future<void> _saveAssignment() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedMember == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a team member')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final assignment = Assignment(
        id: '',
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        assignedTo: _selectedMember!.id,
        assignedToName: _selectedMember!.name,
        assignedBy: widget.currentMember.id,
        assignedByName: widget.currentMember.name,
        companyId: widget.companyId,
        status: AssignmentStatus.pending,
        targetDate: _targetDate,
        assignedDate: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await AssignmentService.createAssignment(assignment);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Assignment created successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('New Assignment', style: AppTheme.headingMd),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Title Field
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Title',
                  hintText: 'Enter assignment title',
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a title';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Description Field
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: 'Description (optional)',
                  hintText: 'Add more details...',
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),

              // Assign To Field (Searchable Dropdown)
              Text(
                'Assign To',
                style: AppTheme.labelMd.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              CompositedTransformTarget(
                link: _layerLink,
                child: TextFormField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  decoration: InputDecoration(
                    hintText: _isLoading
                        ? 'Loading...'
                        : 'Search team member...',
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    prefixIcon: _selectedMember != null
                        ? Padding(
                            padding: const EdgeInsets.only(left: 8, right: 4),
                            child: CircleAvatar(
                              radius: 14,
                              backgroundColor: AppTheme.primary.withOpacity(
                                0.1,
                              ),
                              child: Text(
                                _selectedMember!.name.isNotEmpty
                                    ? _selectedMember!.name[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          )
                        : const Icon(Icons.search),
                    prefixIconConstraints: _selectedMember != null
                        ? const BoxConstraints(minWidth: 48, minHeight: 48)
                        : null,
                    suffixIcon: _selectedMember != null
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              setState(() {
                                _selectedMember = null;
                                _searchController.clear();
                              });
                              _filterMembers();
                            },
                          )
                        : const Icon(Icons.arrow_drop_down),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  enabled: !_isLoading,
                  onTap: () {
                    if (!_showDropdown) {
                      _showOverlay();
                    }
                  },
                  onChanged: (value) {
                    if (_selectedMember != null) {
                      setState(() => _selectedMember = null);
                    }
                    if (!_showDropdown) {
                      _showOverlay();
                    }
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Target Date
              Text(
                'Target Date (optional)',
                style: AppTheme.labelMd.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _selectDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 20,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _targetDate != null
                            ? DateFormat('MMM d, yyyy').format(_targetDate!)
                            : 'Select a date',
                        style: TextStyle(
                          color: _targetDate != null
                              ? Colors.black87
                              : Colors.grey.shade500,
                        ),
                      ),
                      const Spacer(),
                      if (_targetDate != null)
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() => _targetDate = null),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _saveAssignment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Text('Create Assignment'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
