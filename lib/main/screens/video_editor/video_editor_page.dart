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
  int? _activeTrimHandle; // Track which handle is being dragged

  // Timeline constants
  static const double _trackHeight = 80.0;
  static const double _pixelsPerSecond = 50.0;
  static const double _minClipDurationSeconds = 0.5;
  List<List<Uint8List>> _clipThumbnails = [];

  @override
  void initState() {
    super.initState();
    print('=== VideoEditorPage initState ===');
    print('Files passed to editor: ${widget.files.length}');
    for (int i = 0; i < widget.files.length; i++) {
      print('File $i: ${widget.files[i].path}');
      print('File $i exists: ${widget.files[i].existsSync()}');
      if (widget.files[i].existsSync()) {
        print('File $i size: ${widget.files[i].lengthSync()} bytes');
      }
    }
    _validateAndInitializeClips();
  }

  Future<void> _validateAndInitializeClips() async {
    print('=== _validateAndInitializeClips called ===');

    // Validate files before attempting to load
    List<File> validFiles = [];
    for (int i = 0; i < widget.files.length; i++) {
      final file = widget.files[i];
      try {
        if (await file.exists()) {
          final stat = await file.stat();
          if (stat.size > 0) {
            validFiles.add(file);
            print('File $i is valid: ${file.path} (${stat.size} bytes)');
          } else {
            print('File $i is empty: ${file.path}');
          }
        } else {
          print('File $i does not exist: ${file.path}');
        }
      } catch (e) {
        print('Error checking file $i: $e');
      }
    }

    print('Valid files: ${validFiles.length}/${widget.files.length}');

    if (validFiles.isEmpty) {
      print('No valid files found');
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
      return;
    }

    // Update the files list to only include valid files
    // Note: We can't modify widget.files directly, so we'll use validFiles in initialization
    _initializeClips();
  }

  @override
  void dispose() {
    _playerController?.removeListener(_videoListener);
    _playerController?.dispose();
    super.dispose();
  }

  void _videoListener() {
    if (!mounted ||
        _playerController == null ||
        !_playerController!.value.isInitialized)
      return;

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
      double globalPosition =
          selectedClip.trackPosition +
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
    if (_selectedClipIndex == null ||
        _selectedClipIndex! >= _clips.length - 1) {
      setState(() => _isPlaying = false);
      return;
    }

    await _loadClipInPlayer(_selectedClipIndex! + 1, autoPlay: true);
  }

  Future<void> _loadClipInPlayer(
    int clipIndex, {
    bool autoPlay = false,
    Duration? seekTo,
  }) async {
    print('=== _loadClipInPlayer called ===');
    print('Clip index: $clipIndex, Clips length: ${_clips.length}');

    if (clipIndex >= _clips.length || clipIndex < 0) {
      print('Invalid clip index');
      return;
    }

    try {
      print('Disposing previous controller...');
      _playerController?.removeListener(_videoListener);
      await _playerController?.dispose();

      final clip = _clips[clipIndex];
      print('Loading clip: ${clip.file.path}');
      print('File exists: ${await clip.file.exists()}');

      if (!await clip.file.exists()) {
        print('File does not exist, cannot load clip');
        if (mounted) {
          setState(() {
            _selectedClipIndex = clipIndex;
          });
        }
        return;
      }

      _playerController = VideoPlayerController.file(clip.file);
      print('Initializing video player...');

      await _playerController!.initialize();

      if (!_playerController!.value.isInitialized) {
        print('Video player failed to initialize');
        return;
      }

      print('Video player initialized successfully');
      print('Video size: ${_playerController!.value.size}');
      print('Video duration: ${_playerController!.value.duration.inSeconds}s');

      if (mounted) {
        setState(() {
          _selectedClipIndex = clipIndex;
        });
      }

      _playerController!.addListener(_videoListener);

      // Seek to the right position within the clip's trim bounds
      final seekPosition = seekTo ?? clip.startTrim;
      final clampedSeekPosition = Duration(
        milliseconds: seekPosition.inMilliseconds.clamp(
          clip.startTrim.inMilliseconds,
          clip.endTrim.inMilliseconds,
        ),
      );
      print('Seeking to position: ${clampedSeekPosition.inSeconds}s');
      await _playerController!.seekTo(clampedSeekPosition);

      if (autoPlay && mounted) {
        print('Auto-playing video...');
        await _playerController!.play();
      }

      print('Video player setup complete');
    } catch (e) {
      print('Error loading clip: $e');
      if (mounted) {
        setState(() {
          _selectedClipIndex = clipIndex;
        });
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
        _selectedClipIndex! >= _clips.length)
      return;

    final currentClip = _clips[_selectedClipIndex!];
    final currentPosition = _playerController!.value.position;

    // Make sure we're within the clip's trim bounds
    if (currentPosition <= currentClip.startTrim ||
        currentPosition >= currentClip.endTrim)
      return;

    // Check minimum duration for both parts
    final firstPartDuration = currentPosition - currentClip.startTrim;
    final secondPartDuration = currentClip.endTrim - currentPosition;

    if (firstPartDuration.inMilliseconds < _minClipDurationSeconds * 1000 ||
        secondPartDuration.inMilliseconds < _minClipDurationSeconds * 1000) {
      _showSnackBar('Cannot split: resulting clips would be too short');
      return;
    }

    // Create two new clips
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

    // Stay on the first part
    _loadClipInPlayer(_selectedClipIndex!);
  }

  void _trimClip(int clipIndex, Duration newStart, Duration newEnd) {
    if (clipIndex >= _clips.length || clipIndex < 0) return;

    final clip = _clips[clipIndex];

    // Ensure bounds are within original duration
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

    // Ensure start < end
    if (newStart >= newEnd) return;

    // Ensure minimum duration
    if ((newEnd - newStart).inMilliseconds < _minClipDurationSeconds * 1000)
      return;

    // Debug output to verify trim operations
    print(
      'Trimming clip $clipIndex: ${newStart.inSeconds}s - ${newEnd.inSeconds}s',
    );

    setState(() {
      _clips[clipIndex] = clip.copyWith(startTrim: newStart, endTrim: newEnd);
      _recalculateClipPositions();
    });

    // Update player if this clip is currently selected
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

        setState(() {
          _currentPosition = seconds;
        });
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
      final outputPath =
          '${directory.path}/edited_video_${DateTime.now().millisecondsSinceEpoch}.mp4';

      // Build FFmpeg command
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

        // Only add audio filter if the file has audio
        filterComplex.add(
          '[$i:a]atrim=start=$startSeconds:duration=$durationSeconds,asetpts=PTS-STARTPTS[a$i]',
        );
      }

      // Concatenate video streams
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
          '${inputs.join(' ')} -filter_complex "${filterComplex.join(';')}" '
          '-map "[outv]" -map "[outa]" -c:v libx264 -c:a aac -y "$outputPath"';

      print('FFmpeg command: $command');

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        _showSnackBar('Video exported successfully!');
      } else {
        final logs = await session.getLogs();
        print('Export failed. Logs: $logs');
        _showSnackBar('Export failed. Check logs for details.');
      }
    } catch (e) {
      print('Export error: $e');
      _showSnackBar('Export error: $e');
    } finally {
      setState(() => _isExporting = false);
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  double get _totalDuration {
    if (_clips.isEmpty) return 10.0; // Default 10 seconds when no clips
    double total = 0.0;
    for (final clip in _clips) {
      total += clip.trimmedDuration.inMilliseconds / 1000.0;
    }
    return total > 0
        ? total
        : 10.0; // Ensure we always have a positive duration
  }

  Future<void> _initializeClips() async {
    print('=== _initializeClips called ===');
    print('Files count: ${widget.files.length}');

    if (widget.files.isEmpty) {
      print('No files provided to video editor');
      if (mounted) {
        setState(() {
          _isInitialized = true; // Set to true even with no files
        });
      }
      return;
    }

    try {
      await _performInitialization();
    } catch (e) {
      print('Initialization failed: $e');
      if (mounted) {
        setState(() {
          _isInitialized = true; // Set to true to show error state
        });
      }
    }
  }

  Future<void> _performInitialization() async {
    List<VideoClip> clips = [];
    List<List<Uint8List>> thumbnails = [];
    double position = 0.0;

    for (int i = 0; i < widget.files.length; i++) {
      final file = widget.files[i];
      print('Processing file $i: ${file.path}');
      print('File exists: ${await file.exists()}');

      if (!await file.exists()) {
        print('Skipping non-existent file: ${file.path}');
        continue;
      }

      try {
        // Get video duration with better error handling
        Duration duration = Duration.zero;
        VideoPlayerController? tempController;

        try {
          tempController = VideoPlayerController.file(file);
          print('Initializing video controller for file $i...');
          await tempController.initialize();
          duration = tempController.value.duration;
          print('Video duration: ${duration.inSeconds}s');
        } catch (e) {
          print('Error getting video duration for file $i: $e');
          // Set default duration if we can't get it
          duration = const Duration(seconds: 10);
        } finally {
          await tempController?.dispose();
        }

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
        print('Added clip $i successfully');

        // Generate thumbnails with better error handling
        final List<Uint8List> clipThumbs = [];
        try {
          final int thumbCount = max(
            3,
            (duration.inSeconds / 2).ceil().clamp(3, 10),
          );

          for (int t = 0; t < thumbCount; t++) {
            try {
              final thumbData = await VideoThumbnail.thumbnailData(
                video: file.path,
                imageFormat: ImageFormat.JPEG,
                maxWidth: 60,
                quality: 60,
                timeMs: (duration.inMilliseconds * t / thumbCount)
                    .round()
                    .clamp(0, duration.inMilliseconds - 1000),
              );
              if (thumbData != null) {
                clipThumbs.add(thumbData);
              }
            } catch (e) {
              print('Thumbnail generation error for clip $i, thumb $t: $e');
            }
          }
          thumbnails.add(clipThumbs);
          print('Generated ${clipThumbs.length} thumbnails for clip $i');
        } catch (e) {
          print('Thumbnail generation failed for clip $i: $e');
          thumbnails.add([]);
        }
      } catch (e) {
        print('Error initializing clip $i: $e');
      }
    }

    print('Total clips processed: ${clips.length}');

    if (mounted) {
      print('Setting clips state. Clips count: ${clips.length}');
      setState(() {
        _clips = clips;
        _clipThumbnails = thumbnails;
        _isInitialized = true;
      });
      print(
        'State updated - _isInitialized: $_isInitialized, _clips.length: ${_clips.length}',
      );

      if (_clips.isNotEmpty) {
        print('Loading first clip in player...');
        await _loadClipInPlayer(0);
        print('First clip loaded');
      } else {
        print('No clips to load');
      }
    } else {
      print('Widget not mounted, skipping state update');
    }
  }

  @override
  Widget build(BuildContext context) {
    print('=== BUILD CALLED ===');
    print('_isInitialized: $_isInitialized');
    print('_clips.length: ${_clips.length}');
    print('widget.files.length: ${widget.files.length}');

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Video Editor',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_isExporting)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.file_download),
              onPressed: _clips.isNotEmpty ? _exportVideo : null,
            ),
        ],
      ),
      body: Column(
        children: [
          // Debug info - can be removed in production
          if (true) // Set to false to hide debug info
            Container(
              color: Colors.red[900],
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DEBUG: Init:$_isInitialized, Clips:${_clips.length}, Files:${widget.files.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  if (widget.files.isNotEmpty)
                    Text(
                      'First file: ${widget.files.first.path}',
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  if (_clips.isNotEmpty)
                    Text(
                      'First clip duration: ${_clips.first.originalDuration.inSeconds}s',
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                ],
              ),
            ),
          Expanded(
            child: !_isInitialized
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 16),
                        Text(
                          'Loading videos...',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  )
                : _clips.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.video_library,
                          color: Colors.white,
                          size: 64,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No video files loaded',
                          style: TextStyle(color: Colors.white, fontSize: 18),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Files provided: ${widget.files.length}',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 14,
                          ),
                        ),
                        if (widget.files.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _isInitialized = false;
                              });
                              _initializeClips();
                            },
                            child: const Text('Retry Loading'),
                          ),
                        ],
                      ],
                    ),
                  )
                : Column(
                    children: [
                      // Video Preview
                      Expanded(
                        flex: 3,
                        child: Container(
                          color: Colors.grey[900],
                          child: _buildVideoPreview(),
                        ),
                      ),
                      // Timeline
                      Expanded(
                        flex: 2,
                        child: Container(
                          color: Colors.grey[800],
                          child: Column(
                            children: [
                              _buildTimeline(),
                              // Add dedicated trim control for selected clip
                              if (_selectedClipIndex != null)
                                _buildTrimControlWidget(
                                  _clips[_selectedClipIndex!],
                                  _selectedClipIndex!,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPreview() {
    print('=== _buildVideoPreview called ===');
    print('Player controller null: ${_playerController == null}');
    print(
      'Player initialized: ${_playerController?.value.isInitialized ?? false}',
    );

    if (_playerController == null || !_playerController!.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text('Loading video...', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    }

    // Check if video has valid size
    final videoSize = _playerController!.value.size;
    if (videoSize.width == 0 || videoSize.height == 0) {
      print('Video has invalid size: $videoSize');
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error, color: Colors.red, size: 48),
              SizedBox(height: 16),
              Text(
                'Video format not supported',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    print('Video size: $videoSize');
    print('Aspect ratio: ${_playerController!.value.aspectRatio}');

    return Container(
      color: Colors.black,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: _playerController!.value.aspectRatio,
              child: VideoPlayer(_playerController!),
            ),
          ),
          Positioned(
            bottom: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                    color: Colors.white,
                    iconSize: 40,
                    onPressed: _playPause,
                  ),
                  const SizedBox(width: 20),
                  IconButton(
                    icon: const Icon(Icons.content_cut),
                    color: Colors.white,
                    iconSize: 30,
                    onPressed: _selectedClipIndex != null ? _splitClip : null,
                  ),
                ],
              ),
            ),
          ),
          // Show clip info
          if (_selectedClipIndex != null)
            Positioned(
              top: 20,
              left: 20,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Clip ${_selectedClipIndex! + 1} of ${_clips.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    return Column(
      children: [
        // Timeline Header
        Container(
          height: 40,
          color: Colors.grey[700],
          child: Row(
            children: [
              const SizedBox(width: 10),
              Text(
                'Timeline: ${_totalDuration.toStringAsFixed(1)}s',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.zoom_in, color: Colors.white),
                onPressed: () => setState(
                  () => _timelineScale = min(_timelineScale * 1.5, 4.0),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.zoom_out, color: Colors.white),
                onPressed: () => setState(
                  () => _timelineScale = max(_timelineScale / 1.5, 0.3),
                ),
              ),
            ],
          ),
        ),
        // Timeline Track
        Flexible(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Container(
              height: _trackHeight,
              width: max(
                MediaQuery.of(context).size.width,
                _totalDuration * _pixelsPerSecond * _timelineScale,
              ),
              child: Stack(
                children: [
                  // Background
                  Container(
                    color: Colors.grey[600],
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: TimelineGridPainter(_timelineScale),
                    ),
                  ),
                  // Clips
                  ..._clips.asMap().entries.map((entry) {
                    return _buildClipWidget(entry.value, entry.key);
                  }).toList(),
                  // Playhead
                  Positioned(
                    left:
                        _currentPosition * _pixelsPerSecond * _timelineScale -
                        1,
                    top: 0,
                    child: Container(
                      width: 2,
                      height: _trackHeight,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Scrubber
        SizedBox(height: 30, child: _buildTimelineScrubber()),
      ],
    );
  }

  Widget _buildClipWidget(VideoClip clip, int index) {
    final totalClipWidth =
        clip.originalDuration.inMilliseconds /
        1000.0 *
        _pixelsPerSecond *
        _timelineScale;
    final trimmedWidth =
        clip.trimmedDuration.inMilliseconds /
        1000.0 *
        _pixelsPerSecond *
        _timelineScale;
    final left = clip.trackPosition * _pixelsPerSecond * _timelineScale;
    final isSelected = _selectedClipIndex == index;
    final thumbs = index < _clipThumbnails.length
        ? _clipThumbnails[index]
        : <Uint8List>[];

    // Calculate normalized positions for trim handles (0.0 to 1.0)
    final startPosition =
        clip.startTrim.inMilliseconds / clip.originalDuration.inMilliseconds;
    final endPosition =
        clip.endTrim.inMilliseconds / clip.originalDuration.inMilliseconds;

    return Positioned(
      left: left,
      top: 10,
      child: GestureDetector(
        onTap: () => _loadClipInPlayer(index),
        child: Container(
          width: trimmedWidth,
          height: _trackHeight - 20,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // Full clip background (shows trimmed out parts in darker color)
                  Container(
                    width: totalClipWidth,
                    height: _trackHeight - 20,
                    decoration: BoxDecoration(
                      color: Colors.grey[700],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),

                  // Active (trimmed) portion
                  Positioned(
                    left: startPosition * totalClipWidth,
                    child: Container(
                      width: (endPosition - startPosition) * totalClipWidth,
                      height: _trackHeight - 20,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.blue[600]
                            : Colors.purple[600],
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isSelected
                              ? Colors.blue[300]!
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Stack(
                        children: [
                          // Thumbnails
                          if (thumbs.isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
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

                          // Clip info
                          Positioned(
                            top: 4,
                            left: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: Text(
                                'Clip ${index + 1} (${clip.trimmedDuration.inSeconds}s)',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Start trim handle
                  _buildAdvancedTrimHandle(
                    isStart: true,
                    clipIndex: index,
                    position: startPosition * totalClipWidth,
                    totalWidth: totalClipWidth,
                  ),

                  // End trim handle
                  _buildAdvancedTrimHandle(
                    isStart: false,
                    clipIndex: index,
                    position: endPosition * totalClipWidth,
                    totalWidth: totalClipWidth,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildAdvancedTrimHandle({
    required bool isStart,
    required int clipIndex,
    required double position,
    required double totalWidth,
  }) {
    return Positioned(
      left: position - 6, // Center the handle
      top: -5,
      child: GestureDetector(
        onPanUpdate: (details) {
          final clip = _clips[clipIndex];

          // Use simple delta-based approach for more responsive dragging
          final deltaX = details.delta.dx;
          final currentNormalizedPos = position / totalWidth;

          // Calculate new normalized position based on drag delta
          final pixelDelta = deltaX / totalWidth;
          final newNormalizedPosition = (currentNormalizedPos + pixelDelta)
              .clamp(0.0, 1.0);

          // Convert to duration
          final newDuration = Duration(
            milliseconds:
                (newNormalizedPosition * clip.originalDuration.inMilliseconds)
                    .round(),
          );

          if (isStart) {
            // Update start trim, ensure it doesn't go past end
            final maxStart =
                clip.endTrim -
                Duration(
                  milliseconds: (_minClipDurationSeconds * 1000).round(),
                );
            final clampedStart = Duration(
              milliseconds: newDuration.inMilliseconds.clamp(
                0,
                maxStart.inMilliseconds,
              ),
            );
            if (clampedStart != clip.startTrim) {
              _trimClip(clipIndex, clampedStart, clip.endTrim);
            }
          } else {
            // Update end trim, ensure it doesn't go before start
            final minEnd =
                clip.startTrim +
                Duration(
                  milliseconds: (_minClipDurationSeconds * 1000).round(),
                );
            final clampedEnd = Duration(
              milliseconds: newDuration.inMilliseconds.clamp(
                minEnd.inMilliseconds,
                clip.originalDuration.inMilliseconds,
              ),
            );
            if (clampedEnd != clip.endTrim) {
              _trimClip(clipIndex, clip.startTrim, clampedEnd);
            }
          }
        },
        onPanStart: (_) {
          // Visual feedback and stop playback during trimming
          setState(() {
            _isTrimming = true;
            _activeTrimHandle = isStart ? 0 : 1; // 0 for start, 1 for end
          });
          HapticFeedback.lightImpact();
          if (_isPlaying) {
            _playerController?.pause();
          }
        },
        onPanEnd: (_) {
          // Provide feedback when trimming is complete
          setState(() {
            _isTrimming = false;
            _activeTrimHandle = null;
          });
          HapticFeedback.mediumImpact();
        },
        child: Container(
          width: 12,
          height: _trackHeight - 10,
          decoration: BoxDecoration(
            color: _isTrimming && _activeTrimHandle == (isStart ? 0 : 1)
                ? (isStart ? Colors.green[300] : Colors.red[300])
                : (isStart ? Colors.green[600] : Colors.red[600]),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _isTrimming && _activeTrimHandle == (isStart ? 0 : 1)
                  ? Colors.white
                  : (isStart ? Colors.green[300]! : Colors.red[300]!),
              width: _isTrimming && _activeTrimHandle == (isStart ? 0 : 1)
                  ? 3
                  : 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(
                  _isTrimming && _activeTrimHandle == (isStart ? 0 : 1)
                      ? 0.6
                      : 0.3,
                ),
                blurRadius:
                    _isTrimming && _activeTrimHandle == (isStart ? 0 : 1)
                    ? 8
                    : 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 2, height: 8, color: Colors.white),
              const SizedBox(height: 2),
              Container(width: 2, height: 8, color: Colors.white),
              const SizedBox(height: 2),
              Container(width: 2, height: 8, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrimControlWidget(VideoClip clip, int clipIndex) {
    return Container(
      height: 80,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        border: Border(top: BorderSide(color: Colors.grey[600]!)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Trim Clip ${clipIndex + 1} (${clip.originalDuration.inSeconds}s total)',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final timelineWidth = constraints.maxWidth;
              final startPosition =
                  clip.startTrim.inMilliseconds /
                  clip.originalDuration.inMilliseconds;
              final endPosition =
                  clip.endTrim.inMilliseconds /
                  clip.originalDuration.inMilliseconds;

              return Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.grey[700],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Stack(
                  children: [
                    // Full timeline background with frame markers
                    Container(
                      width: timelineWidth,
                      height: 40,
                      child: CustomPaint(
                        painter: TrimTimelinePainter(clip.originalDuration),
                      ),
                    ),

                    // Trimmed out areas (darker)
                    if (startPosition > 0)
                      Positioned(
                        left: 0,
                        child: Container(
                          width: startPosition * timelineWidth,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(4),
                              bottomLeft: Radius.circular(4),
                            ),
                          ),
                        ),
                      ),

                    if (endPosition < 1.0)
                      Positioned(
                        right: 0,
                        child: Container(
                          width: (1.0 - endPosition) * timelineWidth,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(4),
                              bottomRight: Radius.circular(4),
                            ),
                          ),
                        ),
                      ),

                    // Active trim area
                    Positioned(
                      left: startPosition * timelineWidth,
                      child: Container(
                        width: (endPosition - startPosition) * timelineWidth,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.blue[600]!.withOpacity(0.3),
                          border: Border.all(
                            color: Colors.blue[400]!,
                            width: 2,
                          ),
                        ),
                      ),
                    ),

                    // Start handle
                    _buildPrecisionTrimHandle(
                      position: startPosition * timelineWidth,
                      isStart: true,
                      clipIndex: clipIndex,
                      timelineWidth: timelineWidth,
                      label:
                          '${(clip.startTrim.inMilliseconds / 1000).toStringAsFixed(1)}s',
                    ),

                    // End handle
                    _buildPrecisionTrimHandle(
                      position: endPosition * timelineWidth,
                      isStart: false,
                      clipIndex: clipIndex,
                      timelineWidth: timelineWidth,
                      label:
                          '${(clip.endTrim.inMilliseconds / 1000).toStringAsFixed(1)}s',
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPrecisionTrimHandle({
    required double position,
    required bool isStart,
    required int clipIndex,
    required double timelineWidth,
    required String label,
  }) {
    return Positioned(
      left: position - 8, // Center the handle
      top: -5,
      child: Column(
        children: [
          // Time label
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: isStart ? Colors.green[700] : Colors.red[700],
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
          ),

          // Handle
          GestureDetector(
            onPanUpdate: (details) {
              final clip = _clips[clipIndex];

              // Use delta-based approach for more responsive dragging
              final deltaX = details.delta.dx;
              final currentNormalizedPos = position / timelineWidth;

              // Calculate new normalized position based on drag delta
              final pixelDelta = deltaX / timelineWidth;
              final newNormalizedPosition = (currentNormalizedPos + pixelDelta)
                  .clamp(0.0, 1.0);

              // Convert to duration
              final newDuration = Duration(
                milliseconds:
                    (newNormalizedPosition *
                            clip.originalDuration.inMilliseconds)
                        .round(),
              );

              if (isStart) {
                // Ensure start doesn't go past end - minimum duration
                final maxStart =
                    clip.endTrim -
                    Duration(
                      milliseconds: (_minClipDurationSeconds * 1000).round(),
                    );
                final clampedStart = Duration(
                  milliseconds: newDuration.inMilliseconds.clamp(
                    0,
                    maxStart.inMilliseconds,
                  ),
                );
                if (clampedStart != clip.startTrim) {
                  _trimClip(clipIndex, clampedStart, clip.endTrim);
                }
              } else {
                // Ensure end doesn't go before start + minimum duration
                final minEnd =
                    clip.startTrim +
                    Duration(
                      milliseconds: (_minClipDurationSeconds * 1000).round(),
                    );
                final clampedEnd = Duration(
                  milliseconds: newDuration.inMilliseconds.clamp(
                    minEnd.inMilliseconds,
                    clip.originalDuration.inMilliseconds,
                  ),
                );
                if (clampedEnd != clip.endTrim) {
                  _trimClip(clipIndex, clip.startTrim, clampedEnd);
                }
              }

              // Provide haptic feedback
              HapticFeedback.selectionClick();
            },
            onPanStart: (_) {
              // Stop playback during trimming for better UX
              setState(() {
                _isTrimming = true;
                _activeTrimHandle = isStart ? 0 : 1;
              });
              if (_isPlaying) {
                _playerController?.pause();
              }
              HapticFeedback.lightImpact();
            },
            onPanEnd: (_) {
              // Update the player position if this clip is currently selected
              setState(() {
                _isTrimming = false;
                _activeTrimHandle = null;
              });
              if (_selectedClipIndex == clipIndex &&
                  _playerController != null) {
                final currentPos = _playerController!.value.position;
                final clip = _clips[clipIndex];
                if (currentPos < clip.startTrim || currentPos > clip.endTrim) {
                  _playerController!.seekTo(clip.startTrim);
                }
              }
              HapticFeedback.mediumImpact();
            },
            child: Container(
              width: 16,
              height: 50,
              decoration: BoxDecoration(
                color: _isTrimming && _activeTrimHandle == (isStart ? 0 : 1)
                    ? (isStart ? Colors.green[300] : Colors.red[300])
                    : (isStart ? Colors.green[600] : Colors.red[600]),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isTrimming && _activeTrimHandle == (isStart ? 0 : 1)
                      ? Colors.yellow
                      : Colors.white,
                  width: _isTrimming && _activeTrimHandle == (isStart ? 0 : 1)
                      ? 3
                      : 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(
                      _isTrimming && _activeTrimHandle == (isStart ? 0 : 1)
                          ? 0.6
                          : 0.4,
                    ),
                    blurRadius:
                        _isTrimming && _activeTrimHandle == (isStart ? 0 : 1)
                        ? 10
                        : 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isStart
                        ? Icons.keyboard_arrow_right
                        : Icons.keyboard_arrow_left,
                    color: Colors.white,
                    size: 16,
                  ),
                  Container(width: 8, height: 2, color: Colors.white),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineScrubber() {
    return Container(
      height: 30,
      width: double.infinity,
      color: Colors.grey[700],
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          final box = context.findRenderObject() as RenderBox?;
          if (box != null) {
            final localPosition = box.globalToLocal(details.globalPosition);
            final timelineWidth = max(
              MediaQuery.of(context).size.width,
              _totalDuration * _pixelsPerSecond * _timelineScale,
            );
            final tappedSeconds =
                (localPosition.dx / (timelineWidth)) * _totalDuration;
            _seekToPosition(tappedSeconds);
          }
        },
        onTapDown: (details) {
          final box = context.findRenderObject() as RenderBox?;
          if (box != null) {
            final localPosition = box.globalToLocal(details.globalPosition);
            final timelineWidth = max(
              MediaQuery.of(context).size.width,
              _totalDuration * _pixelsPerSecond * _timelineScale,
            );
            final tappedSeconds =
                (localPosition.dx / (timelineWidth)) * _totalDuration;
            _seekToPosition(tappedSeconds);
          }
        },
        child: CustomPaint(
          size: Size(
            max(
              MediaQuery.of(context).size.width,
              _totalDuration * _pixelsPerSecond * _timelineScale,
            ),
            30,
          ),
          painter: TimelineScrubberPainter(
            _currentPosition,
            _timelineScale,
            _totalDuration,
          ),
        ),
      ),
    );
  }
}

// Custom Painters
class TimelineGridPainter extends CustomPainter {
  final double scale;
  TimelineGridPainter(this.scale);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey[400]!
      ..strokeWidth = 0.5;

    for (double i = 0; i < size.width; i += 50 * scale) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class TrimTimelinePainter extends CustomPainter {
  final Duration duration;
  TrimTimelinePainter(this.duration);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;

    final seconds = duration.inSeconds;
    if (seconds == 0) return;

    for (int i = 0; i <= seconds; i++) {
      final x = i * size.width / seconds;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);

      final textPainter = TextPainter(
        text: TextSpan(
          text: '${i}s',
          style: const TextStyle(color: Colors.white, fontSize: 8),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - 8, size.height - 14));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class TimelineScrubberPainter extends CustomPainter {
  final double currentPosition;
  final double scale;
  final double totalDuration;

  TimelineScrubberPainter(this.currentPosition, this.scale, this.totalDuration);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white70
      ..strokeWidth = 1;

    // Draw time markers
    for (int i = 0; i <= totalDuration.ceil(); i++) {
      final x = i * 50.0 * scale;
      if (x <= size.width) {
        canvas.drawLine(Offset(x, 0), Offset(x, 10), paint);

        final textPainter = TextPainter(
          text: TextSpan(
            text: '${i}s',
            style: const TextStyle(color: Colors.white, fontSize: 10),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(x - 8, 15));
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
