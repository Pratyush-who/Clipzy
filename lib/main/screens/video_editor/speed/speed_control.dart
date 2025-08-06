import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;

class SpeedSettings {
  double speed;
  bool maintainPitch;
  String speedLabel;

  SpeedSettings({
    this.speed = 1.0,
    this.maintainPitch = true,
    this.speedLabel = '1x',
  });

  SpeedSettings copyWith({
    double? speed,
    bool? maintainPitch,
    String? speedLabel,
  }) {
    return SpeedSettings(
      speed: speed ?? this.speed,
      maintainPitch: maintainPitch ?? this.maintainPitch,
      speedLabel: speedLabel ?? this.speedLabel,
    );
  }

  static String getSpeedLabel(double speed) {
    if (speed == 0.25) return '0.25x';
    if (speed == 0.5) return '0.5x';
    if (speed == 0.75) return '0.75x';
    if (speed == 1.0) return '1x';
    if (speed == 1.25) return '1.25x';
    if (speed == 1.5) return '1.5x';
    if (speed == 2.0) return '2x';
    if (speed == 3.0) return '3x';
    if (speed == 4.0) return '4x';
    return '${speed.toStringAsFixed(2)}x';
  }
}

class SpeedControlWidget extends StatefulWidget {
  final SpeedSettings speedSettings;
  final Function(SpeedSettings) onSpeedChanged;
  final int? selectedClipIndex;
  final List<SpeedSettings>? clipSpeedSettings;
  final Function(int, SpeedSettings)? onClipSpeedChanged;

  const SpeedControlWidget({
    Key? key,
    required this.speedSettings,
    required this.onSpeedChanged,
    this.selectedClipIndex,
    this.clipSpeedSettings,
    this.onClipSpeedChanged,
  }) : super(key: key);

  @override
  State<SpeedControlWidget> createState() => _SpeedControlWidgetState();
}

