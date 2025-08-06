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
  }) : style = style ??
            const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              shadows: [
                Shadow(offset: Offset(2, 2), blurRadius: 4, color: Colors.black87),
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

class _TextOverlayWidgetState extends State<TextOverlayWidget>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _shadowController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _shadowAnimation;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _shadowController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.15,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeOutBack,
    ));

    _shadowAnimation = Tween<double>(
      begin: 4.0,
      end: 12.0,
    ).animate(CurvedAnimation(
      parent: _shadowController,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _shadowController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TextOverlayWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.overlay.isSelected != oldWidget.overlay.isSelected) {
      if (widget.overlay.isSelected) {
        _scaleController.forward();
        _shadowController.forward();
      } else {
        _scaleController.reverse();
        _shadowController.reverse();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final absolutePosition = Offset(
      widget.overlay.position.dx * widget.videoSize.width,
      widget.overlay.position.dy * widget.videoSize.height,
    );

    return AnimatedBuilder(
      animation: Listenable.merge([_scaleAnimation, _shadowAnimation]),
      builder: (context, child) {
        return Positioned(
          left: absolutePosition.dx,
          top: absolutePosition.dy,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                widget.onTap(widget.overlay.id);
              },
              onDoubleTap: () {
                HapticFeedback.mediumImpact();
                widget.onEditText(widget.overlay.id);
              },
              onPanStart: (details) {
                setState(() => _isDragging = true);
                HapticFeedback.lightImpact();
                _shadowController.forward();
              },
              onPanUpdate: (details) {
                final newAbsolutePosition = Offset(
                  (absolutePosition.dx + details.delta.dx).clamp(
                    0.0,
                    widget.videoSize.width - 120,
                  ),
                  (absolutePosition.dy + details.delta.dy).clamp(
                    0.0,
                    widget.videoSize.height - 60,
                  ),
                );

                final newRelativePosition = Offset(
                  newAbsolutePosition.dx / widget.videoSize.width,
                  newAbsolutePosition.dy / widget.videoSize.height,
                );

                widget.onPositionChanged(widget.overlay.id, newRelativePosition);
              },
              onPanEnd: (details) {
                setState(() => _isDragging = false);
                HapticFeedback.mediumImpact();
                if (!widget.overlay.isSelected) {
                  _shadowController.reverse();
                }
              },
              child: Container(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: widget.overlay.backgroundColor,
                  borderRadius: BorderRadius.circular(8),
                  border: widget.overlay.isSelected
                      ? Border.all(color: Colors.blue, width: 2)
                      : _isDragging
                          ? Border.all(color: Colors.white54, width: 1)
                          : null,
                  boxShadow: [
                    BoxShadow(
                      color: widget.overlay.isSelected
                          ? Colors.blue.withOpacity(0.4)
                          : Colors.black54,
                      blurRadius: _shadowAnimation.value,
                      spreadRadius: widget.overlay.isSelected ? 2 : 0,
                      offset: Offset(0, _shadowAnimation.value / 3),
                    ),
                  ],
                ),
                child: Text(
                  widget.overlay.text,
                  style: widget.overlay.style,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class TextTimelineStrip extends StatefulWidget {
  final List<TextOverlay> overlays;
  final double totalDuration;
  final double currentTime;
  final double timelineWidth;
  final double pixelsPerSecond;
  final Function(String id, double startTime, double endTime) onOverlayTimeChanged;
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
    required this.onOverlayDeleted, required void Function() onAddOverlay,
  }) : super(key: key);

  @override
  State<TextTimelineStrip> createState() => _TextTimelineStripState();
}

class _TextTimelineStripState extends State<TextTimelineStrip>
    with TickerProviderStateMixin {
  String? _draggingOverlayId;
  bool _isDraggingStart = false;
  bool _isDraggingEnd = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      child: Stack(
        children: [
          // Background track
          Container(
            width: widget.timelineWidth,
            height: 35,
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.grey[850]!, Colors.grey[800]!],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),

          // Time markers
          ...List.generate(
            (widget.totalDuration / 5).ceil(),
            (index) => _buildTimeMarker(index * 5),
          ),

          // Overlay blocks
          ...widget.overlays.map((overlay) => _buildOverlayBlock(overlay)),

          // Enhanced playhead
          _buildPlayhead(),
        ],
      ),
    );
  }

  Widget _buildTimeMarker(double seconds) {
    if (seconds > widget.totalDuration) return const SizedBox.shrink();

    final position = seconds * widget.pixelsPerSecond;
    return Positioned(
      left: position,
      top: 0,
      child: Column(
        children: [
          Text(
            '${seconds.toInt()}s',
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          Container(
            width: 1,
            height: 43,
            color: Colors.white24,
          ),
        ],
      ),
    );
  }

  Widget _buildPlayhead() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Positioned(
          left: widget.currentTime * widget.pixelsPerSecond - 1,
          top: 0,
          child: Column(
            children: [
              Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.blue, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.5),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.blue,
                    size: 10,
                  ),
                ),
              ),
              Container(
                width: 2,
                height: 34,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.white, Colors.blue],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.3),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOverlayBlock(TextOverlay overlay) {
    final blockWidth = overlay.duration * widget.pixelsPerSecond;
    final blockLeft = overlay.startTime * widget.pixelsPerSecond;

    return Positioned(
      left: blockLeft,
      top: 8,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onOverlaySelected(overlay.id);
        },
        onLongPress: () {
          HapticFeedback.heavyImpact();
          _showOverlayOptions(overlay);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: blockWidth.clamp(80.0, double.infinity),
          height: 35,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: overlay.isSelected
                  ? [Colors.blue[400]!, Colors.blue[600]!]
                  : [Colors.purple[400]!, Colors.purple[600]!],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: overlay.isSelected ? Colors.white : Colors.transparent,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: (overlay.isSelected ? Colors.blue : Colors.purple)
                    .withOpacity(0.4),
                blurRadius: overlay.isSelected ? 8 : 4,
                spreadRadius: overlay.isSelected ? 1 : 0,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    overlay.text.length > 12
                        ? '${overlay.text.substring(0, 12)}...'
                        : overlay.text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      shadows: [
                        Shadow(
                          offset: Offset(1, 1),
                          blurRadius: 2,
                          color: Colors.black54,
                        ),
                      ],
                    ),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

              if (overlay.isSelected) ...[
                _buildTimelineHandle(
                  isStart: true,
                  overlay: overlay,
                  onPan: (delta) {
                    final deltaSeconds = delta / widget.pixelsPerSecond;
                    var newStartTime = overlay.startTime + deltaSeconds;
                    
                    // Magnetic snapping to seconds
                    final roundedStart = newStartTime.round().toDouble();
                    if ((newStartTime - roundedStart).abs() < 0.2) {
                      newStartTime = roundedStart;
                    }
                    
                    newStartTime = newStartTime.clamp(0.0, overlay.endTime - 0.5);

                    if (newStartTime != overlay.startTime) {
                      widget.onOverlayTimeChanged(
                        overlay.id,
                        newStartTime,
                        overlay.endTime,
                      );
                    }
                  },
                ),
                _buildTimelineHandle(
                  isStart: false,
                  overlay: overlay,
                  onPan: (delta) {
                    final deltaSeconds = delta / widget.pixelsPerSecond;
                    var newEndTime = overlay.endTime + deltaSeconds;
                    
                    // Magnetic snapping to seconds
                    final roundedEnd = newEndTime.round().toDouble();
                    if ((newEndTime - roundedEnd).abs() < 0.2) {
                      newEndTime = roundedEnd;
                    }
                    
                    newEndTime = newEndTime.clamp(
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
      left: isStart ? -6 : null,
      right: isStart ? null : -6,
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
          width: 12,
          height: 39,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isStart
                  ? [Colors.green[300]!, Colors.green[600]!]
                  : [Colors.red[300]!, Colors.red[600]!],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: (isStart ? Colors.green : Colors.red).withOpacity(0.5),
                blurRadius: 6,
                spreadRadius: 1,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            isStart ? Icons.chevron_left : Icons.chevron_right,
            color: Colors.white,
            size: 12,
          ),
        ),
      ),
    );
  }

  void _showOverlayOptions(TextOverlay overlay) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Text Overlay Options',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            _buildOptionTile(
              icon: Icons.edit,
              title: 'Edit Text',
              color: Colors.blue,
              onTap: () {
                Navigator.pop(context);
                // Edit functionality would be handled by parent
              },
            ),
            const SizedBox(height: 12),
            _buildOptionTile(
              icon: Icons.palette,
              title: 'Change Style',
              color: Colors.orange,
              onTap: () {
                Navigator.pop(context);
                // Style editing functionality
              },
            ),
            const SizedBox(height: 12),
            _buildOptionTile(
              icon: Icons.copy,
              title: 'Duplicate',
              color: Colors.green,
              onTap: () {
                Navigator.pop(context);
                // Duplicate functionality
              },
            ),
            const SizedBox(height: 12),
            _buildOptionTile(
              icon: Icons.delete,
              title: 'Delete',
              color: Colors.red,
              onTap: () {
                Navigator.pop(context);
                HapticFeedback.heavyImpact();
                widget.onOverlayDeleted(overlay.id);
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.grey[800],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[700]!, width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Colors.grey[400],
                size: 20,
              ),
            ],
          ),
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

