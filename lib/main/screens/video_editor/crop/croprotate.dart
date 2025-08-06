import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;

class CropRotateSettings {
  double rotation;
  double cropX;
  double cropY;
  double cropWidth;
  double cropHeight;
  double scaleX;
  double scaleY;
  bool flipHorizontal;
  bool flipVertical;

  CropRotateSettings({
    this.rotation = 0.0,
    this.cropX = 0.0,
    this.cropY = 0.0,
    this.cropWidth = 1.0,
    this.cropHeight = 1.0,
    this.scaleX = 1.0,
    this.scaleY = 1.0,
    this.flipHorizontal = false,
    this.flipVertical = false,
  });

  CropRotateSettings copyWith({
    double? rotation,
    double? cropX,
    double? cropY,
    double? cropWidth,
    double? cropHeight,
    double? scaleX,
    double? scaleY,
    bool? flipHorizontal,
    bool? flipVertical,
  }) {
    return CropRotateSettings(
      rotation: rotation ?? this.rotation,
      cropX: cropX ?? this.cropX,
      cropY: cropY ?? this.cropY,
      cropWidth: cropWidth ?? this.cropWidth,
      cropHeight: cropHeight ?? this.cropHeight,
      scaleX: scaleX ?? this.scaleX,
      scaleY: scaleY ?? this.scaleY,
      flipHorizontal: flipHorizontal ?? this.flipHorizontal,
      flipVertical: flipVertical ?? this.flipVertical,
    );
  }

  bool get hasChanges {
    return rotation != 0.0 ||
        cropX != 0.0 ||
        cropY != 0.0 ||
        cropWidth != 1.0 ||
        cropHeight != 1.0 ||
        scaleX != 1.0 ||
        scaleY != 1.0 ||
        flipHorizontal ||
        flipVertical;
  }
}

class CropRotateWidget extends StatefulWidget {
  final CropRotateSettings settings;
  final Function(CropRotateSettings) onSettingsChanged;
  final Widget videoPreview;
  final Size videoSize;

  const CropRotateWidget({
    Key? key,
    required this.settings,
    required this.onSettingsChanged,
    required this.videoPreview,
    required this.videoSize,
  }) : super(key: key);

  @override
  State<CropRotateWidget> createState() => _CropRotateWidgetState();
}

