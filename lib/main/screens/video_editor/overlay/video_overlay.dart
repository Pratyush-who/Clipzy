import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_sound/flutter_sound.dart';

class VoiceOverlay {
  String id;
  String audioPath;
  double startTime;
  double endTime;
  double volume;
  bool isMuted;
  String name;

  VoiceOverlay({
    required this.id,
    required this.audioPath,
    required this.startTime,
    required this.endTime,
    this.volume = 1.0,
    this.isMuted = false,
    this.name = 'Voice Over',
  });

  VoiceOverlay copyWith({
    String? id,
    String? audioPath,
    double? startTime,
    double? endTime,
    double? volume,
    bool? isMuted,
    String? name,
  }) {
    return VoiceOverlay(
      id: id ?? this.id,
      audioPath: audioPath ?? this.audioPath,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      volume: volume ?? this.volume,
      isMuted: isMuted ?? this.isMuted,
      name: name ?? this.name,
    );
  }

  double get duration => endTime - startTime;
}

class VoiceRecordingWidget extends StatefulWidget {
  final Function(String audioPath, double startTime, double duration)
  onVoiceRecorded;
  final double currentTime;
  final double totalDuration;

  const VoiceRecordingWidget({
    Key? key,
    required this.onVoiceRecorded,
    required this.currentTime,
    required this.totalDuration,
  }) : super(key: key);

  @override
  State<VoiceRecordingWidget> createState() => _VoiceRecordingWidgetState();
}

class _VoiceRecordingWidgetState extends State<VoiceRecordingWidget>
    with TickerProviderStateMixin {
  FlutterSoundRecorder? _recorder;
  bool _isRecording = false;
  bool _isRecorderInitialized = false;
  String? _recordingPath;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;

  late AnimationController _pulseController;
  late AnimationController _scaleController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _initializeRecorder();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  Future<void> _initializeRecorder() async {
    _recorder = FlutterSoundRecorder();

    try {
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        throw Exception('Microphone permission not granted');
      }

      await _recorder!.openRecorder();
      setState(() {
        _isRecorderInitialized = true;
      });
    } catch (e) {
      print('Error initializing recorder: $e');
    }
  }

  @override
  void dispose() {
    _recorder?.closeRecorder();
    _recordingTimer?.cancel();
    _pulseController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (!_isRecorderInitialized || _recorder == null) return;

    try {
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _recordingPath = '${directory.path}/voice_recording_$timestamp.aac';

      await _recorder!.startRecorder(
        toFile: _recordingPath,
        codec: Codec.aacADTS,
      );

      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
      });

      _pulseController.repeat(reverse: true);

      _recordingTimer = Timer.periodic(const Duration(milliseconds: 100), (
        timer,
      ) {
        if (mounted) {
          setState(() {
            _recordingDuration = Duration(milliseconds: timer.tick * 100);
          });
        }
      });

      HapticFeedback.mediumImpact();
    } catch (e) {
      print('Error starting recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording || _recorder == null) return;

    try {
      await _recorder!.stopRecorder();
      _recordingTimer?.cancel();
      _pulseController.stop();

      setState(() {
        _isRecording = false;
      });

      if (_recordingPath != null && _recordingDuration.inSeconds > 0) {
        widget.onVoiceRecorded(
          _recordingPath!,
          widget.currentTime,
          _recordingDuration.inMilliseconds / 1000.0,
        );
      }

      HapticFeedback.lightImpact();
    } catch (e) {
      print('Error stopping recording: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
              const Icon(Icons.mic, color: Colors.red, size: 24),
              const SizedBox(width: 12),
              const Text(
                'Voice Recording',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 30),

          if (_isRecording) ...[
            Text(
              'Recording: ${_formatDuration(_recordingDuration)}',
              style: TextStyle(
                color: Colors.red,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.2),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.red, width: 3),
                    ),
                    child: const Icon(Icons.mic, color: Colors.red, size: 48),
                  ),
                );
              },
            ),
          ] else ...[
            Text(
              'Tap to start recording',
              style: TextStyle(color: Colors.grey[400], fontSize: 16),
            ),
            const SizedBox(height: 20),
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.grey[800],
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey[600]!, width: 2),
              ),
              child: Icon(Icons.mic, color: Colors.grey[400], size: 48),
            ),
          ],

          const SizedBox(height: 30),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (_isRecording)
                ElevatedButton.icon(
                  onPressed: _stopRecording,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: _isRecorderInitialized ? _startRecording : null,
                  icon: const Icon(Icons.fiber_manual_record),
                  label: const Text('Record'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                ),

              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey[400]),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          if (!_isRecorderInitialized)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange, width: 1),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Microphone permission required for voice recording',
                      style: TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class VoiceTimelineStrip extends StatefulWidget {
  final List<VoiceOverlay> voiceOverlays;
  final double totalDuration;
  final double currentTime;
  final double timelineWidth;
  final double pixelsPerSecond;
  final Function(String id, double startTime, double endTime)
  onOverlayTimeChanged;
  final Function(String id) onOverlaySelected;
  final Function(String id) onOverlayDeleted;
  final Function(String id, double volume) onVolumeChanged;

  const VoiceTimelineStrip({
    Key? key,
    required this.voiceOverlays,
    required this.totalDuration,
    required this.currentTime,
    required this.timelineWidth,
    required this.pixelsPerSecond,
    required this.onOverlayTimeChanged,
    required this.onOverlaySelected,
    required this.onOverlayDeleted,
    required this.onVolumeChanged,
  }) : super(key: key);

  @override
  State<VoiceTimelineStrip> createState() => _VoiceTimelineStripState();
}

class _VoiceTimelineStripState extends State<VoiceTimelineStrip> {
  String? _selectedOverlayId;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      child: Stack(
        children: [
          Container(
            width: widget.timelineWidth,
            height: 35,
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.pink[900]!, Colors.pink[700]!],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
          ),

          ...widget.voiceOverlays.map((overlay) => _buildVoiceBlock(overlay)),
        ],
      ),
    );
  }

  Widget _buildVoiceBlock(VoiceOverlay overlay) {
    final blockWidth = overlay.duration * widget.pixelsPerSecond;
    final blockLeft = overlay.startTime * widget.pixelsPerSecond;
    final isSelected = _selectedOverlayId == overlay.id;

    return Positioned(
      left: blockLeft,
      top: 8,
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedOverlayId = overlay.id);
          widget.onOverlaySelected(overlay.id);
        },
        onLongPress: () => _showVoiceOptions(overlay),
        child: Container(
          width: blockWidth.clamp(60.0, double.infinity),
          height: 35,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isSelected
                  ? [Colors.red[400]!, Colors.red[600]!]
                  : [Colors.pink[400]!, Colors.pink[600]!],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? Colors.white : Colors.transparent,
              width: 2,
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      overlay.isMuted ? Icons.mic_off : Icons.mic,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      overlay.name.length > 8
                          ? '${overlay.name.substring(0, 8)}...'
                          : overlay.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (!overlay.isMuted)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    width: 12,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: overlay.volume,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showVoiceOptions(VoiceOverlay overlay) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Voice Overlay Options',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                const Icon(Icons.volume_up, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Slider(
                    value: overlay.volume,
                    onChanged: (value) {
                      widget.onVolumeChanged(overlay.id, value);
                    },
                    activeColor: Colors.red,
                    inactiveColor: Colors.grey[600],
                  ),
                ),
                Text(
                  '${(overlay.volume * 100).round()}%',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),

            const SizedBox(height: 20),

            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                widget.onOverlayDeleted(overlay.id);
              },
              icon: const Icon(Icons.delete),
              label: const Text('Delete'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