class _TextEditDialogState extends State<TextEditDialog>
    with TickerProviderStateMixin {
  late TextEditingController _controller;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutBack,
    ));

    _slideController.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _slideAnimation,
      builder: (context, child) {
        return SlideTransition(
          position: _slideAnimation,
          child: AlertDialog(
            backgroundColor: Colors.grey[900],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 20,
            title: Row(
              children: [
                Icon(Icons.text_fields, color: Colors.blue, size: 24),
                const SizedBox(width: 12),
                const Text(
                  'Edit Text',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[600]!, width: 1),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Enter your text...',
                      hintStyle: TextStyle(color: Colors.grey[400]),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    autofocus: true,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ),
                const SizedBox(height: 20),
                // Quick style options
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStyleButton(
                      icon: Icons.format_bold,
                      label: 'Bold',
                      color: Colors.orange,
                    ),
                    _buildStyleButton(
                      icon: Icons.format_italic,
                      label: 'Italic',
                      color: Colors.green,
                    ),
                    _buildStyleButton(
                      icon: Icons.color_lens,
                      label: 'Color',
                      color: Colors.purple,
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(context);
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  if (_controller.text.trim().isNotEmpty) {
                    HapticFeedback.mediumImpact();
                    widget.onTextChanged(_controller.text.trim());
                    Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 4,
                ),
                child: const Text(
                  'Save',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStyleButton({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.5), width: 1),
          ),
          child: IconButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              // Style functionality would be implemented here
            },
            icon: Icon(icon, color: color, size: 20),
            padding: EdgeInsets.zero,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}