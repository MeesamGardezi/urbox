import 'package:flutter/material.dart';

class ResizableShell extends StatefulWidget {
  final Widget sidebar;
  final Widget body;
  final double initialSidebarWidth;
  final double minSidebarWidth;
  final double maxSidebarWidth;
  final bool isSidebarVisible;

  const ResizableShell({
    super.key,
    required this.sidebar,
    required this.body,
    this.initialSidebarWidth = 360,
    this.minSidebarWidth = 300,
    this.maxSidebarWidth = 480,
    this.isSidebarVisible = true,
  });

  @override
  State<ResizableShell> createState() => _ResizableShellState();
}

class _ResizableShellState extends State<ResizableShell> {
  late double _sidebarWidth;
  bool _isResizing = false;

  @override
  void initState() {
    super.initState();
    _sidebarWidth = widget.initialSidebarWidth;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Sidebar
        AnimatedContainer(
          duration: _isResizing
              ? Duration.zero
              : const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          width: widget.isSidebarVisible ? _sidebarWidth : 0,
          child: OverflowBox(
            minWidth: 0,
            maxWidth: widget.maxSidebarWidth,
            alignment: Alignment.centerLeft,
            child: SizedBox(width: _sidebarWidth, child: widget.sidebar),
          ),
        ),

        // Resize Handle
        if (widget.isSidebarVisible)
          MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              onHorizontalDragStart: (_) => setState(() => _isResizing = true),
              onHorizontalDragEnd: (_) => setState(() => _isResizing = false),
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _sidebarWidth += details.delta.dx;
                  if (_sidebarWidth < widget.minSidebarWidth) {
                    _sidebarWidth = widget.minSidebarWidth;
                  }
                  if (_sidebarWidth > widget.maxSidebarWidth) {
                    _sidebarWidth = widget.maxSidebarWidth;
                  }
                });
              },
              child: Container(
                width: 4,
                color: _isResizing
                    ? Colors.blue.withOpacity(0.5)
                    : Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  color: Colors.grey.shade300,
                ),
              ),
            ),
          ),

        // Main Content
        Expanded(child: widget.body),
      ],
    );
  }
}
