import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TextOverlay {
  String id;
  String text;
  Offset position;
  double startTime;
  double endTime;
  TextStyle style;
  Color backgroundColor;
  bool isSelected;

  TextOverlay({
    required this.id,
    required this.text,
    required this.position,
    required this.startTime,
    required this.endTime,
    TextStyle? style,
    Color? backgroundColor,
    this.isSelected = false,
  }) : style =
           style ??
           const TextStyle(
             color: Colors.white,
             fontSize: 24,
             fontWeight: FontWeight.bold,
             shadows: [
               Shadow(offset: Offset(1, 1), blurRadius: 2, color: Colors.black),
             ],
           ),
       backgroundColor = backgroundColor ?? Colors.transparent;

  TextOverlay copyWith({
    String? id,
    String? text,
    Offset? position,
    double? startTime,
    double? endTime,
    TextStyle? style,
    Color? backgroundColor,
    bool? isSelected,
  }) {
    return TextOverlay(
      id: id ?? this.id,
      text: text ?? this.text,
      position: position ?? this.position,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      style: style ?? this.style,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      isSelected: isSelected ?? this.isSelected,
    );
  }

  double get duration => endTime - startTime;
}

class TextOverlayWidget extends StatefulWidget {
  final TextOverlay overlay;
  final Size videoSize;
  final Function(String id, Offset position) onPositionChanged;
  final Function(String id) onTap;
  final Function(String id) onEditText;
  final bool isEditing;

  const TextOverlayWidget({
    Key? key,
    required this.overlay,
    required this.videoSize,
    required this.onPositionChanged,
    required this.onTap,
    required this.onEditText,
    this.isEditing = false,
  }) : super(key: key);

  @override
  State<TextOverlayWidget> createState() => _TextOverlayWidgetState();
}

class _TextOverlayWidgetState extends State<TextOverlayWidget> {
  @override
  Widget build(BuildContext context) {
    final absolutePosition = Offset(
      widget.overlay.position.dx * widget.videoSize.width,
      widget.overlay.position.dy * widget.videoSize.height,
    );

    return Positioned(
      left: absolutePosition.dx,
      top: absolutePosition.dy,
      child: GestureDetector(
        onTap: () => widget.onTap(widget.overlay.id),
        onDoubleTap: () => widget.onEditText(widget.overlay.id),
        onPanUpdate: (details) {
          final newAbsolutePosition = Offset(
            (absolutePosition.dx + details.delta.dx).clamp(
              0.0,
              widget.videoSize.width - 100,
            ),
            (absolutePosition.dy + details.delta.dy).clamp(
              0.0,
              widget.videoSize.height - 50,
            ),
          );

          final newRelativePosition = Offset(
            newAbsolutePosition.dx / widget.videoSize.width,
            newAbsolutePosition.dy / widget.videoSize.height,
          );

          widget.onPositionChanged(widget.overlay.id, newRelativePosition);
        },
        onPanEnd: (details) {
          HapticFeedback.lightImpact();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: widget.overlay.backgroundColor,
            borderRadius: BorderRadius.circular(4),
            border: widget.overlay.isSelected
                ? Border.all(color: Colors.blue, width: 2)
                : null,
            boxShadow: widget.overlay.isSelected
                ? [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.3),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Text(widget.overlay.text, style: widget.overlay.style),
        ),
      ),
    );
  }
}

class TextTimelineStrip extends StatefulWidget {
  final List<TextOverlay> overlays;
  final double totalDuration;
  final double currentTime;
  final double timelineWidth;
  final double pixelsPerSecond;
  final Function(String id, double startTime, double endTime)
  onOverlayTimeChanged;
  final Function(String id) onOverlaySelected;
  final Function(String id) onOverlayDeleted;

  const TextTimelineStrip({
    Key? key,
    required this.overlays,
    required this.totalDuration,
    required this.currentTime,
    required this.timelineWidth,
    required this.pixelsPerSecond,
    required this.onOverlayTimeChanged,
    required this.onOverlaySelected,
    required this.onOverlayDeleted,
  }) : super(key: key);

  @override
  State<TextTimelineStrip> createState() => _TextTimelineStripState();
}

