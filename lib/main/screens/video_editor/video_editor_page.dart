import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:async';
import 'package:clipzy/main/screens/video_editor/crop/croprotate.dart';
import 'package:clipzy/main/screens/video_editor/save/save.dart';
import 'package:clipzy/main/screens/video_editor/sound/soundonoff.dart';
import 'package:clipzy/main/screens/video_editor/speed/speed_control.dart';
import 'package:clipzy/main/screens/video_editor/text/TextOverlay.dart';
import 'package:clipzy/main/screens/video_editor/overlay/video_overlay.dart';
import 'package:clipzy/models/video_clip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class VideoEditorPage extends StatefulWidget {
  final List<File> files;

  const VideoEditorPage({Key? key, required this.files}) : super(key: key);

  @override
  State<VideoEditorPage> createState() => _VideoEditorPageState();
}

class _VideoEditorPageState extends State<VideoEditorPage>
    with TickerProviderStateMixin {
  VideoPlayerController? _playerController;
  List<VideoClip> _clips = [];
  List<TextOverlay> _textOverlays = [];
  List<VoiceOverlay> _voiceOverlays = [];

  AudioSettings _globalAudioSettings = AudioSettings();
  List<AudioSettings> _clipAudioSettings = [];
  List<CropRotateSettings> _clipCropRotateSettings = [];
  List<SpeedSettings> _clipSpeedSettings = [];

  int? _selectedClipIndex;
  String? _selectedTextOverlayId;
  double _currentGlobalPosition = 0.0;
  double _timelineScale = 1.0;
  bool _isPlaying = false;
  bool _isInitialized = false;
  bool _isExporting = false;
  bool _isTrimming = false;
  int? _activeTrimHandle;
  ScrollController _timelineScrollController = ScrollController();
  ScrollController _bottomToolbarScrollController = ScrollController();
  Timer? _playbackTimer;
  bool _shouldPlayNextClip = false;
  bool _isDisposed = false;

  late AnimationController _scaleController;
  late AnimationController _fadeController;
  late AnimationController _loadingController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _loadingAnimation;

  static const double _trackHeight = 70.0;
  static const double _pixelsPerSecond = 35.0;
  static const double _minClipDurationSeconds = 0.5;
  static const double _handleWidth = 60.0;
  static const double _handleTouchArea = 100.0;
  List<List<Uint8List>> _clipThumbnails = [];

  @override
  void initState() {
    super.initState();
    print('=== VideoEditorPage initState ===');
    print('Files passed to editor: ${widget.files.length}');

    _initializeAnimations();
    _initializeClips();
  }

  void _initializeAnimations() {
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _loadingController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOutBack),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));

    _loadingAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _loadingController, curve: Curves.easeInOut),
    );

    _fadeController.forward();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _playerController?.removeListener(_videoListener);
    _playerController?.dispose();
    _timelineScrollController.dispose();
    _bottomToolbarScrollController.dispose();
    _playbackTimer?.cancel();
    _scaleController.dispose();
    _fadeController.dispose();
    _loadingController.dispose();
    super.dispose();
  }

  void _videoListener() {
    if (_isDisposed ||
        !mounted ||
        _playerController == null ||
        !_playerController!.value.isInitialized)
      return;

    final controller = _playerController!;
    final position = controller.value.position;

    if (_selectedClipIndex != null && _selectedClipIndex! < _clips.length) {
      final selectedClip = _clips[_selectedClipIndex!];

      if (position >= selectedClip.endTrim) {
        if (_shouldPlayNextClip && _selectedClipIndex! < _clips.length - 1) {
          _playNextClip();
          return;
        } else {
          controller.pause();
          if (mounted) {
            setState(() {
              _isPlaying = false;
              _shouldPlayNextClip = false;
            });
          }
          return;
        }
      }

      if (position < selectedClip.startTrim) {
        _seekToClipStart();
        return;
      }

      double globalPosition =
          selectedClip.trackPosition +
          (position - selectedClip.startTrim).inMilliseconds / 1000.0;

      if (mounted) {
        setState(() {
          _currentGlobalPosition = globalPosition.clamp(0.0, _totalDuration);
          _isPlaying = controller.value.isPlaying;
        });

        _autoScrollToPlayhead();
      }
    }
  }

  void _autoScrollToPlayhead() {
    if (_isTrimming || !_timelineScrollController.hasClients) return;

    final playheadPosition =
        _currentGlobalPosition * _pixelsPerSecond * _timelineScale;
    final screenWidth = MediaQuery.of(context).size.width - 40;
    final currentScrollOffset = _timelineScrollController.offset;

    if (playheadPosition < currentScrollOffset ||
        playheadPosition > currentScrollOffset + screenWidth) {
      final targetScrollOffset = playheadPosition - (screenWidth / 2);
      final maxScrollOffset =
          _timelineScrollController.position.maxScrollExtent;

      _timelineScrollController.animateTo(
        targetScrollOffset.clamp(0.0, maxScrollOffset),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _seekToClipStart() async {
    if (_selectedClipIndex == null || _selectedClipIndex! >= _clips.length)
      return;

    final clip = _clips[_selectedClipIndex!];
    await _playerController?.seekTo(clip.startTrim);

    if (!_isPlaying) {
      await _playerController?.pause();
    }
  }

  void _playNextClip() async {
    if (_selectedClipIndex == null ||
        _selectedClipIndex! >= _clips.length - 1) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _shouldPlayNextClip = false;
        });
      }
      return;
    }

    await _loadClipInPlayer(_selectedClipIndex! + 1, autoPlay: true);
  }

  Future<void> _loadClipInPlayer(
    int clipIndex, {
    bool autoPlay = false,
    Duration? seekTo,
  }) async {
    if (clipIndex >= _clips.length || clipIndex < 0) return;

    try {
      if (_playerController != null) {
        _playerController!.removeListener(_videoListener);
        await _playerController!.dispose();
        _playerController = null;
      }

      final clip = _clips[clipIndex];
      if (!await clip.file.exists()) {
        if (mounted) {
          setState(() => _selectedClipIndex = clipIndex);
        }
        return;
      }

      _playerController = VideoPlayerController.file(clip.file);
      await _playerController!.initialize();

      if (!_playerController!.value.isInitialized) return;

      if (mounted) {
        setState(() => _selectedClipIndex = clipIndex);
      }

      _playerController!.addListener(_videoListener);

      final seekPosition = seekTo ?? clip.startTrim;
      final clampedSeekPosition = Duration(
        milliseconds: seekPosition.inMilliseconds.clamp(
          clip.startTrim.inMilliseconds,
          clip.endTrim.inMilliseconds,
        ),
      );
      await _playerController!.seekTo(clampedSeekPosition);

      if (autoPlay && mounted) {
        await _playerController!.play();
        setState(() {
          _shouldPlayNextClip = true;
        });
      }
    } catch (e) {
      print('Error loading clip: $e');
      if (mounted) {
        setState(() => _selectedClipIndex = clipIndex);
      }
    }
  }

  void _playPause() {
    if (_playerController == null) return;

    if (_isPlaying) {
      _playerController!.pause();
      if (mounted) {
        setState(() {
          _shouldPlayNextClip = false;
        });
      }
    } else {
      if (_selectedClipIndex != null && _selectedClipIndex! < _clips.length) {
        final clip = _clips[_selectedClipIndex!];
        final currentPos = _playerController!.value.position;

        if (currentPos < clip.startTrim || currentPos >= clip.endTrim) {
          _playerController!.seekTo(clip.startTrim);
        }
      }
      _playerController!.play();
      if (mounted) {
        setState(() {
          _shouldPlayNextClip = true;
        });
      }
    }
  }

  void _splitClip() async {
    if (_selectedClipIndex == null ||
        _playerController == null ||
        _selectedClipIndex! >= _clips.length)
      return;

    final currentClip = _clips[_selectedClipIndex!];
    final currentPosition = _playerController!.value.position;

    if (currentPosition <= currentClip.startTrim ||
        currentPosition >= currentClip.endTrim)
      return;

    final firstPartDuration = currentPosition - currentClip.startTrim;
    final secondPartDuration = currentClip.endTrim - currentPosition;

    if (firstPartDuration.inMilliseconds < _minClipDurationSeconds * 1000 ||
        secondPartDuration.inMilliseconds < _minClipDurationSeconds * 1000) {
      _showSnackBar('Cannot split: resulting clips would be too short');
      return;
    }

    final firstClip = currentClip.copyWith(
      id: '${currentClip.id}_part1_${DateTime.now().millisecondsSinceEpoch}',
      endTrim: currentPosition,
    );

    final secondClip = currentClip.copyWith(
      id: '${currentClip.id}_part2_${DateTime.now().millisecondsSinceEpoch}',
      startTrim: currentPosition,
    );

    List<Uint8List> firstThumbs = [];
    List<Uint8List> secondThumbs = [];

    try {
      final firstThumbCount = max(
        3,
        (firstPartDuration.inSeconds / 2).ceil().clamp(3, 8),
      );
      for (int t = 0; t < firstThumbCount; t++) {
        final thumbData = await VideoThumbnail.thumbnailData(
          video: currentClip.file.path,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 80,
          quality: 70,
          timeMs:
              (currentClip.startTrim.inMilliseconds +
                      (firstPartDuration.inMilliseconds * t / firstThumbCount))
                  .round(),
        );
        if (thumbData != null) {
          firstThumbs.add(thumbData);
        }
      }

      final secondThumbCount = max(
        3,
        (secondPartDuration.inSeconds / 2).ceil().clamp(3, 8),
      );
      for (int t = 0; t < secondThumbCount; t++) {
        final thumbData = await VideoThumbnail.thumbnailData(
          video: currentClip.file.path,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 80,
          quality: 70,
          timeMs:
              (currentPosition.inMilliseconds +
                      (secondPartDuration.inMilliseconds *
                          t /
                          secondThumbCount))
                  .round(),
        );
        if (thumbData != null) {
          secondThumbs.add(thumbData);
        }
      }
    } catch (e) {
      print('Error generating thumbnails for split: $e');
    }

    if (mounted) {
      setState(() {
        _clips.removeAt(_selectedClipIndex!);
        _clips.insertAll(_selectedClipIndex!, [firstClip, secondClip]);
        _clipThumbnails.removeAt(_selectedClipIndex!);
        _clipThumbnails.insertAll(_selectedClipIndex!, [
          firstThumbs,
          secondThumbs,
        ]);

        final currentAudioSettings =
            _selectedClipIndex! < _clipAudioSettings.length
            ? _clipAudioSettings[_selectedClipIndex!]
            : AudioSettings();
        final currentCropSettings =
            _selectedClipIndex! < _clipCropRotateSettings.length
            ? _clipCropRotateSettings[_selectedClipIndex!]
            : CropRotateSettings();
        final currentSpeedSettings =
            _selectedClipIndex! < _clipSpeedSettings.length
            ? _clipSpeedSettings[_selectedClipIndex!]
            : SpeedSettings();

        if (_selectedClipIndex! < _clipAudioSettings.length) {
          _clipAudioSettings.removeAt(_selectedClipIndex!);
        }
        if (_selectedClipIndex! < _clipCropRotateSettings.length) {
          _clipCropRotateSettings.removeAt(_selectedClipIndex!);
        }
        if (_selectedClipIndex! < _clipSpeedSettings.length) {
          _clipSpeedSettings.removeAt(_selectedClipIndex!);
        }

        _clipAudioSettings.insertAll(_selectedClipIndex!, [
          currentAudioSettings,
          currentAudioSettings,
        ]);
        _clipCropRotateSettings.insertAll(_selectedClipIndex!, [
          currentCropSettings,
          currentCropSettings,
        ]);
        _clipSpeedSettings.insertAll(_selectedClipIndex!, [
          currentSpeedSettings,
          currentSpeedSettings,
        ]);

        _recalculateClipPositions();
      });
    }

    _loadClipInPlayer(_selectedClipIndex!);
  }

  void _trimClip(int clipIndex, Duration newStart, Duration newEnd) {
    if (clipIndex >= _clips.length || clipIndex < 0) return;

    final clip = _clips[clipIndex];

    newStart = Duration(
      milliseconds: newStart.inMilliseconds.clamp(
        0,
        clip.originalDuration.inMilliseconds,
      ),
    );
    newEnd = Duration(
      milliseconds: newEnd.inMilliseconds.clamp(
        0,
        clip.originalDuration.inMilliseconds,
      ),
    );

    if (newStart >= newEnd) return;
    if ((newEnd - newStart).inMilliseconds < _minClipDurationSeconds * 1000)
      return;

    if (mounted) {
      setState(() {
        _clips[clipIndex] = clip.copyWith(startTrim: newStart, endTrim: newEnd);
        _recalculateClipPositions();
      });
    }

    if (_selectedClipIndex == clipIndex && _playerController != null) {
      final currentPos = _playerController!.value.position;
      if (currentPos < newStart || currentPos > newEnd) {
        _playerController!.seekTo(newStart);
      }
    }
  }

  void _recalculateClipPositions() {
    double position = 0.0;
    for (int i = 0; i < _clips.length; i++) {
      _clips[i] = _clips[i].copyWith(trackPosition: position);
      position += _clips[i].trimmedDuration.inMilliseconds / 1000.0;
    }
  }

  void _seekToGlobalPosition(double seconds) async {
    if (_clips.isEmpty || _isTrimming) return;

    seconds = seconds.clamp(0.0, _totalDuration);
    double cumulativeTime = 0.0;

    for (int i = 0; i < _clips.length; i++) {
      final clip = _clips[i];
      final clipDuration = clip.trimmedDuration.inMilliseconds / 1000.0;

      if (seconds >= cumulativeTime &&
          seconds < cumulativeTime + clipDuration) {
        final offsetInClip = seconds - cumulativeTime;
        final seekPosition =
            clip.startTrim +
            Duration(milliseconds: (offsetInClip * 1000).round());

        await _loadClipInPlayer(
          i,
          autoPlay: _isPlaying,
          seekTo: Duration(
            milliseconds: seekPosition.inMilliseconds.clamp(
              clip.startTrim.inMilliseconds,
              clip.endTrim.inMilliseconds,
            ),
          ),
        );

        if (mounted) {
          setState(() => _currentGlobalPosition = seconds);
        }
        return;
      }
      cumulativeTime += clipDuration;
    }
  }

  void _addTextOverlay() {
    final newOverlay = TextOverlay(
      id: 'text_${DateTime.now().millisecondsSinceEpoch}',
      text: 'Tap to edit',
      position: const Offset(0.1, 0.1),
      startTime: _currentGlobalPosition,
      endTime: (_currentGlobalPosition + 3.0).clamp(0.0, _totalDuration),
    );

    if (mounted) {
      setState(() {
        _textOverlays.add(newOverlay);
        _selectedTextOverlayId = newOverlay.id;
        _selectedClipIndex = null;

        for (int i = 0; i < _textOverlays.length - 1; i++) {
          _textOverlays[i] = _textOverlays[i].copyWith(isSelected: false);
        }
        _textOverlays.last = _textOverlays.last.copyWith(isSelected: true);
      });
    }

    Future.delayed(const Duration(milliseconds: 100), () {
      _editTextOverlay(newOverlay.id);
    });
  }

  void _updateTextOverlayPosition(String id, Offset position) {
    final index = _textOverlays.indexWhere((overlay) => overlay.id == id);
    if (index != -1 && mounted) {
      setState(() {
        _textOverlays[index] = _textOverlays[index].copyWith(
          position: position,
        );
      });
    }
  }

  void _selectTextOverlay(String id) {
    if (mounted) {
      setState(() {
        for (int i = 0; i < _textOverlays.length; i++) {
          _textOverlays[i] = _textOverlays[i].copyWith(isSelected: false);
        }

        final index = _textOverlays.indexWhere((overlay) => overlay.id == id);
        if (index != -1) {
          _textOverlays[index] = _textOverlays[index].copyWith(
            isSelected: true,
          );
          _selectedTextOverlayId = id;
        }

        _selectedClipIndex = null;
      });
    }
  }

  void _editTextOverlay(String id) {
    final overlay = _textOverlays.firstWhere((o) => o.id == id);
    showDialog(
      context: context,
      builder: (context) => TextEditDialog(
        initialText: overlay.text,
        onTextChanged: (newText) {
          final index = _textOverlays.indexWhere((o) => o.id == id);
          if (index != -1 && mounted) {
            setState(() {
              _textOverlays[index] = _textOverlays[index].copyWith(
                text: newText,
              );
            });
          }
        },
      ),
    );
  }

  void _updateTextOverlayTime(String id, double startTime, double endTime) {
    final index = _textOverlays.indexWhere((overlay) => overlay.id == id);
    if (index != -1 && mounted) {
      setState(() {
        _textOverlays[index] = _textOverlays[index].copyWith(
          startTime: startTime,
          endTime: endTime,
        );
      });
    }
  }

  void _deleteTextOverlay(String id) {
    final index = _textOverlays.indexWhere((overlay) => overlay.id == id);
    if (index != -1 && mounted) {
      setState(() {
        _textOverlays.removeAt(index);
        if (_selectedTextOverlayId == id) {
          _selectedTextOverlayId = null;
        }
      });
    }
  }

  void _addVoiceOverlay() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => VoiceRecordingWidget(
        onVoiceRecorded: (String audioPath, double startTime, double duration) {
          final newVoiceOverlay = VoiceOverlay(
            id: 'voice_${DateTime.now().millisecondsSinceEpoch}',
            audioPath: audioPath,
            startTime: startTime,
            endTime: startTime + duration,
            name: 'Voice ${_voiceOverlays.length + 1}',
          );

          if (mounted) {
            setState(() {
              _voiceOverlays.add(newVoiceOverlay);
            });
          }
        },
        currentTime: _currentGlobalPosition,
        totalDuration: _totalDuration,
      ),
    );
  }

  void _updateVoiceOverlayTime(String id, double startTime, double endTime) {
    final index = _voiceOverlays.indexWhere((overlay) => overlay.id == id);
    if (index != -1 && mounted) {
      setState(() {
        _voiceOverlays[index] = _voiceOverlays[index].copyWith(
          startTime: startTime,
          endTime: endTime,
        );
      });
    }
  }

  void _selectVoiceOverlay(String id) {
    final overlay = _voiceOverlays.firstWhere((o) => o.id == id);
    _seekToGlobalPosition(overlay.startTime);
  }

  void _deleteVoiceOverlay(String id) {
    final index = _voiceOverlays.indexWhere((overlay) => overlay.id == id);
    if (index != -1 && mounted) {
      setState(() {
        _voiceOverlays.removeAt(index);
      });
    }
  }

  void _updateVoiceOverlayVolume(String id, double volume) {
    final index = _voiceOverlays.indexWhere((overlay) => overlay.id == id);
    if (index != -1 && mounted) {
      setState(() {
        _voiceOverlays[index] = _voiceOverlays[index].copyWith(volume: volume);
      });
    }
  }

  void _showSoundControl() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => SoundControlWidget(
        audioSettings: _globalAudioSettings,
        onAudioSettingsChanged: (settings) {
          setState(() => _globalAudioSettings = settings);
        },
        selectedClipIndex: _selectedClipIndex,
        clipAudioSettings: _clipAudioSettings,
        onClipAudioSettingsChanged: (index, settings) {
          if (index < _clipAudioSettings.length) {
            setState(() => _clipAudioSettings[index] = settings);
          } else {
            while (_clipAudioSettings.length <= index) {
              _clipAudioSettings.add(AudioSettings());
            }
            setState(() => _clipAudioSettings[index] = settings);
          }
        },
      ),
    );
  }

  void _showCropRotate() {
    if (_selectedClipIndex == null || _playerController == null) return;

    while (_clipCropRotateSettings.length <= _selectedClipIndex!) {
      _clipCropRotateSettings.add(CropRotateSettings());
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CropRotateWidget(
          settings: _clipCropRotateSettings[_selectedClipIndex!],
          onSettingsChanged: (settings) {
            setState(() {
              _clipCropRotateSettings[_selectedClipIndex!] = settings;
            });
          },
          videoPreview: _playerController != null
              ? VideoPlayer(_playerController!)
              : Container(),
          videoSize: _playerController?.value.size ?? Size.zero,
        ),
      ),
    ).then((result) {
      if (result != null && result is CropRotateSettings) {
        setState(() {
          _clipCropRotateSettings[_selectedClipIndex!] = result;
        });
      }
    });
  }

  void _showSpeedControl() {
    if (_selectedClipIndex == null || _selectedClipIndex! >= _clips.length)
      return;

    while (_clipSpeedSettings.length <= _selectedClipIndex!) {
      _clipSpeedSettings.add(SpeedSettings());
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => SpeedControlWidget(
        speedSettings: _clipSpeedSettings[_selectedClipIndex!],
        onSpeedChanged: (settings) {
          setState(() {
            _clipSpeedSettings[_selectedClipIndex!] = settings;
          });
        },
        selectedClipIndex: _selectedClipIndex,
        clipSpeedSettings: _clipSpeedSettings,
        onClipSpeedChanged: (index, settings) {
          if (index < _clipSpeedSettings.length) {
            setState(() => _clipSpeedSettings[index] = settings);
          } else {
            while (_clipSpeedSettings.length <= index) {
              _clipSpeedSettings.add(SpeedSettings());
            }
            setState(() => _clipSpeedSettings[index] = settings);
          }
        },
      ),
    );
  }

  void _showSaveDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => SaveLocalWidget(
        videoPath: '',
        onVideoSaved: (String savedPath, String name) {
          _showSnackBar('Video saved successfully as $name');
        },
        onCancel: () => Navigator.pop(context),
      ),
    );
  }

  Future<void> _exportVideoWithOptions(
    String outputPath,
    Map<String, dynamic> options,
  ) async {
    if (_clips.isEmpty || _isExporting) return;

    if (mounted) {
      setState(() => _isExporting = true);
    }

    try {
      final result = await _exportVideoToPath(outputPath, options);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result ? 'Video saved successfully!' : 'Failed to save video',
            ),
            backgroundColor: result ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving video: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<bool> _exportVideoToPath(
    String outputPath,
    Map<String, dynamic> options,
  ) async {
    return await _exportVideo();
  }

  List<TextOverlay> get _activeTextOverlays {
    return _textOverlays.where((overlay) {
      return _currentGlobalPosition >= overlay.startTime &&
          _currentGlobalPosition <= overlay.endTime;
    }).toList();
  }

  List<VoiceOverlay> get _activeVoiceOverlays {
    return _voiceOverlays.where((overlay) {
      return _currentGlobalPosition >= overlay.startTime &&
          _currentGlobalPosition <= overlay.endTime;
    }).toList();
  }

  Future<bool> _exportVideo() async {
    if (_clips.isEmpty || _isExporting) return false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.blue),
            const SizedBox(height: 16),
            const Text(
              'Exporting video...',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      ),
    );

    if (mounted) {
      setState(() => _isExporting = true);
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      final outputPath =
          '${directory.path}/edited_video_${DateTime.now().millisecondsSinceEpoch}.mp4';

      List<String> inputs = [];
      List<String> filterComplex = [];

      for (int i = 0; i < _clips.length; i++) {
        final clip = _clips[i];
        final audioSettings = i < _clipAudioSettings.length
            ? _clipAudioSettings[i]
            : AudioSettings();
        final cropSettings = i < _clipCropRotateSettings.length
            ? _clipCropRotateSettings[i]
            : CropRotateSettings();
        final speedSettings = i < _clipSpeedSettings.length
            ? _clipSpeedSettings[i]
            : SpeedSettings();

        inputs.add('-i "${clip.file.path}"');

        final startSeconds = clip.startTrim.inMilliseconds / 1000.0;
        final durationSeconds = clip.trimmedDuration.inMilliseconds / 1000.0;

        String videoFilter =
            '[$i:v]trim=start=$startSeconds:duration=$durationSeconds,setpts=PTS-STARTPTS';

        if (speedSettings.speed != 1.0) {
          videoFilter += ',setpts=${1.0 / speedSettings.speed}*PTS';
        }

        if (cropSettings.hasChanges) {
          if (cropSettings.rotation != 0.0) {
            videoFilter += ',rotate=${cropSettings.rotation * 3.14159 / 180}';
          }
          if (cropSettings.cropWidth != 1.0 || cropSettings.cropHeight != 1.0) {
            final cropW = 'iw*${cropSettings.cropWidth}';
            final cropH = 'ih*${cropSettings.cropHeight}';
            final cropX = 'iw*${cropSettings.cropX}';
            final cropY = 'ih*${cropSettings.cropY}';
            videoFilter += ',crop=$cropW:$cropH:$cropX:$cropY';
          }
          if (cropSettings.scaleX != 1.0 || cropSettings.scaleY != 1.0) {
            videoFilter +=
                ',scale=iw*${cropSettings.scaleX}:ih*${cropSettings.scaleY}';
          }
          if (cropSettings.flipHorizontal) {
            videoFilter += ',hflip';
          }
          if (cropSettings.flipVertical) {
            videoFilter += ',vflip';
          }
        }

        videoFilter += '[v$i]';
        filterComplex.add(videoFilter);

        String audioFilter =
            '[$i:a]atrim=start=$startSeconds:duration=$durationSeconds,asetpts=PTS-STARTPTS';

        if (audioSettings.isMuted) {
          audioFilter += ',volume=0';
        } else if (audioSettings.volume != 1.0) {
          audioFilter += ',volume=${audioSettings.volume}';
        }

        if (speedSettings.speed != 1.0) {
          if (speedSettings.maintainPitch) {
            audioFilter += ',atempo=${speedSettings.speed}';
          } else {
            audioFilter +=
                ',asetrate=44100*${speedSettings.speed},aresample=44100';
          }
        }

        audioFilter += '[a$i]';
        filterComplex.add(audioFilter);
      }

      for (int i = 0; i < _voiceOverlays.length; i++) {
        final voiceOverlay = _voiceOverlays[i];
        inputs.add('-i "${voiceOverlay.audioPath}"');
      }

      String videoConcat = '';
      String audioConcat = '';
      for (int i = 0; i < _clips.length; i++) {
        videoConcat += '[v$i]';
        audioConcat += '[a$i]';
      }

      filterComplex.add(
        '${videoConcat}concat=n=${_clips.length}:v=1:a=0[outv]',
      );
      filterComplex.add(
        '${audioConcat}concat=n=${_clips.length}:v=0:a=1[outa]',
      );

      if (_voiceOverlays.isNotEmpty) {
        String mixFilter = '[outa]';
        for (int i = 0; i < _voiceOverlays.length; i++) {
          final voiceIndex = _clips.length + i;
          mixFilter += '[$voiceIndex:a]';
        }
        mixFilter +=
            'amix=inputs=${_voiceOverlays.length + 1}:duration=longest[finalaudio]';
        filterComplex.add(mixFilter);
      }

      if (_textOverlays.isNotEmpty) {
        String textFilter = '[outv]';

        for (int i = 0; i < _textOverlays.length; i++) {
          final overlay = _textOverlays[i];

          final escapedText = overlay.text
              .replaceAll("'", "\\'")
              .replaceAll(":", "\\:")
              .replaceAll(",", "\\,");

          final fontSize = overlay.style.fontSize ?? 24;
          final fontColor = _colorToHex(overlay.style.color ?? Colors.white);

          final xPos =
              '${(overlay.position.dx * 100).toStringAsFixed(1)}*w/100';
          final yPos =
              '${(overlay.position.dy * 100).toStringAsFixed(1)}*h/100';

          final drawTextFilter = [
            "text='$escapedText'",
            "fontsize=${fontSize.round()}",
            "fontcolor=$fontColor",
            "x=$xPos",
            "y=$yPos",
            "shadowcolor=0x000000@0.5",
            "shadowx=1",
            "shadowy=1",
            "enable='between(t,${overlay.startTime},${overlay.endTime})'",
          ].join(':');

          if (i == 0) {
            textFilter += 'drawtext=$drawTextFilter';
          } else {
            textFilter += ',drawtext=$drawTextFilter';
          }
        }

        textFilter += '[finalv]';
        filterComplex.add(textFilter);

        final command = [
          inputs.join(' '),
          '-filter_complex "${filterComplex.join(';')}"',
          '-map "[finalv]"',
          '-map "[${_voiceOverlays.isNotEmpty ? 'finalaudio' : 'outa'}]"',
          '-c:v libx264',
          '-preset medium',
          '-crf 23',
          '-c:a aac',
          '-b:a 128k',
          '-y "$outputPath"',
        ].join(' ');

        final session = await FFmpegKit.execute(command);
        final returnCode = await session.getReturnCode();

        Navigator.pop(context);

        if (ReturnCode.isSuccess(returnCode)) {
          _showSaveDialogLocal(outputPath);
          return true;
        } else {
          _showSnackBar('Export failed. Please try again.');
          return false;
        }
      } else {
        final command = [
          inputs.join(' '),
          '-filter_complex "${filterComplex.join(';')}"',
          '-map "[outv]"',
          '-map "[${_voiceOverlays.isNotEmpty ? 'finalaudio' : 'outa'}]"',
          '-c:v libx264',
          '-preset medium',
          '-crf 23',
          '-c:a aac',
          '-b:a 128k',
          '-y "$outputPath"',
        ].join(' ');

        final session = await FFmpegKit.execute(command);
        final returnCode = await session.getReturnCode();

        Navigator.pop(context);

        if (ReturnCode.isSuccess(returnCode)) {
          _showSaveDialogLocal(outputPath);
          return true;
        } else {
          _showSnackBar('Export failed. Please try again.');
          return false;
        }
      }
    } catch (e) {
      Navigator.pop(context);
      _showSnackBar('Export error: ${e.toString()}');
      return false;
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  void _showSaveDialogLocal(String videoPath) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => SaveLocalWidget(
        videoPath: videoPath,
        onVideoSaved: (String savedPath, String name) {
          _showSnackBar('Video saved successfully as $name');
        },
        onCancel: () => Navigator.pop(context),
      ),
    );
  }

  String _colorToHex(Color color) {
    return '0x${color.value.toRadixString(16).substring(2).toUpperCase()}';
  }

  void _showSnackBar(String message) {
    if (mounted && !_isDisposed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.grey[900],
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  double get _totalDuration {
    if (_clips.isEmpty) return 10.0;
    double total = 0.0;
    for (final clip in _clips) {
      total += clip.trimmedDuration.inMilliseconds / 1000.0;
    }
    return total > 0 ? total : 10.0;
  }

  double get _timelineWidth {
    return max(
      MediaQuery.of(context).size.width - 40,
      _totalDuration * _pixelsPerSecond * _timelineScale,
    );
  }

  String _formatDuration(double seconds) {
    final minutes = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Future<void> _initializeClips() async {
    if (widget.files.isEmpty) {
      if (mounted) {
        setState(() => _isInitialized = true);
      }
      return;
    }

    try {
      List<VideoClip> clips = [];
      List<List<Uint8List>> thumbnails = [];
      List<AudioSettings> audioSettings = [];
      List<CropRotateSettings> cropRotateSettings = [];
      List<SpeedSettings> speedSettings = [];
      double position = 0.0;

      for (int i = 0; i < widget.files.length; i++) {
        final file = widget.files[i];
        if (!await file.exists()) continue;

        try {
          VideoPlayerController? tempController = VideoPlayerController.file(
            file,
          );
          await tempController.initialize();
          Duration duration = tempController.value.duration;
          await tempController.dispose();

          final clip = VideoClip(
            id: 'clip_$i',
            file: file,
            startTrim: Duration.zero,
            endTrim: duration,
            originalDuration: duration,
            trackPosition: position,
          );

          clips.add(clip);
          audioSettings.add(AudioSettings());
          cropRotateSettings.add(CropRotateSettings());
          speedSettings.add(SpeedSettings());
          position += duration.inMilliseconds / 1000.0;

          final List<Uint8List> clipThumbs = [];
          final int thumbCount = max(
            5,
            (duration.inSeconds / 2).ceil().clamp(5, 10),
          );

          for (int t = 0; t < thumbCount; t++) {
            try {
              final thumbData = await VideoThumbnail.thumbnailData(
                video: file.path,
                imageFormat: ImageFormat.JPEG,
                maxWidth: 80,
                quality: 70,
                timeMs: (duration.inMilliseconds * t / thumbCount)
                    .round()
                    .clamp(0, duration.inMilliseconds - 1000),
              );
              if (thumbData != null) {
                clipThumbs.add(thumbData);
              }
            } catch (e) {
              print('Thumbnail generation error: $e');
            }
          }
          thumbnails.add(clipThumbs);
        } catch (e) {
          print('Error initializing clip $i: $e');
        }
      }

      if (mounted) {
        setState(() {
          _clips = clips;
          _clipThumbnails = thumbnails;
          _clipAudioSettings = audioSettings;
          _clipCropRotateSettings = cropRotateSettings;
          _clipSpeedSettings = speedSettings;
          _isInitialized = true;
        });

        if (_clips.isNotEmpty) {
          await _loadClipInPlayer(0);
        }
      }
    } catch (e) {
      print('Initialization failed: $e');
      if (mounted) {
        setState(() => _isInitialized = true);
      }
    }
  }

  Widget _buildVideoClip(VideoClip clip, int index) {
    final clipWidth =
        clip.trimmedDuration.inMilliseconds /
        1000.0 *
        _pixelsPerSecond *
        _timelineScale;
    final clipLeft = clip.trackPosition * _pixelsPerSecond * _timelineScale;
    final isSelected = _selectedClipIndex == index;
    final thumbs = index < _clipThumbnails.length
        ? _clipThumbnails[index]
        : <Uint8List>[];

    final audioSettings = index < _clipAudioSettings.length
        ? _clipAudioSettings[index]
        : AudioSettings();
    final cropSettings = index < _clipCropRotateSettings.length
        ? _clipCropRotateSettings[index]
        : CropRotateSettings();
    final speedSettings = index < _clipSpeedSettings.length
        ? _clipSpeedSettings[index]
        : SpeedSettings();

    return Positioned(
      left: clipLeft,
      top: 10,
      child: GestureDetector(
        onTap: () {
          if (mounted) {
            setState(() {
              _selectedClipIndex = index;
              _selectedTextOverlayId = null;
              for (int i = 0; i < _textOverlays.length; i++) {
                _textOverlays[i] = _textOverlays[i].copyWith(isSelected: false);
              }
            });
          }
          _loadClipInPlayer(index);
          final tapPosition = clip.trackPosition;
          _seekToGlobalPosition(tapPosition);
        },
        child: Container(
          width: clipWidth,
          height: _trackHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? Colors.blue : Colors.transparent,
              width: 3,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              if (thumbs.isNotEmpty)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Row(
                      children: thumbs
                          .map(
                            (thumb) => Expanded(
                              child: Image.memory(
                                thumb,
                                fit: BoxFit.cover,
                                height: double.infinity,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),

              Positioned(
                top: 4,
                right: 4,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (audioSettings.isMuted)
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.volume_off,
                          color: Colors.white,
                          size: 12,
                        ),
                      ),
                    if (cropSettings.hasChanges) ...[
                      const SizedBox(width: 2),
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.crop,
                          color: Colors.white,
                          size: 12,
                        ),
                      ),
                    ],
                    if (speedSettings.speed != 1.0) ...[
                      const SizedBox(width: 2),
                      Container(
                        width: 20,
                        height: 16,
                        decoration: BoxDecoration(
                          color: speedSettings.speed > 1.0
                              ? Colors.green
                              : Colors.blue,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            speedSettings.speedLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              if (isSelected) ...[
                _buildTrimHandle(
                  isLeft: true,
                  clipIndex: index,
                  onPan: (delta) {
                    final deltaSeconds =
                        delta / (_pixelsPerSecond * _timelineScale);
                    final newStartMs =
                        clip.startTrim.inMilliseconds +
                        (deltaSeconds * 1000).round();
                    final maxStartMs =
                        clip.endTrim.inMilliseconds -
                        (_minClipDurationSeconds * 1000).round();

                    final clampedStartMs = newStartMs.clamp(0, maxStartMs);
                    final newStart = Duration(milliseconds: clampedStartMs);

                    if (newStart != clip.startTrim) {
                      _trimClip(index, newStart, clip.endTrim);
                    }
                  },
                ),
                _buildTrimHandle(
                  isLeft: false,
                  clipIndex: index,
                  onPan: (delta) {
                    final deltaSeconds =
                        delta / (_pixelsPerSecond * _timelineScale);
                    final newEndMs =
                        clip.endTrim.inMilliseconds +
                        (deltaSeconds * 1000).round();
                    final minEndMs =
                        clip.startTrim.inMilliseconds +
                        (_minClipDurationSeconds * 1000).round();

                    final clampedEndMs = newEndMs.clamp(
                      minEndMs,
                      clip.originalDuration.inMilliseconds,
                    );
                    final newEnd = Duration(milliseconds: clampedEndMs);

                    if (newEnd != clip.endTrim) {
                      _trimClip(index, clip.startTrim, newEnd);
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

  Widget _buildAdditionalStrips() {
    return Container(
      height: 180,
      color: Colors.black,
      child: SingleChildScrollView(
        controller: _timelineScrollController,
        scrollDirection: Axis.horizontal,
        physics: _isTrimming ? const NeverScrollableScrollPhysics() : null,
        child: Container(
          width: _timelineWidth + 40,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Stack(
            children: [
              Positioned(
                top: 20,
                child: Container(
                  width: _timelineWidth,
                  height: 50,
                  child: TextTimelineStrip(
                    overlays: _textOverlays,
                    totalDuration: _totalDuration,
                    currentTime: _currentGlobalPosition,
                    timelineWidth: _timelineWidth,
                    pixelsPerSecond: _pixelsPerSecond * _timelineScale,
                    onOverlayTimeChanged: _updateTextOverlayTime,
                    onOverlaySelected: (id) {
                      _selectTextOverlay(id);
                      final overlay = _textOverlays.firstWhere(
                        (o) => o.id == id,
                      );
                      _seekToGlobalPosition(overlay.startTime);
                    },
                    onAddOverlay: _addTextOverlay,
                    onOverlayDeleted: _deleteTextOverlay,
                  ),
                ),
              ),

              Positioned(
                top: 80,
                child: Container(
                  width: _timelineWidth,
                  height: 50,
                  child: VoiceTimelineStrip(
                    voiceOverlays: _voiceOverlays,
                    totalDuration: _totalDuration,
                    currentTime: _currentGlobalPosition,
                    timelineWidth: _timelineWidth,
                    pixelsPerSecond: _pixelsPerSecond * _timelineScale,
                    onOverlayTimeChanged: _updateVoiceOverlayTime,
                    onOverlaySelected: _selectVoiceOverlay,
                    onOverlayDeleted: _deleteVoiceOverlay,
                    onVolumeChanged: _updateVoiceOverlayVolume,
                  ),
                ),
              ),

              Positioned(
                top: 140,
                child: Container(
                  width: _timelineWidth,
                  height: 25,
                  decoration: BoxDecoration(
                    color: _globalAudioSettings.isMuted
                        ? Colors.red[600]
                        : Colors.orange[600],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _globalAudioSettings.isMuted
                              ? Icons.volume_off
                              : Icons.volume_up,
                          color: Colors.white,
                          size: 12,
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'Audio',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              Positioned(
                left:
                    _currentGlobalPosition * _pixelsPerSecond * _timelineScale -
                    1,
                top: 0,
                child: Container(width: 2, height: 180, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomToolbar() {
    final List<Map<String, dynamic>> toolbarItems = [
      {'icon': Icons.add, 'label': 'Add', 'onTap': null, 'isActive': false},
      {
        'icon': Icons.volume_up,
        'label': 'Sound',
        'onTap': _showSoundControl,
        'isActive':
            _globalAudioSettings.isMuted ||
            (_selectedClipIndex != null &&
                _selectedClipIndex! < _clipAudioSettings.length &&
                _clipAudioSettings[_selectedClipIndex!].isMuted),
      },
      {
        'icon': Icons.mic,
        'label': 'Voice',
        'onTap': _addVoiceOverlay,
        'isActive': _voiceOverlays.isNotEmpty,
      },
      {
        'icon': Icons.text_fields,
        'label': 'Text',
        'onTap': _addTextOverlay,
        'isActive': _selectedTextOverlayId != null,
      },
      {
        'icon': Icons.content_cut,
        'label': 'Split',
        'onTap': _splitClip,
        'isActive': _selectedClipIndex != null,
      },
      {
        'icon': Icons.crop_rotate,
        'label': 'Crop',
        'onTap': _showCropRotate,
        'isActive':
            _selectedClipIndex != null &&
            _selectedClipIndex! < _clipCropRotateSettings.length &&
            _clipCropRotateSettings[_selectedClipIndex!].hasChanges,
      },
      {
        'icon': Icons.speed,
        'label': 'Speed',
        'onTap': _showSpeedControl,
        'isActive':
            _selectedClipIndex != null &&
            _selectedClipIndex! < _clipSpeedSettings.length &&
            _clipSpeedSettings[_selectedClipIndex!].speed != 1.0,
      },
      {
        'icon': Icons.save,
        'label': 'Save',
        'onTap': _showSaveDialog,
        'isActive': false,
      },
    ];

    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border(top: BorderSide(color: Colors.grey[800]!, width: 1)),
      ),
      child: SingleChildScrollView(
        controller: _bottomToolbarScrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: toolbarItems.map((item) {
            final icon = item['icon'] as IconData;
            final label = item['label'] as String;
            final onTap = item['onTap'] as VoidCallback?;
            final isActive = item['isActive'] as bool;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: onTap,
                child: Container(
                  width: 64,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: onTap != null
                              ? (isActive ? Colors.blue : Colors.grey[800])
                              : Colors.grey[700],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          icon,
                          color: onTap != null
                              ? (isActive ? Colors.white : Colors.grey[300])
                              : Colors.grey[500],
                          size: 20,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: TextStyle(
                          color: onTap != null
                              ? (isActive ? Colors.blue : Colors.grey[300])
                              : Colors.grey[500],
                          fontSize: 10,
                          fontWeight: isActive
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTrimHandle({
    required bool isLeft,
    required int clipIndex,
    required Function(double) onPan,
  }) {
    final isActive =
        _isTrimming &&
        _activeTrimHandle == (isLeft ? clipIndex * 2 : clipIndex * 2 + 1);

    return Positioned(
      left: isLeft ? -_handleTouchArea / 2 : null,
      right: isLeft ? null : -_handleTouchArea / 2,
      top: -10,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) {
          HapticFeedback.lightImpact();
          if (mounted) {
            setState(() {
              _isTrimming = true;
              _activeTrimHandle = isLeft ? clipIndex * 2 : clipIndex * 2 + 1;
            });
          }
          if (_isPlaying) {
            _playerController?.pause();
            if (mounted) {
              setState(() {
                _shouldPlayNextClip = false;
              });
            }
          }
        },
        onPanUpdate: (details) {
          onPan(details.delta.dx);
        },
        onPanEnd: (details) {
          HapticFeedback.mediumImpact();
          if (mounted) {
            setState(() {
              _isTrimming = false;
              _activeTrimHandle = null;
            });
          }
        },
        child: Container(
          width: _handleTouchArea,
          height: _trackHeight + 20,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: _handleWidth,
              height: _trackHeight + 16,
              decoration: BoxDecoration(
                color: isActive
                    ? Colors.yellow
                    : (isLeft ? Colors.green : Colors.red),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.9),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Icon(
                    isLeft ? Icons.arrow_back_ios : Icons.arrow_forward_ios,
                    color: Colors.white,
                    size: 16,
                  ),
                  ...List.generate(
                    4,
                    (index) => Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  Icon(
                    isLeft ? Icons.arrow_back_ios : Icons.arrow_forward_ios,
                    color: Colors.white,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ),
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
            onPressed: () {
              _playerController?.pause();
              _playerController?.removeListener(_videoListener);
              Navigator.of(context).pop();
            },
          ),
          const Spacer(),
          const Text(
            'Edit',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (_isExporting)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.check, color: Colors.white, size: 24),
              onPressed: _clips.isNotEmpty ? () => _exportVideo() : null,
            ),
        ],
      ),
    );
  }

  Widget _buildVideoPreviewWithPlayButton() {
    if (!_isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_clips.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.video_library, color: Colors.white, size: 64),
            const SizedBox(height: 16),
            const Text(
              'No video files loaded',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
      );
    }

    if (_playerController == null || !_playerController!.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    Widget videoWidget = VideoPlayer(_playerController!);

    if (_selectedClipIndex != null &&
        _selectedClipIndex! < _clipCropRotateSettings.length) {
      final settings = _clipCropRotateSettings[_selectedClipIndex!];
      if (settings.hasChanges) {
        videoWidget = Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..rotateZ(settings.rotation * 3.14159 / 180)
            ..scale(
              settings.scaleX * (settings.flipHorizontal ? -1 : 1),
              settings.scaleY * (settings.flipVertical ? -1 : 1),
            ),
          child: ClipRect(
            child: Align(
              alignment: Alignment(
                -1 + 2 * (settings.cropX + settings.cropWidth / 2),
                -1 + 2 * (settings.cropY + settings.cropHeight / 2),
              ),
              widthFactor: settings.cropWidth,
              heightFactor: settings.cropHeight,
              child: videoWidget,
            ),
          ),
        );
      }
    }

    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: _playerController!.value.aspectRatio,
              child: videoWidget,
            ),
          ),

          if (_activeTextOverlays.isNotEmpty)
            Positioned.fill(
              child: Center(
                child: AspectRatio(
                  aspectRatio: _playerController!.value.aspectRatio,
                  child: Stack(
                    children: _activeTextOverlays.map((overlay) {
                      return TextOverlayWidget(
                        key: ValueKey(overlay.id),
                        overlay: overlay,
                        videoSize: Size(
                          MediaQuery.of(context).size.width,
                          MediaQuery.of(context).size.width /
                              _playerController!.value.aspectRatio,
                        ),
                        onPositionChanged: _updateTextOverlayPosition,
                        onTap: _selectTextOverlay,
                        onEditText: _editTextOverlay,
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),

          Positioned(
            left: 20,
            bottom: 20,
            child: GestureDetector(
              onTap: _playPause,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.black,
                  size: 32,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeDisplaySection() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.undo, color: Colors.grey, size: 20),
            onPressed: null,
          ),
          const SizedBox(width: 20),
          Text(
            '${_formatDuration(_currentGlobalPosition)}/${_formatDuration(_totalDuration)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 20),
          IconButton(
            icon: const Icon(Icons.redo, color: Colors.grey, size: 20),
            onPressed: null,
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineScrubber() {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 4,
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(2),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: _totalDuration > 0
                    ? _currentGlobalPosition / _totalDuration
                    : 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            Positioned(
              left: _totalDuration > 0
                  ? (MediaQuery.of(context).size.width - 40) *
                            (_currentGlobalPosition / _totalDuration) -
                        6
                  : 0,
              top: -4,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey[600]!, width: 1),
                ),
              ),
            ),
            Positioned.fill(
              child: GestureDetector(
                onTapDown: (details) {
                  if (!_isTrimming) {
                    final progress =
                        details.localPosition.dx /
                        (MediaQuery.of(context).size.width - 40);
                    final seconds = progress * _totalDuration;
                    _seekToGlobalPosition(seconds);
                  }
                },
                child: Container(color: Colors.transparent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoStrips() {
    return Container(
      height: 80,
      color: Colors.black,
      child: SingleChildScrollView(
        controller: _timelineScrollController,
        scrollDirection: Axis.horizontal,
        physics: _isTrimming ? const NeverScrollableScrollPhysics() : null,
        child: Container(
          width: _timelineWidth + 40,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Stack(
            children: [
              Positioned(
                top: 10,
                child: Container(
                  width: _timelineWidth,
                  height: _trackHeight,
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              ..._clips.asMap().entries.map((entry) {
                return _buildVideoClip(entry.value, entry.key);
              }).toList(),
              Positioned(
                left:
                    _currentGlobalPosition * _pixelsPerSecond * _timelineScale -
                    1,
                top: 5,
                child: Container(width: 2, height: 70, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _playerController?.pause();
        _playerController?.removeListener(_videoListener);
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(child: _buildVideoPreviewWithPlayButton()),
              _buildTimeDisplaySection(),
              _buildTimelineScrubber(),
              _buildVideoStrips(),
              _buildAdditionalStrips(),
              _buildBottomToolbar(),
            ],
          ),
        ),
      ),
    );
  }
}

class RecordingWaveformPainter extends CustomPainter {
  final bool isRecording;
  final Duration duration;

  RecordingWaveformPainter({required this.isRecording, required this.duration});

  @override
  void paint(Canvas canvas, Size size) {
    if (!isRecording) return;

    final paint = Paint()
      ..color = Colors.red.withOpacity(0.8)
      ..strokeWidth = 2;

    final time = duration.inMilliseconds / 100;

    for (int i = 0; i < size.width; i += 3) {
      final height =
          sin((i + time) * 0.02) *
              sin((i + time) * 0.01) *
              (size.height * 0.4) +
          (size.height * 0.5);

      canvas.drawLine(
        Offset(i.toDouble(), size.height * 0.5),
        Offset(i.toDouble(), height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class TextTimelineStrip extends StatelessWidget {
  final List<TextOverlay> overlays;
  final double totalDuration;
  final double currentTime;
  final double timelineWidth;
  final double pixelsPerSecond;
  final Function(String, double, double) onOverlayTimeChanged;
  final Function(String) onOverlaySelected;
  final VoidCallback onAddOverlay;
  final Function(String) onOverlayDeleted;

  const TextTimelineStrip({
    Key? key,
    required this.overlays,
    required this.totalDuration,
    required this.currentTime,
    required this.timelineWidth,
    required this.pixelsPerSecond,
    required this.onOverlayTimeChanged,
    required this.onOverlaySelected,
    required this.onAddOverlay,
    required this.onOverlayDeleted,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: timelineWidth,
      height: 50,
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        children: [
          if (overlays.isEmpty)
            Positioned(
              left: 8,
              top: 8,
              child: GestureDetector(
                onTap: onAddOverlay,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.blue, width: 1),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, color: Colors.blue, size: 16),
                      SizedBox(width: 4),
                      Text(
                        'Add Text',
                        style: TextStyle(color: Colors.blue, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ...overlays.map((overlay) => _buildTextOverlayStrip(overlay)),
        ],
      ),
    );
  }

  Widget _buildTextOverlayStrip(TextOverlay overlay) {
    final startX = (overlay.startTime / totalDuration) * timelineWidth;
    final width =
        ((overlay.endTime - overlay.startTime) / totalDuration) * timelineWidth;

    return Positioned(
      left: startX,
      top: 8,
      child: Container(
        width: max(width, 40),
        height: 34,
        decoration: BoxDecoration(
          color: overlay.isSelected ? Colors.blue : Colors.purple[600],
          borderRadius: BorderRadius.circular(4),
          border: overlay.isSelected
              ? Border.all(color: Colors.blue[300]!, width: 2)
              : null,
        ),
        child: Center(
          child: Text(
            overlay.text.length > 10
                ? '${overlay.text.substring(0, 10)}...'
                : overlay.text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

class VoiceTimelineStrip extends StatelessWidget {
  final List<VoiceOverlay> voiceOverlays;
  final double totalDuration;
  final double currentTime;
  final double timelineWidth;
  final double pixelsPerSecond;
  final Function(String, double, double) onOverlayTimeChanged;
  final Function(String) onOverlaySelected;
  final Function(String) onOverlayDeleted;
  final Function(String, double) onVolumeChanged;

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
  Widget build(BuildContext context) {
    return Container(
      width: timelineWidth,
      height: 50,
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        children: voiceOverlays
            .map((overlay) => _buildVoiceOverlayStrip(overlay))
            .toList(),
      ),
    );
  }

  Widget _buildVoiceOverlayStrip(VoiceOverlay overlay) {
    final startX = (overlay.startTime / totalDuration) * timelineWidth;
    final width =
        ((overlay.endTime - overlay.startTime) / totalDuration) * timelineWidth;

    return Positioned(
      left: startX,
      top: 8,
      child: Container(
        width: max(width, 40),
        height: 34,
        decoration: BoxDecoration(
          color: Colors.green[600],
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            overlay.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
