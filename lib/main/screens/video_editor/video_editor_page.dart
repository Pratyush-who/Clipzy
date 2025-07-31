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
  double _currentPosition = 0.0;
  double _timelineScale = 1.0;
  bool _isPlaying = false;
  bool _isInitialized = false;
  bool _isExporting = false;
  bool _isTrimming = false;
  int? _activeTrimHandle;
  ScrollController _timelineScrollController = ScrollController();

  // Timeline constants
  static const double _trackHeight = 60.0;
  static const double _pixelsPerSecond = 30.0;
  static const double _minClipDurationSeconds = 0.5;
  static const double _handleWidth = 12.0;
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
    _playerController?.removeListener(_videoListener);
    _playerController?.dispose();
    _timelineScrollController.dispose();
    super.dispose();
  }

  void _videoListener() {
    if (!mounted ||
        _playerController == null ||
        !_playerController!.value.isInitialized) return;

    final controller = _playerController!;
    final position = controller.value.position;

    if (_selectedClipIndex != null && _selectedClipIndex! < _clips.length) {
      final selectedClip = _clips[_selectedClipIndex!];

      // Check if we've reached the end of the current clip's trim
      if (position >= selectedClip.endTrim) {
        _playNextClip();
        return;
      }

      // Update global position
      double globalPosition = selectedClip.trackPosition +
          (position - selectedClip.startTrim).inMilliseconds / 1000.0;

      if (mounted) {
        setState(() {
          _currentPosition = globalPosition.clamp(0.0, _totalDuration);
          _isPlaying = controller.value.isPlaying;
        });
      }
    }
  }

  void _playNextClip() async {
    if (_selectedClipIndex == null || _selectedClipIndex! >= _clips.length - 1) {
      setState(() => _isPlaying = false);
      return;
    }

    await _loadClipInPlayer(_selectedClipIndex! + 1, autoPlay: true);
  }

  Future<void> _loadClipInPlayer(int clipIndex, {bool autoPlay = false, Duration? seekTo}) async {
    if (clipIndex >= _clips.length || clipIndex < 0) return;

    try {
      _playerController?.removeListener(_videoListener);
      await _playerController?.dispose();

      final clip = _clips[clipIndex];
      if (!await clip.file.exists()) {
        setState(() => _selectedClipIndex = clipIndex);
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
    } else {
      _playerController!.play();
    }
  }

  void _splitClip() {
    if (_selectedClipIndex == null ||
        _playerController == null ||
        _selectedClipIndex! >= _clips.length) return;

    final currentClip = _clips[_selectedClipIndex!];
    final currentPosition = _playerController!.value.position;

    if (currentPosition <= currentClip.startTrim ||
        currentPosition >= currentClip.endTrim) return;

    final firstPartDuration = currentPosition - currentClip.startTrim;
    final secondPartDuration = currentClip.endTrim - currentPosition;

    if (firstPartDuration.inMilliseconds < _minClipDurationSeconds * 1000 ||
        secondPartDuration.inMilliseconds < _minClipDurationSeconds * 1000) {
      _showSnackBar('Cannot split: resulting clips would be too short');
      return;
    }

    final firstClip = currentClip.copyWith(
      id: '${currentClip.id}_part1',
      endTrim: currentPosition,
    );

    final secondClip = currentClip.copyWith(
      id: '${currentClip.id}_part2',
      startTrim: currentPosition,
    );

    setState(() {
      _clips.removeAt(_selectedClipIndex!);
      _clips.insertAll(_selectedClipIndex!, [firstClip, secondClip]);
      _recalculateClipPositions();
    });

    _loadClipInPlayer(_selectedClipIndex!);
  }

  void _trimClip(int clipIndex, Duration newStart, Duration newEnd) {
    if (clipIndex >= _clips.length || clipIndex < 0) return;

    final clip = _clips[clipIndex];

    newStart = Duration(
      milliseconds: newStart.inMilliseconds.clamp(0, clip.originalDuration.inMilliseconds),
    );
    newEnd = Duration(
      milliseconds: newEnd.inMilliseconds.clamp(0, clip.originalDuration.inMilliseconds),
    );

    if (newStart >= newEnd) return;
    if ((newEnd - newStart).inMilliseconds < _minClipDurationSeconds * 1000) return;

    setState(() {
      _clips[clipIndex] = clip.copyWith(startTrim: newStart, endTrim: newEnd);
      _recalculateClipPositions();
    });

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

  void _seekToPosition(double seconds) async {
    if (_clips.isEmpty) return;

    seconds = seconds.clamp(0.0, _totalDuration);
    double cumulativeTime = 0.0;

    for (int i = 0; i < _clips.length; i++) {
      final clip = _clips[i];
      final clipDuration = clip.trimmedDuration.inMilliseconds / 1000.0;

      if (seconds >= cumulativeTime && seconds < cumulativeTime + clipDuration) {
        final offsetInClip = seconds - cumulativeTime;
        final seekPosition = clip.startTrim + Duration(milliseconds: (offsetInClip * 1000).round());

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

        setState(() => _currentPosition = seconds);
        return;
      }
      cumulativeTime += clipDuration;
    }
  }

  void _exportVideo() async {
    if (_clips.isEmpty || _isExporting) return;

    setState(() => _isExporting = true);

    try {
      final directory = await getApplicationDocumentsDirectory();
      final outputPath = '${directory.path}/edited_video_${DateTime.now().millisecondsSinceEpoch}.mp4';

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

      filterComplex.add('${videoConcat}concat=n=${_clips.length}:v=1:a=0[outv]');
      filterComplex.add('${audioConcat}concat=n=${_clips.length}:v=0:a=1[outa]');

      final command = '${inputs.join(' ')} -filter_complex "${filterComplex.join(';')}" -map "[outv]" -map "[outa]" -c:v libx264 -c:a aac -y "$outputPath"';

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
      setState(() => _isExporting = false);
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
    return max(MediaQuery.of(context).size.width, _totalDuration * _pixelsPerSecond * _timelineScale);
  }

  Future<void> _initializeClips() async {
    if (widget.files.isEmpty) {
      setState(() => _isInitialized = true);
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
          VideoPlayerController? tempController = VideoPlayerController.file(file);
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
          final int thumbCount = max(3, (duration.inSeconds / 3).ceil().clamp(3, 8));

          for (int t = 0; t < thumbCount; t++) {
            try {
              final thumbData = await VideoThumbnail.thumbnailData(
                video: file.path,
                imageFormat: ImageFormat.JPEG,
                maxWidth: 80,
                quality: 70,
                timeMs: (duration.inMilliseconds * t / thumbCount).round().clamp(0, duration.inMilliseconds - 1000),
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(),
            
            // Video Preview
            Expanded(
              flex: 3,
              child: _buildVideoPreview(),
            ),
            
            // Controls
            _buildControls(),
            
            // Timeline
            Container(
              height: 200,
              child: _buildTimeline(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        border: Border(bottom: BorderSide(color: Colors.grey[700]!)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Spacer(),
          const Text(
            'Edit',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          if (_isExporting)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          else
            IconButton(
              icon: const Icon(Icons.check, color: Colors.white),
              onPressed: _clips.isNotEmpty ? _exportVideo : null,
            ),
        ],
      ),
    );
  }

  Widget _buildVideoPreview() {
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
            const Text('No video files loaded', style: TextStyle(color: Colors.white, fontSize: 18)),
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
      child: Center(
        child: AspectRatio(
          aspectRatio: _playerController!.value.aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(_playerController!),
              
              Positioned.fill(
                child: GestureDetector(
                  onTapDown: (details) {
                    if (_selectedClipIndex != null) {
                      final clip = _clips[_selectedClipIndex!];
                      final renderBox = context.findRenderObject() as RenderBox;
                      final localPosition = renderBox.globalToLocal(details.globalPosition);
                      final progress = localPosition.dx / renderBox.size.width;
                      final seekPosition = clip.startTrim + Duration(
                        milliseconds: (progress * clip.trimmedDuration.inMilliseconds).round(),
                      );
                      final clampedSeekPosition = Duration(
  milliseconds: seekPosition.inMilliseconds.clamp(
    clip.startTrim.inMilliseconds,
    clip.endTrim.inMilliseconds,
  ),
);
_playerController?.seekTo(clampedSeekPosition);
                    }
                  },
                ),
              ),
              
              // Clip indicator
              if (_selectedClipIndex != null)
                Positioned(
                  top: 16,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Clip ${_selectedClipIndex! + 1}/${_clips.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildControlButton(Icons.cut, _selectedClipIndex != null ? _splitClip : null),
          _buildControlButton(_isPlaying ? Icons.pause : Icons.play_arrow, _playPause, size: 50),
          _buildControlButton(Icons.zoom_in, () {
            setState(() => _timelineScale = min(_timelineScale * 1.2, 3.0));
          }),
          _buildControlButton(Icons.zoom_out, () {
            setState(() => _timelineScale = max(_timelineScale / 1.2, 0.5));
          }),
        ],
      ),
    );
  }

  Widget _buildControlButton(IconData icon, VoidCallback? onPressed, {double size = 40}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(size / 2),
        onTap: onPressed,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: onPressed != null ? Colors.white.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(
              color: onPressed != null ? Colors.white.withOpacity(0.3) : Colors.grey.withOpacity(0.3),
            ),
          ),
          child: Icon(
            icon,
            color: onPressed != null ? Colors.white : Colors.grey,
            size: size * 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildTimeline() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        border: Border(top: BorderSide(color: Colors.grey[700]!)),
      ),
      child: Column(
        children: [
          // Timeline header
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  '${_currentPosition.toStringAsFixed(1)}s / ${_totalDuration.toStringAsFixed(1)}s',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                const Spacer(),
                Text(
                  'Scale: ${_timelineScale.toStringAsFixed(1)}x',
                  style: const TextStyle(color: Colors.grey, fontSize: 10),
                ),
              ],
            ),
          ),
          
          // Timeline tracks
          Expanded(
            child: SingleChildScrollView(
              controller: _timelineScrollController,
              scrollDirection: Axis.horizontal,
              child: Container(
                width: _timelineWidth,
                child: Stack(
                  children: [
                    // Background grid
                    CustomPaint(
                      size: Size(_timelineWidth, 160),
                      painter: TimelineGridPainter(_timelineScale, _totalDuration),
                    ),
                    
                    // Video track
                    Positioned(
                      top: 40,
                      child: Container(
                        width: _timelineWidth,
                        height: _trackHeight,
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          border: Border.all(color: Colors.grey[600]!),
                        ),
                        child: Stack(
                          children: [
                            // Clips
                            ..._clips.asMap().entries.map((entry) {
                              return _buildTimelineClip(entry.value, entry.key);
                            }).toList(),
                          ],
                        ),
                      ),
                    ),
                    
                    // Playhead
                    Positioned(
                      left: _currentPosition * _pixelsPerSecond * _timelineScale - 1,
                      top: 20,
                      child: Container(
                        width: 2,
                        height: 120,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withOpacity(0.5),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    // Scrubber area
                    Positioned(
                      top: 0,
                      child: GestureDetector(
                        onTapDown: (details) {
                          final seconds = details.localPosition.dx / (_pixelsPerSecond * _timelineScale);
                          _seekToPosition(seconds);
                        },
                        onPanUpdate: (details) {
                          final seconds = details.localPosition.dx / (_pixelsPerSecond * _timelineScale);
                          _seekToPosition(seconds);
                        },
                        child: Container(
                          width: _timelineWidth,
                          height: 40,
                          color: Colors.transparent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineClip(VideoClip clip, int index) {
    final clipWidth = clip.trimmedDuration.inMilliseconds / 1000.0 * _pixelsPerSecond * _timelineScale;
    final clipLeft = clip.trackPosition * _pixelsPerSecond * _timelineScale;
    final isSelected = _selectedClipIndex == index;
    final thumbs = index < _clipThumbnails.length ? _clipThumbnails[index] : <Uint8List>[];

    return Positioned(
      left: clipLeft,
      child: GestureDetector(
        onTap: () => _loadClipInPlayer(index),
        child: Container(
          width: clipWidth,
          height: _trackHeight,
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue[600] : Colors.purple[600],
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? Colors.blue[300]! : Colors.transparent,
              width: 2,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // Thumbnails
              if (thumbs.isNotEmpty)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: Row(
                      children: thumbs.map((thumb) => Expanded(
                        child: Image.memory(
                          thumb,
                          fit: BoxFit.cover,
                          height: double.infinity,
                        ),
                      )).toList(),
                    ),
                  ),
                ),
              
              // Clip label
              Positioned(
                top: 4,
                left: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              
              // Left trim handle
              _buildTrimHandle(
                isLeft: true,
                clipIndex: index,
                onPan: (delta) {
                  final deltaSeconds = delta / (_pixelsPerSecond * _timelineScale);
                  final newStart = clip.startTrim + Duration(milliseconds: (deltaSeconds * 1000).round());
                  final maxStart = clip.endTrim - Duration(milliseconds: (_minClipDurationSeconds * 1000).round());
                  final clampedStart = Duration(
                    milliseconds: newStart.inMilliseconds.clamp(0, maxStart.inMilliseconds),
                  );
                  if (clampedStart != clip.startTrim) {
                    _trimClip(index, clampedStart, clip.endTrim);
                  }
                },
              ),
              
              // Right trim handle
              _buildTrimHandle(
                isLeft: false,
                clipIndex: index,
                onPan: (delta) {
                  final deltaSeconds = delta / (_pixelsPerSecond * _timelineScale);
                  final newEnd = clip.endTrim + Duration(milliseconds: (deltaSeconds * 1000).round());
                  final minEnd = clip.startTrim + Duration(milliseconds: (_minClipDurationSeconds * 1000).round());
                  final clampedEnd = Duration(
                    milliseconds: newEnd.inMilliseconds.clamp(
                      minEnd.inMilliseconds,
                      clip.originalDuration.inMilliseconds,
                    ),
                  );
                  if (clampedEnd != clip.endTrim) {
                    _trimClip(index, clip.startTrim, clampedEnd);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrimHandle({
    required bool isLeft,
    required int clipIndex,
    required Function(double) onPan,
  }) {
    return Positioned(
      left: isLeft ? -_handleWidth / 2 : null,
      right: isLeft ? null : -_handleWidth / 2,
      top: 0,
      child: GestureDetector(
        onPanUpdate: (details) => onPan(details.delta.dx),
        onPanStart: (_) {
          setState(() {
            _isTrimming = true;
            _activeTrimHandle = isLeft ? 0 : 1;
          });
          HapticFeedback.lightImpact();
          if (_isPlaying) _playerController?.pause();
        },
        onPanEnd: (_) {
          setState(() {
            _isTrimming = false;
            _activeTrimHandle = null;
          });
          HapticFeedback.mediumImpact();
        },
        child: Container(
          width: _handleWidth,
          height: _trackHeight,
          decoration: BoxDecoration(
            color: _isTrimming && _activeTrimHandle == (isLeft ? 0 : 1)
                ? (isLeft ? Colors.green[300] : Colors.red[300])
                : (isLeft ? Colors.green[600] : Colors.red[600]),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: Colors.white,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 2, height: 6, color: Colors.white),
              const SizedBox(height: 2),
              Container(width: 2, height: 6, color: Colors.white),
              const SizedBox(height: 2),
              Container(width: 2, height: 6, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

// Custom Painters
class TimelineGridPainter extends CustomPainter {
  final double scale;
  final double totalDuration;

  TimelineGridPainter(this.scale, this.totalDuration);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey[600]!
      ..strokeWidth = 0.5;

    final textPaint = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // Draw vertical grid lines and time markers
    final pixelsPerSecond = 30.0 * scale;
    final seconds = totalDuration.ceil();

    for (int i = 0; i <= seconds; i++) {
      final x = i * pixelsPerSecond;
      if (x <= size.width) {
        // Draw grid line
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          paint,
        );

        // Draw time label
        textPaint.text = TextSpan(
          text: '${i}s',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
          ),
        );
        textPaint.layout();
        textPaint.paint(
          canvas,
          Offset(x + 2, 2),
        );

        // Draw sub-second markers
        if (scale > 1.0) {
          for (int j = 1; j < 4; j++) {
            final subX = x + (j * pixelsPerSecond / 4);
            if (subX <= size.width) {
              canvas.drawLine(
                Offset(subX, 0),
                Offset(subX, 10),
                Paint()
                  ..color = Colors.grey[700]!
                  ..strokeWidth = 0.3,
              );
            }
          }
        }
      }
    }

    // Draw horizontal lines for tracks
    canvas.drawLine(
      Offset(0, 40),
      Offset(size.width, 40),
      Paint()
        ..color = Colors.grey[500]!
        ..strokeWidth = 1,
    );

    canvas.drawLine(
      Offset(0, 40 + 60),
      Offset(size.width, 40 + 60),
      Paint()
        ..color = Colors.grey[500]!
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}