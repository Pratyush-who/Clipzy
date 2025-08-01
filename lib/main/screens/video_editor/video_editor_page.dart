import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

// Data Models
class VideoClip {
  String id;
  File file;
  Duration startTrim;
  Duration endTrim;
  Duration originalDuration;
  double trackPosition;

  VideoClip({
    required this.id,
    required this.file,
    required this.startTrim,
    required this.endTrim,
    required this.originalDuration,
    this.trackPosition = 0.0,
  });

  Duration get trimmedDuration => endTrim - startTrim;

  VideoClip copyWith({
    String? id,
    File? file,
    Duration? startTrim,
    Duration? endTrim,
    Duration? originalDuration,
    double? trackPosition,
  }) {
    return VideoClip(
      id: id ?? this.id,
      file: file ?? this.file,
      startTrim: startTrim ?? this.startTrim,
      endTrim: endTrim ?? this.endTrim,
      originalDuration: originalDuration ?? this.originalDuration,
      trackPosition: trackPosition ?? this.trackPosition,
    );
  }
}

class VideoEditorPage extends StatefulWidget {
  final List<File> files;

  const VideoEditorPage({Key? key, required this.files}) : super(key: key);

  @override
  State<VideoEditorPage> createState() => _VideoEditorPageState();
}

class _VideoEditorPageState extends State<VideoEditorPage> {
  VideoPlayerController? _playerController;
  List<VideoClip> _clips = [];
  int? _selectedClipIndex;
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

  // Timeline constants - Increased handle width for better touch targets
  static const double _trackHeight = 60.0;
  static const double _pixelsPerSecond = 30.0;
  static const double _minClipDurationSeconds = 0.5;
  static const double _handleWidth = 50.0; // Increased for better visibility
  static const double _handleTouchArea =
      80.0; // Larger touch area for easier dragging
  List<List<Uint8List>> _clipThumbnails = [];

