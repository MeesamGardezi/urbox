import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class FolderTreeSelector extends StatefulWidget {
  final List<Map<String, dynamic>> folders;
  final ValueChanged<String?> onSelect;
  final String? initialSelection;

  const FolderTreeSelector({
    super.key,
    required this.folders,
    required this.onSelect,
    this.initialSelection,
  });

  @override
  State<FolderTreeSelector> createState() => _FolderTreeSelectorState();
}

class _FolderTreeSelectorState extends State<FolderTreeSelector> {
  final Set<String> _expandedKeys = {'', '/'};
  late String? _selectedKey;
  late List<_TreeNode> _visibleNodes;

  @override
  void initState() {
    super.initState();
    _selectedKey = widget.initialSelection;
    _rebuildTree();
  }

  void _rebuildTree() {
    // 1. Build Adjacency Map
    final Map<String, List<Map<String, dynamic>>> adj = {};
    // Ensure root exists in adj to start traversal
    adj[''] = [];

    // Organize folders by parent
    for (final folder in widget.folders) {
      final key = folder['key'] as String;
      if (key.isEmpty) continue; // Root is handled

      final parent = _getParentKey(key);
      if (adj.containsKey(parent)) {
        adj[parent]!.add(folder);
      } else {
        adj[parent] = [folder];
      }
      // Initialize entry for this folder (as a potential parent)
      if (!adj.containsKey(key)) {
        adj[key] = [];
      }
    }

    // Sort children
    for (final key in adj.keys) {
      adj[key]!.sort(
        (a, b) => (a['name'] as String).toLowerCase().compareTo(
          (b['name'] as String).toLowerCase(),
        ),
      );
    }

    // 2. Build Visible List
    _visibleNodes = [];

    // Add Root if present in folders list, or virtually
    final rootFolder = widget.folders.firstWhere(
      (f) => (f['key'] as String).isEmpty,
      orElse: () => {'key': '', 'name': 'Home'},
    );

    _buildNodeRecursively(rootFolder, 0, adj, []);
  }

  String _getParentKey(String key) {
    if (key.isEmpty) return '';
    final trimmed = key.endsWith('/') ? key.substring(0, key.length - 1) : key;
    final lastSlashIndex = trimmed.lastIndexOf('/');
    if (lastSlashIndex == -1) return '';
    return trimmed.substring(0, lastSlashIndex + 1);
  }

  void _buildNodeRecursively(
    Map<String, dynamic> folder,
    int depth,
    Map<String, List<Map<String, dynamic>>> adj,
    List<bool> isLastChildStack,
  ) {
    final key = folder['key'] as String;
    final children = adj[key] ?? [];
    final hasChildren = children.isNotEmpty;
    final isExpanded = _expandedKeys.contains(key);

    _visibleNodes.add(
      _TreeNode(
        folder: folder,
        depth: depth,
        hasChildren: hasChildren,
        isExpanded: isExpanded,
        isLastChildStack: List.from(isLastChildStack),
      ),
    );

    if (isExpanded) {
      for (int i = 0; i < children.length; i++) {
        final child = children[i];
        final isLast = i == children.length - 1;
        _buildNodeRecursively(child, depth + 1, adj, [
          ...isLastChildStack,
          isLast,
        ]);
      }
    }
  }

  void _toggleExpand(String key) {
    setState(() {
      if (_expandedKeys.contains(key)) {
        _expandedKeys.remove(key);
      } else {
        _expandedKeys.add(key);
      }
      _rebuildTree();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.folders.isEmpty) {
      return Center(
        child: Text(
          'No folders available',
          style: GoogleFonts.inter(color: Colors.grey.shade500),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _visibleNodes.length,
      itemBuilder: (context, index) {
        final node = _visibleNodes[index];
        final key = node.folder['key'] as String;
        final isSelected = _selectedKey == key;

        return InkWell(
          onTap: () {
            setState(() => _selectedKey = key);
            widget.onSelect(key);
          },
          child: Container(
            height: 36,
            color: isSelected ? const Color(0xFF3B82F6).withOpacity(0.1) : null,
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: [
                // Indentation and Lines
                for (int i = 0; i < node.depth; i++)
                  SizedBox(
                    width: 24,
                    child: Center(
                      child:
                          i < node.isLastChildStack.length &&
                              !node.isLastChildStack[i]
                          ? VerticalDivider(
                              width: 1,
                              thickness: 1,
                              color: Colors.grey.shade300,
                            )
                          : null,
                    ),
                  ),

                // Expand/Collapse Icon or Connector
                SizedBox(
                  width: 24,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Vertical line from above if not root
                      if (node.depth > 0)
                        Positioned(
                          top: 0,
                          bottom: 18,
                          left: 11.5,
                          child: Container(
                            width: 1,
                            color: Colors.grey.shade300,
                          ),
                        ),
                      // Horizontal line to icon
                      if (node.depth > 0)
                        Positioned(
                          left: 11.5,
                          right: 0,
                          top: 18,
                          child: Container(
                            height: 1,
                            color: Colors.grey.shade300,
                          ),
                        ),

                      if (node.hasChildren)
                        InkWell(
                          onTap: () => _toggleExpand(key),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            width: 14,
                            height: 14,
                            child: Icon(
                              node.isExpanded ? Icons.remove : Icons.add,
                              size: 10,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        )
                      else if (node.depth > 0)
                        // Just an elbow connector if no children (and not root)
                        // Actually the loops above handle lines.
                        // We just need the elbow connection.
                        // The loop draws vertical lines for ancestors.
                        // This specific cell is for the current node's "self" connector.
                        // Since we structure this row as: [Ancestor Indents] [Self Indent/Expand] [Folder Icon]
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(width: 6),

                // Folder Icon
                Icon(
                  key.isEmpty ? Icons.home_filled : Icons.folder,
                  size: 18,
                  color: isSelected
                      ? const Color(0xFF3B82F6)
                      : const Color(0xFFFFCA28),
                ),

                const SizedBox(width: 8),

                // Name
                Expanded(
                  child: Text(
                    node.folder['name'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: isSelected
                          ? const Color(0xFF3B82F6)
                          : Colors.grey.shade800,
                    ),
                  ),
                ),

                if (isSelected)
                  const Icon(Icons.check, size: 14, color: Color(0xFF3B82F6)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TreeNode {
  final Map<String, dynamic> folder;
  final int depth;
  final bool hasChildren;
  final bool isExpanded;
  final List<bool> isLastChildStack; // To draw vertical lines correctly

  _TreeNode({
    required this.folder,
    required this.depth,
    required this.hasChildren,
    required this.isExpanded,
    required this.isLastChildStack,
  });
}