class _CropRotateWidgetState extends State<CropRotateWidget>
    with TickerProviderStateMixin {
  late AnimationController _rotationController;
  late Animation<double> _rotationAnimation;
  bool _isDragging = false;
  bool _isCropping = false;
  String _activeMode = 'rotate';

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _rotationAnimation = Tween<double>(begin: 0, end: 90).animate(
      CurvedAnimation(parent: _rotationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  void _rotate90Degrees() {
    HapticFeedback.mediumImpact();
    final newRotation = (widget.settings.rotation + 90) % 360;
    widget.onSettingsChanged(widget.settings.copyWith(rotation: newRotation));
    _rotationController.forward().then((_) => _rotationController.reset());
  }

  void _resetAll() {
    HapticFeedback.lightImpact();
    widget.onSettingsChanged(CropRotateSettings());
  }

  void _flipHorizontal() {
    HapticFeedback.lightImpact();
    widget.onSettingsChanged(
      widget.settings.copyWith(flipHorizontal: !widget.settings.flipHorizontal),
    );
  }

  void _flipVertical() {
    HapticFeedback.lightImpact();
    widget.onSettingsChanged(
      widget.settings.copyWith(flipVertical: !widget.settings.flipVertical),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(child: _buildVideoPreviewWithOverlay()),
          _buildModeSelector(),
          _buildControlPanel(),
          _buildBottomActions(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border(bottom: BorderSide(color: Colors.grey[800]!)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 24),
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          const Text(
            'Crop & Rotate',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (widget.settings.hasChanges)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.orange, size: 24),
              onPressed: _resetAll,
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildVideoPreviewWithOverlay() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Stack(
          children: [
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..rotateZ(widget.settings.rotation * math.pi / 180)
                ..scale(
                  widget.settings.scaleX *
                      (widget.settings.flipHorizontal ? -1 : 1),
                  widget.settings.scaleY *
                      (widget.settings.flipVertical ? -1 : 1),
                ),
              child: ClipRect(
                child: Align(
                  alignment: Alignment(
                    -1 +
                        2 *
                            (widget.settings.cropX +
                                widget.settings.cropWidth / 2),
                    -1 +
                        2 *
                            (widget.settings.cropY +
                                widget.settings.cropHeight / 2),
                  ),
                  widthFactor: widget.settings.cropWidth,
                  heightFactor: widget.settings.cropHeight,
                  child: widget.videoPreview,
                ),
              ),
            ),

            if (_activeMode == 'crop')
              Positioned.fill(child: _buildCropOverlay()),

            if (_activeMode == 'rotate')
              Positioned(
                top: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${widget.settings.rotation.toInt()}°',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCropOverlay() {
    return GestureDetector(
      onPanStart: (details) {
        setState(() {
          _isDragging = true;
          _isCropping = true;
        });
      },
      onPanUpdate: (details) {
        final renderBox = context.findRenderObject() as RenderBox;
        final localPosition = renderBox.globalToLocal(details.globalPosition);
        final size = renderBox.size;

        final deltaX = details.delta.dx / size.width;
        final deltaY = details.delta.dy / size.height;

        widget.onSettingsChanged(
          widget.settings.copyWith(
            cropX: (widget.settings.cropX + deltaX).clamp(0.0, 0.8),
            cropY: (widget.settings.cropY + deltaY).clamp(0.0, 0.8),
          ),
        );
      },
      onPanEnd: (details) {
        setState(() {
          _isDragging = false;
          _isCropping = false;
        });
      },
      child: Container(
        color: Colors.transparent,
        child: CustomPaint(
          painter: CropOverlayPainter(
            cropX: widget.settings.cropX,
            cropY: widget.settings.cropY,
            cropWidth: widget.settings.cropWidth,
            cropHeight: widget.settings.cropHeight,
            isDragging: _isDragging,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }

  Widget _buildModeSelector() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildModeButton('Rotate', Icons.rotate_right, 'rotate'),
          _buildModeButton('Crop', Icons.crop, 'crop'),
          _buildModeButton('Scale', Icons.zoom_in, 'scale'),
        ],
      ),
    );
  }

  Widget _buildModeButton(String label, IconData icon, String mode) {
    final isActive = _activeMode == mode;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _activeMode = mode);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.blue : Colors.grey[800],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? Colors.blue : Colors.grey[600]!,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? Colors.white : Colors.grey[400],
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.grey[400],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      height: 120,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          if (_activeMode == 'rotate') _buildRotateControls(),
          if (_activeMode == 'crop') _buildCropControls(),
          if (_activeMode == 'scale') _buildScaleControls(),
        ],
      ),
    );
  }

  Widget _buildRotateControls() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildQuickActionButton(
              'Rotate 90°',
              Icons.rotate_right,
              _rotate90Degrees,
            ),
            _buildQuickActionButton(
              'Flip H',
              Icons.flip,
              _flipHorizontal,
              isActive: widget.settings.flipHorizontal,
            ),
            _buildQuickActionButton(
              'Flip V',
              Icons.flip,
              _flipVertical,
              isActive: widget.settings.flipVertical,
              rotateIcon: 90,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Icon(Icons.rotate_left, color: Colors.white, size: 20),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: Colors.blue,
                  inactiveTrackColor: Colors.grey[600],
                  thumbColor: Colors.blue,
                  overlayColor: Colors.blue.withOpacity(0.2),
                ),
                child: Slider(
                  value: widget.settings.rotation,
                  min: 0,
                  max: 360,
                  divisions: 72,
                  onChanged: (value) {
                    widget.onSettingsChanged(
                      widget.settings.copyWith(rotation: value),
                    );
                  },
                ),
              ),
            ),
            const Icon(Icons.rotate_right, color: Colors.white, size: 20),
          ],
        ),
      ],
    );
  }

  Widget _buildCropControls() {
    return Column(
      children: [
        Text(
          'Drag to adjust crop area',
          style: TextStyle(color: Colors.grey[400], fontSize: 14),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildCropPresetButton('16:9', 16 / 9),
            _buildCropPresetButton('4:3', 4 / 3),
            _buildCropPresetButton('1:1', 1 / 1),
            _buildCropPresetButton('9:16', 9 / 16),
          ],
        ),
      ],
    );
  }

  Widget _buildScaleControls() {
    return Column(
      children: [
        Row(
          children: [
            const Text('Scale X:', style: TextStyle(color: Colors.white)),
            Expanded(
              child: Slider(
                value: widget.settings.scaleX,
                min: 0.5,
                max: 2.0,
                onChanged: (value) {
                  widget.onSettingsChanged(
                    widget.settings.copyWith(scaleX: value),
                  );
                },
              ),
            ),
          ],
        ),
        Row(
          children: [
            const Text('Scale Y:', style: TextStyle(color: Colors.white)),
            Expanded(
              child: Slider(
                value: widget.settings.scaleY,
                min: 0.5,
                max: 2.0,
                onChanged: (value) {
                  widget.onSettingsChanged(
                    widget.settings.copyWith(scaleY: value),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActionButton(
    String label,
    IconData icon,
    VoidCallback onTap, {
    bool isActive = false,
    double? rotateIcon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? Colors.blue : Colors.grey[800],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? Colors.blue : Colors.grey[600]!,
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.rotate(
              angle: (rotateIcon ?? 0) * math.pi / 180,
              child: Icon(
                icon,
                color: isActive ? Colors.white : Colors.grey[300],
                size: 20,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.grey[300],
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCropPresetButton(String label, double aspectRatio) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();

        double newWidth, newHeight;
        if (aspectRatio > 1) {
          newHeight = 0.8;
          newWidth = newHeight * aspectRatio;
          if (newWidth > 1.0) {
            newWidth = 1.0;
            newHeight = newWidth / aspectRatio;
          }
        } else {
          newWidth = 0.8;
          newHeight = newWidth / aspectRatio;
          if (newHeight > 1.0) {
            newHeight = 1.0;
            newWidth = newHeight * aspectRatio;
          }
        }

        widget.onSettingsChanged(
          widget.settings.copyWith(
            cropX: (1.0 - newWidth) / 2,
            cropY: (1.0 - newHeight) / 2,
            cropWidth: newWidth,
            cropHeight: newHeight,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[600]!, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.grey[300],
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomActions() {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border(top: BorderSide(color: Colors.grey[800]!)),
      ),
      child: Row(
        children: [
          if (widget.settings.hasChanges)
            Expanded(
              child: ElevatedButton(
                onPressed: _resetAll,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[800],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Reset'),
              ),
            ),
          if (widget.settings.hasChanges) const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, widget.settings),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Apply',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CropOverlayPainter extends CustomPainter {
  final double cropX;
  final double cropY;
  final double cropWidth;
  final double cropHeight;
  final bool isDragging;

  CropOverlayPainter({
    required this.cropX,
    required this.cropY,
    required this.cropWidth,
    required this.cropHeight,
    required this.isDragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.fill;

    final cropRect = Rect.fromLTWH(
      cropX * size.width,
      cropY * size.height,
      cropWidth * size.width,
      cropHeight * size.height,
    );

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(cropRect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawRect(cropRect, borderPaint);

    final handlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    const handleSize = 12.0;
    final handles = [
      Offset(cropRect.left, cropRect.top),
      Offset(cropRect.right, cropRect.top),
      Offset(cropRect.left, cropRect.bottom),
      Offset(cropRect.right, cropRect.bottom),
    ];

    for (final handle in handles) {
      canvas.drawRect(
        Rect.fromCenter(center: handle, width: handleSize, height: handleSize),
        handlePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CropOverlayPainter oldDelegate) {
    return cropX != oldDelegate.cropX ||
        cropY != oldDelegate.cropY ||
        cropWidth != oldDelegate.cropWidth ||
        cropHeight != oldDelegate.cropHeight ||
        isDragging != oldDelegate.isDragging;
  }
}
