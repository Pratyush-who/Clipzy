import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AudioSettings {
  bool isMuted;
  double volume;
  bool hasOriginalAudio;
  AudioSettings({
    this.isMuted = false,
    this.volume = 1.0,
    this.hasOriginalAudio = true,
  });

  AudioSettings copyWith({
    bool? isMuted,
    double? volume,
    bool? hasOriginalAudio,
  }) {
    return AudioSettings(
      isMuted: isMuted ?? this.isMuted,
      volume: volume ?? this.volume,
      hasOriginalAudio: hasOriginalAudio ?? this.hasOriginalAudio,
    );
  }
}

class SoundControlWidget extends StatefulWidget {
  final AudioSettings audioSettings;
  final Function(AudioSettings) onAudioSettingsChanged;
  final int? selectedClipIndex;
  final List<AudioSettings>? clipAudioSettings;
  final Function(int, AudioSettings)? onClipAudioSettingsChanged;

  const SoundControlWidget({
    Key? key,
    required this.audioSettings,
    required this.onAudioSettingsChanged,
    this.selectedClipIndex,
    this.clipAudioSettings,
    this.onClipAudioSettingsChanged,
  }) : super(key: key);

  @override
  State<SoundControlWidget> createState() => _SoundControlWidgetState();
}

class _SoundControlWidgetState extends State<SoundControlWidget>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _toggleMute() {
    HapticFeedback.lightImpact();
    _scaleController.forward().then((_) => _scaleController.reverse());

    if (widget.selectedClipIndex != null &&
        widget.clipAudioSettings != null &&
        widget.onClipAudioSettingsChanged != null) {
      final clipSettings = widget.clipAudioSettings![widget.selectedClipIndex!];
      widget.onClipAudioSettingsChanged!(
        widget.selectedClipIndex!,
        clipSettings.copyWith(isMuted: !clipSettings.isMuted),
      );
    } else {
      widget.onAudioSettingsChanged(
        widget.audioSettings.copyWith(isMuted: !widget.audioSettings.isMuted),
      );
    }
  }

  void _changeVolume(double volume) {
    if (widget.selectedClipIndex != null &&
        widget.clipAudioSettings != null &&
        widget.onClipAudioSettingsChanged != null) {
      final clipSettings = widget.clipAudioSettings![widget.selectedClipIndex!];
      widget.onClipAudioSettingsChanged!(
        widget.selectedClipIndex!,
        clipSettings.copyWith(volume: volume),
      );
    } else {
      widget.onAudioSettingsChanged(
        widget.audioSettings.copyWith(volume: volume),
      );
    }
  }

  AudioSettings get _currentSettings {
    if (widget.selectedClipIndex != null && widget.clipAudioSettings != null) {
      return widget.clipAudioSettings![widget.selectedClipIndex!];
    }
    return widget.audioSettings;
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
                settings.isMuted ? Icons.volume_off : Icons.volume_up,
                color: settings.isMuted ? Colors.red : Colors.blue,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                isClipMode ? 'Clip Audio Settings' : 'Global Audio Settings',
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
            animation: _scaleAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: GestureDetector(
                  onTap: _toggleMute,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: settings.isMuted
                          ? Colors.red.withOpacity(0.2)
                          : Colors.blue.withOpacity(0.2),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: settings.isMuted ? Colors.red : Colors.blue,
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (settings.isMuted ? Colors.red : Colors.blue)
                              .withOpacity(0.3),
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      settings.isMuted ? Icons.volume_off : Icons.volume_up,
                      color: settings.isMuted ? Colors.red : Colors.blue,
                      size: 48,
                    ),
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 20),

          Text(
            settings.isMuted ? 'Audio Muted' : 'Audio On',
            style: TextStyle(
              color: settings.isMuted ? Colors.red : Colors.blue,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 30),

          if (!settings.isMuted) ...[
            Row(
              children: [
                const Icon(Icons.volume_down, color: Colors.white),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: Colors.blue,
                      inactiveTrackColor: Colors.grey[600],
                      thumbColor: Colors.blue,
                      overlayColor: Colors.blue.withOpacity(0.2),
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 12,
                      ),
                      trackHeight: 4,
                    ),
                    child: Slider(
                      value: settings.volume,
                      onChanged: _changeVolume,
                      min: 0.0,
                      max: 2.0,
                      divisions: 20,
                    ),
                  ),
                ),
                const Icon(Icons.volume_up, color: Colors.white),
              ],
            ),

            Text(
              'Volume: ${(settings.volume * 100).round()}%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),

            const SizedBox(height: 20),
          ],

          TextButton(
            onPressed: () {
              setState(() => _showAdvanced = !_showAdvanced);
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Advanced Options',
                  style: TextStyle(color: Colors.grey[400]),
                ),
                const SizedBox(width: 8),
                Icon(
                  _showAdvanced ? Icons.expand_less : Icons.expand_more,
                  color: Colors.grey[400],
                ),
              ],
            ),
          ),

          if (_showAdvanced) ...[
            const Divider(color: Colors.grey),
            const SizedBox(height: 16),

            Text(
              'Quick Volume Presets',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 12),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildVolumePreset('25%', 0.25),
                _buildVolumePreset('50%', 0.5),
                _buildVolumePreset('75%', 0.75),
                _buildVolumePreset('100%', 1.0),
                _buildVolumePreset('150%', 1.5),
              ],
            ),

            const SizedBox(height: 20),

            Text(
              'Audio Effects',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 12),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildEffectButton('Fade In', Icons.trending_up, false),
                _buildEffectButton('Fade Out', Icons.trending_down, false),
                _buildEffectButton('Echo', Icons.graphic_eq, false),
              ],
            ),
          ],

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey[800],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Done',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVolumePreset(String label, double volume) {
    final isSelected = (_currentSettings.volume - volume).abs() < 0.05;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _changeVolume(volume);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue : Colors.grey[800],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey[600]!,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[300],
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildEffectButton(String label, IconData icon, bool isEnabled) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isEnabled ? Colors.purple : Colors.grey[800],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isEnabled ? Colors.purple : Colors.grey[600]!,
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isEnabled ? Colors.white : Colors.grey[400],
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isEnabled ? Colors.white : Colors.grey[400],
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
