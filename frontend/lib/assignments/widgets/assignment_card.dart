import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../data/models/assignment.dart';

/// A compact card-style widget for displaying assignments in a grid layout
class AssignmentCard extends StatelessWidget {
  final Assignment assignment;
  final bool isOwner;
  final Function(AssignmentStatus) onStatusChanged;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;
  final bool isSelected;

  const AssignmentCard({
    super.key,
    required this.assignment,
    required this.isOwner,
    required this.onStatusChanged,
    this.onDelete,
    this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('MMM d');

    Color statusColor;
    IconData statusIcon;
    switch (assignment.status) {
      case AssignmentStatus.pending:
        statusColor = Colors.orange;
        statusIcon = Icons.schedule;
        break;
      case AssignmentStatus.in_progress:
        statusColor = Colors.blue;
        statusIcon = Icons.autorenew;
        break;
      case AssignmentStatus.completed:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
    }

    final isOverdue =
        assignment.targetDate != null &&
        assignment.targetDate!.isBefore(DateTime.now()) &&
        assignment.status != AssignmentStatus.completed;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary.withOpacity(0.04) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.primary : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status indicator and menu row
                  Row(
                    children: [
                      // Interactive Status Chip
                      PopupMenuButton<AssignmentStatus>(
                        tooltip: 'Change Status',
                        offset: const Offset(0, 30),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onSelected: onStatusChanged,
                        color: Colors.white,
                        surfaceTintColor: Colors.transparent,
                        elevation: 8,
                        shadowColor: Colors.black.withOpacity(0.1),
                        padding: const EdgeInsets.all(8),
                        itemBuilder: (context) =>
                            AssignmentStatus.values.map((s) {
                              Color itemColor;
                              switch (s) {
                                case AssignmentStatus.pending:
                                  itemColor = Colors.orange;
                                  break;
                                case AssignmentStatus.in_progress:
                                  itemColor = Colors.blue;
                                  break;
                                case AssignmentStatus.completed:
                                  itemColor = Colors.green;
                                  break;
                              }

                              return PopupMenuItem<AssignmentStatus>(
                                value: s,
                                height: 48,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                  horizontal: 8,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: itemColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: s == assignment.status
                                        ? Border.all(
                                            color: itemColor.withOpacity(0.5),
                                            width: 1,
                                          )
                                        : null,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        s == AssignmentStatus.completed
                                            ? Icons.check_circle_outline
                                            : s == AssignmentStatus.in_progress
                                            ? Icons.autorenew
                                            : Icons.schedule,
                                        size: 16,
                                        color: itemColor,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        s.name
                                            .split('_')
                                            .join(' ')
                                            .replaceFirstMapped(
                                              RegExp(r'^\w'),
                                              (m) => m[0]!.toUpperCase(),
                                            ),
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: itemColor,
                                        ),
                                      ),
                                      if (s == assignment.status) ...[
                                        const Spacer(),
                                        Icon(
                                          Icons.check,
                                          size: 16,
                                          color: itemColor,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: statusColor.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(statusIcon, size: 12, color: statusColor),
                              const SizedBox(width: 4),
                              Text(
                                assignment.statusDisplay,
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.arrow_drop_down,
                                size: 14,
                                color: statusColor.withOpacity(0.7),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const Spacer(),

                      // More Vert Menu (Only if owner)
                      if (isOwner && onDelete != null)
                        PopupMenuButton<String>(
                          icon: Icon(
                            Icons.more_vert,
                            size: 18,
                            color: Colors.grey.shade400,
                          ),
                          padding: EdgeInsets.zero,
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color: Colors.red,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Delete',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          onSelected: (value) {
                            if (value == 'delete') {
                              onDelete?.call();
                            }
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Title
                  Text(
                    assignment.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  // Description if available
                  if (assignment.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      assignment.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],

                  const Spacer(),

                  // Divider
                  Divider(height: 12, color: Colors.grey.shade100),

                  // Bottom info row
                  Row(
                    children: [
                      // Person info
                      Expanded(
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 10,
                              backgroundColor: AppTheme.primary.withOpacity(
                                0.1,
                              ),
                              child: Text(
                                (isOwner
                                        ? assignment.assignedToName
                                        : assignment.assignedByName)
                                    .substring(0, 1)
                                    .toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                isOwner
                                    ? assignment.assignedToName
                                    : assignment.assignedByName,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Due date
                      if (assignment.targetDate != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isOverdue
                                ? Colors.red.withOpacity(0.1)
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.calendar_today,
                                size: 9,
                                color: isOverdue
                                    ? Colors.red
                                    : Colors.grey.shade600,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                dateFormat.format(assignment.targetDate!),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w500,
                                  color: isOverdue
                                      ? Colors.red
                                      : Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