class _TextTimelineStripState extends State<TextTimelineStrip> {
  String? _draggingOverlayId;
  bool _isDraggingStart = false;
  bool _isDraggingEnd = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      child: Stack(
        children: [
          Container(
            width: widget.timelineWidth,
            height: 30,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(4),
            ),
          ),

          ...widget.overlays.map((overlay) => _buildOverlayBlock(overlay)),

          Positioned(
            left: widget.currentTime * widget.pixelsPerSecond - 1,
            top: 0,
            child: Container(width: 2, height: 40, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlayBlock(TextOverlay overlay) {
    final blockWidth = overlay.duration * widget.pixelsPerSecond;
    final blockLeft = overlay.startTime * widget.pixelsPerSecond;

    return Positioned(
      left: blockLeft,
      top: 5,
      child: GestureDetector(
        onTap: () => widget.onOverlaySelected(overlay.id),
        onLongPress: () => _showOverlayOptions(overlay),
        child: Container(
          width: blockWidth,
          height: 30,
          decoration: BoxDecoration(
            color: overlay.isSelected ? Colors.blue : Colors.purple,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: overlay.isSelected ? Colors.white : Colors.transparent,
              width: 1,
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Text(
                  overlay.text.length > 10
                      ? '${overlay.text.substring(0, 10)}...'
                      : overlay.text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              if (overlay.isSelected)
                _buildTimelineHandle(
                  isStart: true,
                  overlay: overlay,
                  onPan: (delta) {
                    final deltaSeconds = delta / widget.pixelsPerSecond;
                    final newStartTime = (overlay.startTime + deltaSeconds)
                        .clamp(0.0, overlay.endTime - 0.5);

                    if (newStartTime != overlay.startTime) {
                      widget.onOverlayTimeChanged(
                        overlay.id,
                        newStartTime,
                        overlay.endTime,
                      );
                    }
                  },
                ),

              if (overlay.isSelected)
                _buildTimelineHandle(
                  isStart: false,
                  overlay: overlay,
                  onPan: (delta) {
                    final deltaSeconds = delta / widget.pixelsPerSecond;
                    final newEndTime = (overlay.endTime + deltaSeconds).clamp(
                      overlay.startTime + 0.5,
                      widget.totalDuration,
                    );

                    if (newEndTime != overlay.endTime) {
                      widget.onOverlayTimeChanged(
                        overlay.id,
                        overlay.startTime,
                        newEndTime,
                      );
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimelineHandle({
    required bool isStart,
    required TextOverlay overlay,
    required Function(double) onPan,
  }) {
    return Positioned(
      left: isStart ? -4 : null,
      right: isStart ? null : -4,
      top: -2,
      child: GestureDetector(
        onPanStart: (details) {
          setState(() {
            _draggingOverlayId = overlay.id;
            _isDraggingStart = isStart;
            _isDraggingEnd = !isStart;
          });
          HapticFeedback.lightImpact();
        },
        onPanUpdate: (details) {
          onPan(details.delta.dx);
        },
        onPanEnd: (details) {
          setState(() {
            _draggingOverlayId = null;
            _isDraggingStart = false;
            _isDraggingEnd = false;
          });
          HapticFeedback.mediumImpact();
        },
        child: Container(
          width: 8,
          height: 34,
          decoration: BoxDecoration(
            color: isStart ? Colors.green : Colors.red,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: Colors.white, width: 1),
          ),
        ),
      ),
    );
  }

  void _showOverlayOptions(TextOverlay overlay) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Text Overlay Options',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text(
                'Delete',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                widget.onOverlayDeleted(overlay.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text(
                'Edit Text',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class TextEditDialog extends StatefulWidget {
  final String initialText;
  final Function(String) onTextChanged;

  const TextEditDialog({
    Key? key,
    required this.initialText,
    required this.onTextChanged,
  }) : super(key: key);

  @override
  State<TextEditDialog> createState() => _TextEditDialogState();
}

class _TextEditDialogState extends State<TextEditDialog> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.grey[900],
      title: const Text('Edit Text', style: TextStyle(color: Colors.white)),
      content: TextField(
        controller: _controller,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Enter text...',
          hintStyle: TextStyle(color: Colors.grey[400]),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.grey[600]!),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.blue),
          ),
        ),
        autofocus: true,
        maxLines: 3,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        TextButton(
          onPressed: () {
            widget.onTextChanged(_controller.text);
            Navigator.pop(context);
          },
          child: const Text('Save', style: TextStyle(color: Colors.blue)),
        ),
      ],
    );
  }
}