  @override
  void initState() {
    super.initState();
    print('=== VideoEditorPage initState ===');
    print('Files passed to editor: ${widget.files.length}');
    _initializeClips();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _playerController?.removeListener(_videoListener);
    _playerController?.dispose();
    _timelineScrollController.dispose();
    _bottomToolbarScrollController.dispose();
    _playbackTimer?.cancel();
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

        // Auto-scroll timeline to keep playhead visible for large clips
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

    // Check if playhead is outside visible area
    if (playheadPosition < currentScrollOffset ||
        playheadPosition > currentScrollOffset + screenWidth) {
      // Calculate target scroll position to center playhead
      final targetScrollOffset = playheadPosition - (screenWidth / 2);
      final maxScrollOffset =
          _timelineScrollController.position.maxScrollExtent;

      _timelineScrollController.animateTo(
        targetScrollOffset.clamp(0.0, maxScrollOffset),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
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
      // Ensure only one player is active at a time
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

    // Generate thumbnails for the new clips
    List<Uint8List> firstThumbs = [];
    List<Uint8List> secondThumbs = [];

    try {
      // Generate thumbnails for first part
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

      // Generate thumbnails for second part
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

  void _exportVideo() async {
    if (_clips.isEmpty || _isExporting) return;

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
        inputs.add('-i "${clip.file.path}"');

        final startSeconds = clip.startTrim.inMilliseconds / 1000.0;
        final durationSeconds = clip.trimmedDuration.inMilliseconds / 1000.0;

        filterComplex.add(
          '[$i:v]trim=start=$startSeconds:duration=$durationSeconds,setpts=PTS-STARTPTS[v$i]',
        );
        filterComplex.add(
          '[$i:a]atrim=start=$startSeconds:duration=$durationSeconds,asetpts=PTS-STARTPTS[a$i]',
        );
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

      final command =
          '${inputs.join(' ')} -filter_complex "${filterComplex.join(';')}" -map "[outv]" -map "[outa]" -c:v libx264 -c:a aac -y "$outputPath"';

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        _showSnackBar('Video exported successfully!');
      } else {
        _showSnackBar('Export failed. Check logs for details.');
      }
    } catch (e) {
      _showSnackBar('Export error: $e');
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  void _showSnackBar(String message) {
    if (mounted && !_isDisposed) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
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
          position += duration.inMilliseconds / 1000.0;

          // Generate thumbnails
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

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Clean up resources before popping
        _playerController?.pause();
        _playerController?.removeListener(_videoListener);
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              // Header
              _buildHeader(),

              // Video Preview with Play Button
              Expanded(child: _buildVideoPreviewWithPlayButton()),

              // Time Display and Controls
              _buildTimeDisplaySection(),

              // Timeline Scrubber
              _buildTimelineScrubber(),

              // Video Strips
              _buildVideoStrips(),

              // Additional Strips
              _buildAdditionalStrips(),

              // Bottom Toolbar
              _buildBottomToolbar(),
            ],
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
              onPressed: _clips.isNotEmpty ? _exportVideo : null,
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

    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: _playerController!.value.aspectRatio,
              child: VideoPlayer(_playerController!),
            ),
          ),

          // Play button on the left side
          Positioned(
            left: 20,
            bottom: 20,
            child: GestureDetector(
              onTap: _playPause,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.black,
                  size: 28,
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
          // Undo button
          IconButton(
            icon: const Icon(Icons.undo, color: Colors.grey, size: 20),
            onPressed: null, // TODO: Implement undo
          ),

          const SizedBox(width: 20),

          // Time display
          Text(
            '${_formatDuration(_currentGlobalPosition)}/${_formatDuration(_totalDuration)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(width: 20),

          // Redo button
          IconButton(
            icon: const Icon(Icons.redo, color: Colors.grey, size: 20),
            onPressed: null, // TODO: Implement redo
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
            // Progress bar
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

            // Scrubber handle
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

            // Tap area
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
              // Video track background
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

              // Video clips
              ..._clips.asMap().entries.map((entry) {
                return _buildVideoClip(entry.value, entry.key);
              }).toList(),

              // Playhead for strips
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

    return Positioned(
      left: clipLeft,
      top: 10,
      child: GestureDetector(
        onTap: () {
          if (mounted) {
            setState(() {
              _selectedClipIndex = index;
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
              // Thumbnails
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

              // Trim handles (only show when selected)
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
              // Purple strip
              Positioned(
                top: 10,
                child: Container(
                  width: _timelineWidth,
                  height: 25,
                  decoration: BoxDecoration(
                    color: Colors.purple,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Center(
                    child: Text(
                      'Color overlay',
                      style: TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),
              ),

              // Orange audio strip
              Positioned(
                top: 45,
                child: Container(
                  width: _timelineWidth,
                  height: 25,
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(painter: AudioWaveformPainter()),
                      ),
                      const Center(
                        child: Text(
                          'Linear',
                          style: TextStyle(color: Colors.white, fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomToolbar() {
    final toolbarItems = [
      Icons.add,
      Icons.music_note,
      Icons.mic,
      Icons.text_fields,
      Icons.tune,
      Icons.visibility,
      Icons.save_alt,
      Icons.layers,
      Icons.speed,
      Icons.content_cut,
      Icons.close,
    ];

    return Container(
      height: 60,
      color: Colors.black,
      child: SingleChildScrollView(
        controller: _bottomToolbarScrollController,
        scrollDirection: Axis.horizontal,
        child: Row(
          children: toolbarItems.asMap().entries.map((entry) {
            final index = entry.key;
            final icon = entry.value;

            return Container(
              width: 60,
              height: 60,
              child: IconButton(
                icon: Icon(icon, color: Colors.white, size: 24),
                onPressed: () {
                  if (icon == Icons.content_cut) {
                    _splitClip();
                  }
                  // Add other button functionalities here
                },
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
          if (mounted) {
            setState(() {
              _isTrimming = true;
              _activeTrimHandle = isLeft ? clipIndex * 2 : clipIndex * 2 + 1;
            });
          }
          HapticFeedback.lightImpact();
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
          if (mounted) {
            setState(() {
              _isTrimming = false;
              _activeTrimHandle = null;
            });
          }
          HapticFeedback.mediumImpact();
        },
        onTapDown: (details) {
          // Provide immediate feedback when touching the handle
          HapticFeedback.selectionClick();
        },
        child: Container(
          width: _handleTouchArea,
          height: _trackHeight + 20,
          child: Center(
            child: Container(
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
                  // Top arrow indicator
                  Icon(
                    isLeft ? Icons.arrow_back_ios : Icons.arrow_forward_ios,
                    color: Colors.white,
                    size: 16,
                  ),
                  // Dots
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
                  // Bottom arrow indicator
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
}

// Custom Painters
class AudioWaveformPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..strokeWidth = 1;

    final random = Random(42); // Fixed seed for consistent waveform
    final spacing = 2.0;
    final numBars = (size.width / spacing).floor();

    for (int i = 0; i < numBars; i++) {
      final x = i * spacing;
      final height = random.nextDouble() * size.height * 0.8;
      final y = (size.height - height) / 2;

      canvas.drawLine(Offset(x, y), Offset(x, y + height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