class _SpeedControlWidgetState extends State<SpeedControlWidget>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _scaleController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _scaleAnimation;

  static const List<double> speedPresets = [
    0.25,
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
    3.0,
    4.0,
  ];

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  SpeedSettings get _currentSettings {
    if (widget.selectedClipIndex != null && widget.clipSpeedSettings != null) {
      return widget.clipSpeedSettings![widget.selectedClipIndex!];
    }
    return widget.speedSettings;
  }

  void _updateSpeed(double speed) {
    HapticFeedback.lightImpact();
    _scaleController.forward().then((_) => _scaleController.reverse());

    final newSettings = _currentSettings.copyWith(
      speed: speed,
      speedLabel: SpeedSettings.getSpeedLabel(speed),
    );

    if (widget.selectedClipIndex != null && widget.onClipSpeedChanged != null) {
      widget.onClipSpeedChanged!(widget.selectedClipIndex!, newSettings);
    } else {
      widget.onSpeedChanged(newSettings);
    }
  }

  void _toggleMaintainPitch() {
    HapticFeedback.lightImpact();
    final newSettings = _currentSettings.copyWith(
      maintainPitch: !_currentSettings.maintainPitch,
    );

    if (widget.selectedClipIndex != null && widget.onClipSpeedChanged != null) {
      widget.onClipSpeedChanged!(widget.selectedClipIndex!, newSettings);
    } else {
      widget.onSpeedChanged(newSettings);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _currentSettings;
    final isClipMode = widget.selectedClipIndex != null;

    return Container(
      padding: const EdgeInsets.all(20),
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

          Row(
            children: [
              Icon(
                _getSpeedIcon(settings.speed),
                color: _getSpeedColor(settings.speed),
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                isClipMode ? 'Clip Speed Control' : 'Global Speed Control',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          if (isClipMode) ...[
            const SizedBox(height: 8),
            Text(
              'Clip ${widget.selectedClipIndex! + 1}',
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
          ],

          const SizedBox(height: 30),

          AnimatedBuilder(
            animation: settings.speed != 1.0
                ? _pulseAnimation
                : const AlwaysStoppedAnimation(1.0),
            builder: (context, child) {
              return Transform.scale(
                scale:
                    _scaleAnimation.value *
                    (settings.speed != 1.0 ? _pulseAnimation.value : 1.0),
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    color: _getSpeedColor(settings.speed).withOpacity(0.2),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _getSpeedColor(settings.speed),
                      width: 4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _getSpeedColor(settings.speed).withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _getSpeedIcon(settings.speed),
                        color: _getSpeedColor(settings.speed),
                        size: 40,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        settings.speedLabel,
                        style: TextStyle(
                          color: _getSpeedColor(settings.speed),
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _getSpeedDescription(settings.speed),
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 30),

          Text(
            'Speed Presets',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 16),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: speedPresets.map((speed) {
              return _buildSpeedPreset(speed, settings.speed);
            }).toList(),
          ),

          const SizedBox(height: 30),

          Text(
            'Custom Speed',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              const Icon(
                Icons.slow_motion_video,
                color: Colors.white,
                size: 20,
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: _getSpeedColor(settings.speed),
                    inactiveTrackColor: Colors.grey[600],
                    thumbColor: _getSpeedColor(settings.speed),
                    overlayColor: _getSpeedColor(
                      settings.speed,
                    ).withOpacity(0.2),
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 12,
                    ),
                    trackHeight: 4,
                  ),
                  child: Slider(
                    value: settings.speed,
                    min: 0.1,
                    max: 5.0,
                    divisions: 49,
                    onChanged: _updateSpeed,
                  ),
                ),
              ),
              const Icon(Icons.fast_forward, color: Colors.white, size: 20),
            ],
          ),

          Text(
            'Current: ${settings.speedLabel}',
            style: TextStyle(
              color: _getSpeedColor(settings.speed),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[600]!, width: 1),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.music_note,
                  color: settings.maintainPitch
                      ? Colors.green
                      : Colors.grey[400],
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Maintain Pitch',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        'Keep audio pitch unchanged when adjusting speed',
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: settings.maintainPitch,
                  onChanged: (_) => _toggleMaintainPitch(),
                  activeColor: Colors.green,
                  inactiveThumbColor: Colors.grey[400],
                  inactiveTrackColor: Colors.grey[600],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          if (settings.speed != 1.0) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _getSpeedColor(settings.speed).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _getSpeedColor(settings.speed).withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: _getSpeedColor(settings.speed),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _getEffectDescription(settings.speed),
                      style: TextStyle(
                        color: _getSpeedColor(settings.speed),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          Row(
            children: [
              if (settings.speed != 1.0)
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _updateSpeed(1.0),
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
              if (settings.speed != 1.0) const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _getSpeedColor(settings.speed),
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
        ],
      ),
    );
  }

  Widget _buildSpeedPreset(double speed, double currentSpeed) {
    final isSelected = (speed - currentSpeed).abs() < 0.01;
    final label = SpeedSettings.getSpeedLabel(speed);

    return GestureDetector(
      onTap: () => _updateSpeed(speed),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? _getSpeedColor(speed) : Colors.grey[800],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? _getSpeedColor(speed) : Colors.grey[600]!,
            width: 2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _getSpeedColor(speed).withOpacity(0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[300],
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  IconData _getSpeedIcon(double speed) {
    if (speed < 0.5) return Icons.slow_motion_video;
    if (speed < 1.0) return Icons.play_arrow;
    if (speed == 1.0) return Icons.play_circle_outline;
    if (speed <= 2.0) return Icons.fast_forward;
    return Icons.fast_rewind;
  }

  Color _getSpeedColor(double speed) {
    if (speed < 0.75) return Colors.blue;
    if (speed < 1.0) return Colors.cyan;
    if (speed == 1.0) return Colors.green;
    if (speed <= 2.0) return Colors.orange;
    return Colors.red;
  }

  String _getSpeedDescription(double speed) {
    if (speed < 0.5) return 'Super Slow';
    if (speed < 1.0) return 'Slow Motion';
    if (speed == 1.0) return 'Normal';
    if (speed <= 2.0) return 'Fast';
    return 'Super Fast';
  }

  String _getEffectDescription(double speed) {
    if (speed < 0.5) {
      return 'Creates dramatic slow-motion effect';
    } else if (speed < 1.0) {
      return 'Slows down action for emphasis';
    } else if (speed <= 2.0) {
      return 'Speeds up for quick transitions';
    } else {
      return 'Creates time-lapse effect';
    }
  }
}
