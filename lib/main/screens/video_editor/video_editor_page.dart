import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/statistics.dart';

class VideoClip {
  final String id;
  final File file;
  VideoPlayerController? controller;
  VideoPlayerController? previewController;
  double trimStart = 0.0;
  double trimEnd = 1.0;
  double speed = 1.0;
  double cropX = 0.0;
  double cropY = 0.0;
  double cropWidth = 1.0;
  double cropHeight = 1.0;
  double zoom = 1.0;
  double rotation = 0.0;
  bool flipHorizontal = false;
  bool flipVertical = false;
  String filter = 'None';
  double brightness = 0.0;
  double contrast = 1.0;
  double saturation = 1.0;
  double hue = 0.0;
  double opacity = 1.0;
  Duration? duration;
  File? processedFile;
  bool needsReprocessing = false;
  
  VideoClip({required this.id, required this.file});
  
  void dispose() {
    controller?.dispose();
    previewController?.dispose();
  }
  
  double getEffectiveDuration() {
    if (duration == null) return 0.0;
    double originalDuration = duration!.inMilliseconds.toDouble();
    double trimmedDuration = originalDuration * (trimEnd - trimStart);
    return trimmedDuration / speed;
  }
  
  void markForReprocessing() {
    needsReprocessing = true;
  }
}

class TextOverlay {
  String id;
  String text;
  double x;
  double y;
  Color color;
  double fontSize;
  String fontFamily;
  double startTime;
  double endTime;
  double rotation;
  FontWeight fontWeight;
  bool isItalic;
  bool hasStroke;
  Color strokeColor;
  double strokeWidth;
  String alignment;
  
  TextOverlay({
    required this.id,
    required this.text,
    required this.x,
    required this.y,
    this.color = Colors.white,
    this.fontSize = 32,
    this.fontFamily = 'Arial',
    this.startTime = 0,
    this.endTime = 10,
    this.rotation = 0,
    this.fontWeight = FontWeight.normal,
    this.isItalic = false,
    this.hasStroke = false,
    this.strokeColor = Colors.black,
    this.strokeWidth = 2.0,
    this.alignment = 'center',
  });
}

class StickerOverlay {
  String id;
  String content;
  double x;
  double y;
  double scale;
  double startTime;
  double endTime;
  double rotation;
  double opacity;
  
  StickerOverlay({
    required this.id,
    required this.content,
    required this.x,
    required this.y,
    this.scale = 1.0,
    this.startTime = 0,
    this.endTime = 10,
    this.rotation = 0,
    this.opacity = 1.0,
  });
}

class AudioTrack {
  final String id;
  final File file;
  double startTime;
  double volume;
  bool isMuted;
  double fadeIn;
  double fadeOut;
  
  AudioTrack({
    required this.id,
    required this.file,
    this.startTime = 0.0,
    this.volume = 1.0,
    this.isMuted = false,
    this.fadeIn = 0.0,
    this.fadeOut = 0.0,
  });
}

class AdvancedVideoEditor extends StatefulWidget {
  final List<File> initialFiles;
  
  const AdvancedVideoEditor({super.key, required this.initialFiles});

  @override
  State<AdvancedVideoEditor> createState() => _AdvancedVideoEditorState();
}

class _AdvancedVideoEditorState extends State<AdvancedVideoEditor> 
    with TickerProviderStateMixin {
  
  // Core state
  List<VideoClip> _clips = [];
  int _currentClipIndex = 0;
  VideoPlayerController? _previewController;
  
  // Overlays
  List<TextOverlay> _textOverlays = [];
  List<StickerOverlay> _stickerOverlays = [];
  List<AudioTrack> _audioTracks = [];
  
  // UI State
  bool _isPlaying = false;
  double _currentPosition = 0.0;
  double _totalDuration = 0.0;
  bool _showTimeline = true;
  String _selectedTool = 'none';
  
  // Timeline
  double _timelineZoom = 1.0;
  ScrollController _timelineScrollController = ScrollController();
  
  // Processing
  bool _isProcessing = false;
  bool _isExporting = false;
  double _exportProgress = 0.0;
  String _currentStep = '';
  
  // Audio recording
  FlutterSoundRecorder? _recorder;
  bool _isRecordingAudio = false;
  
  // Export settings
  String _exportResolution = '1080p';
  int _exportFrameRate = 30;
  String _exportFormat = 'mp4';
  int _exportBitrate = 8000;
  bool _addWatermark = false;
  String _watermarkText = '';
  
  // Animation controllers
  late AnimationController _toolbarAnimController;
  late AnimationController _timelineAnimController;
  
  // Filters
  final List<Map<String, dynamic>> _availableFilters = [
    {'name': 'None', 'icon': Icons.filter_none},
    {'name': 'Vintage', 'icon': Icons.photo_filter},
    {'name': 'B&W', 'icon': Icons.monochrome_photos},
    {'name': 'Sepia', 'icon': Icons.filter_vintage},
    {'name': 'Bright', 'icon': Icons.brightness_high},
    {'name': 'Dramatic', 'icon': Icons.dark_mode},
    {'name': 'Warm', 'icon': Icons.wb_sunny},
    {'name': 'Cool', 'icon': Icons.ac_unit},
    {'name': 'Saturated', 'icon': Icons.palette},
    {'name': 'Faded', 'icon': Icons.opacity},
    {'name': 'Sharp', 'icon': Icons.tune},
    {'name': 'Blur', 'icon': Icons.blur_on},
  ];
  
  // Stickers/Emojis
  final List<String> _availableStickers = [
    '😀', '😂', '🥰', '😎', '🤔', '👍', '❤️', '🔥', '⭐', '✨',
    '🎉', '🎊', '🌟', '💯', '🚀', '💖', '👏', '🙌', '🎈', '🌈',
    '🎵', '🎶', '💫', '⚡', '🌙', '☀️', '🌸', '🍀', '🦋', '🌺'
  ];

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeClips();
    _initializeRecorder();
  }

  void _initializeAnimations() {
    _toolbarAnimController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _timelineAnimController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _toolbarAnimController.forward();
    _timelineAnimController.forward();
  }

  void _initializeRecorder() async {
    try {
      _recorder = FlutterSoundRecorder();
      await _recorder!.openRecorder();
    } catch (e) {
      debugPrint('Error initializing recorder: $e');
    }
  }

  void _initializeClips() async {
    for (int i = 0; i < widget.initialFiles.length; i++) {
      final clip = VideoClip(
        id: 'clip_${DateTime.now().millisecondsSinceEpoch}_$i',
        file: widget.initialFiles[i],
      );
      
      try {
        clip.controller = VideoPlayerController.file(widget.initialFiles[i]);
        await clip.controller!.initialize();
        clip.duration = clip.controller!.value.duration;
        
        clip.previewController = VideoPlayerController.file(widget.initialFiles[i]);
        await clip.previewController!.initialize();
        
        _clips.add(clip);
      } catch (e) {
        debugPrint('Error initializing clip $i: $e');
      }
    }
    
    if (_clips.isNotEmpty) {
      _previewController = _clips[0].previewController;
      _previewController!.addListener(_videoListener);
      _calculateTotalDuration();
    }
    
    if (mounted) setState(() {});
  }

  void _calculateTotalDuration() {
    _totalDuration = 0.0;
    for (var clip in _clips) {
      _totalDuration += clip.getEffectiveDuration();
    }
  }

  void _videoListener() {
    if (_previewController != null && _previewController!.value.isInitialized) {
      if (mounted) {
        setState(() {
          _currentPosition = _previewController!.value.position.inMilliseconds.toDouble();
          _isPlaying = _previewController!.value.isPlaying;
        });
      }
    }
  }

  // Processing methods
  Future<void> _processClip(VideoClip clip) async {
    if (!clip.needsReprocessing && clip.processedFile != null) return;
    
    setState(() => _isProcessing = true);
    
    try {
      final tempDir = await getTemporaryDirectory();
      final outputPath = '${tempDir.path}/processed_${clip.id}_${DateTime.now().millisecondsSinceEpoch}.mp4';
      
      String command = await _buildProcessingCommand(clip, outputPath);
      
      await FFmpegKit.execute(command);
      
      // Update preview
      clip.previewController?.dispose();
      clip.processedFile = File(outputPath);
      clip.previewController = VideoPlayerController.file(clip.processedFile!);
      await clip.previewController!.initialize();
      
      if (_clips[_currentClipIndex].id == clip.id) {
        _previewController?.removeListener(_videoListener);
        _previewController = clip.previewController;
        _previewController!.addListener(_videoListener);
      }
      
      clip.needsReprocessing = false;
      _calculateTotalDuration();
      
    } catch (e) {
      debugPrint('Error processing clip: $e');
      _showSnackBar('Processing failed: $e');
    }
    
    setState(() => _isProcessing = false);
  }

  Future<String> _buildProcessingCommand(VideoClip clip, String outputPath) async {
    List<String> videoFilters = [];
    String inputPath = clip.file.path;
    
    // Trim
    String trimOptions = '';
    if (clip.trimStart > 0 || clip.trimEnd < 1.0) {
      final duration = clip.duration!.inSeconds;
      final start = clip.trimStart * duration;
      final end = clip.trimEnd * duration;
      trimOptions = '-ss $start -t ${end - start}';
    }
    
    // Speed
    if (clip.speed != 1.0) {
      videoFilters.add('setpts=${1/clip.speed}*PTS');
    }
    
    // Crop and zoom
    if (clip.cropX != 0.0 || clip.cropY != 0.0 || 
        clip.cropWidth != 1.0 || clip.cropHeight != 1.0) {
      videoFilters.add('crop=iw*${clip.cropWidth}:ih*${clip.cropHeight}:iw*${clip.cropX}:ih*${clip.cropY}');
    }
    
    if (clip.zoom != 1.0) {
      videoFilters.add('scale=iw*${clip.zoom}:ih*${clip.zoom}');
    }
    
    // Rotation
    if (clip.rotation != 0.0) {
      double radians = clip.rotation * pi / 180;
      videoFilters.add('rotate=$radians');
    }
    
    // Flip
    if (clip.flipHorizontal) videoFilters.add('hflip');
    if (clip.flipVertical) videoFilters.add('vflip');
    
    // Color adjustments
    if (clip.brightness != 0.0 || clip.contrast != 1.0 || 
        clip.saturation != 1.0 || clip.hue != 0.0) {
      videoFilters.add('eq=brightness=${clip.brightness}:contrast=${clip.contrast}:saturation=${clip.saturation}:hue=${clip.hue}');
    }
    
    // Opacity
    if (clip.opacity != 1.0) {
      videoFilters.add('format=yuva420p,colorchannelmixer=aa=${clip.opacity}');
    }
    
    // Filters
    switch (clip.filter) {
      case 'B&W':
        videoFilters.add('colorchannelmixer=.3:.4:.3:0:.3:.4:.3:0:.3:.4:.3');
        break;
      case 'Sepia':
        videoFilters.add('colorchannelmixer=.393:.769:.189:0:.349:.686:.168:0:.272:.534:.131');
        break;
      case 'Vintage':
        videoFilters.add('curves=vintage');
        break;
      case 'Warm':
        videoFilters.add('colortemperature=temperature=4000');
        break;
      case 'Cool':
        videoFilters.add('colortemperature=temperature=7000');
        break;
      case 'Bright':
        videoFilters.add('eq=brightness=0.2:contrast=1.2');
        break;
      case 'Dramatic':
        videoFilters.add('eq=brightness=-0.1:contrast=1.5:saturation=1.2');
        break;
      case 'Saturated':
        videoFilters.add('eq=saturation=1.5');
        break;
      case 'Faded':
        videoFilters.add('eq=brightness=0.1:contrast=0.8:saturation=0.7');
        break;
      case 'Sharp':
        videoFilters.add('unsharp=5:5:1.0:5:5:0.0');
        break;
      case 'Blur':
        videoFilters.add('boxblur=2:2');
        break;
    }
    
    String videoFilterString = videoFilters.isNotEmpty ? 
      '-vf "${videoFilters.join(',')}"' : '';
    
    return '$trimOptions -i "$inputPath" $videoFilterString -c:v libx264 -preset ultrafast -crf 23 "$outputPath"';
  }

  @override
  void dispose() {
    _toolbarAnimController.dispose();
    _timelineAnimController.dispose();
    _recorder?.closeRecorder();
    _timelineScrollController.dispose();
    for (var clip in _clips) {
      clip.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _clips.isEmpty 
        ? const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          )
        : Column(
            children: [
              _buildTopBar(),
              Expanded(child: _buildPreviewArea()),
              if (_showTimeline) _buildTimeline(),
              _buildToolbar(),
            ],
          ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 100,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top,
        left: 16,
        right: 16,
        bottom: 8,
      ),
      decoration: BoxDecoration(
        color: Colors.black,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Close button
          GestureDetector(
            onTap: () => _showExitDialog(),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 20),
            ),
          ),
          
          const SizedBox(width: 16),
          
          // Title and progress
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Video Editor',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_isProcessing || _isExporting)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isExporting ? 'Exporting...' : 'Processing...',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          
          // Timeline toggle
          GestureDetector(
            onTap: () {
              setState(() => _showTimeline = !_showTimeline);
              if (_showTimeline) {
                _timelineAnimController.forward();
              } else {
                _timelineAnimController.reverse();
              }
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _showTimeline ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          
          const SizedBox(width: 12),
          
          // Export button
          GestureDetector(
            onTap: _showExportDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Export',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewArea() {
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          // Video preview
          Center(
            child: _previewController?.value.isInitialized == true
              ? AspectRatio(
                  aspectRatio: _previewController!.value.aspectRatio,
                  child: VideoPlayer(_previewController!),
                )
              : Container(
                  width: double.infinity,
                  child: const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),
          ),
          
          // Text overlays
          ..._textOverlays.map((overlay) => _buildDraggableTextOverlay(overlay)),
          
          // Sticker overlays
          ..._stickerOverlays.map((overlay) => _buildDraggableStickerOverlay(overlay)),
          
          // Play/pause button
          Center(
            child: GestureDetector(
              onTap: _togglePlayPause,
              child: AnimatedOpacity(
                opacity: _isPlaying ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              ),
            ),
          ),
          
          // Recording indicator
          if (_isRecordingAudio)
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.fiber_manual_record, color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Text('REC', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          
          // Current time display
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${_formatDuration(_currentPosition.toInt())} / ${_formatDuration(_totalDuration.toInt())}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDraggableTextOverlay(TextOverlay overlay) {
    return Positioned(
      left: overlay.x,
      top: overlay.y,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            overlay.x = (overlay.x + details.delta.dx)
                .clamp(0.0, MediaQuery.of(context).size.width - 100);
            overlay.y = (overlay.y + details.delta.dy)
                .clamp(0.0, MediaQuery.of(context).size.height - 100);
          });
        },
        onTap: () => _editTextOverlay(overlay),
        child: Transform.rotate(
          angle: overlay.rotation * pi / 180,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white.withOpacity(0.5)),
            ),
            child: Text(
              overlay.text,
              style: TextStyle(
                color: overlay.color,
                fontSize: overlay.fontSize,
                fontWeight: overlay.fontWeight,
                fontStyle: overlay.isItalic ? FontStyle.italic : FontStyle.normal,
                shadows: overlay.hasStroke ? [
                  Shadow(
                    offset: const Offset(1, 1),
                    blurRadius: 2,
                    color: overlay.strokeColor,
                  ),
                ] : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDraggableStickerOverlay(StickerOverlay overlay) {
    return Positioned(
      left: overlay.x,
      top: overlay.y,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            overlay.x = (overlay.x + details.delta.dx)
                .clamp(0.0, MediaQuery.of(context).size.width - 50);
            overlay.y = (overlay.y + details.delta.dy)
                .clamp(0.0, MediaQuery.of(context).size.height - 50);
          });
        },
        onScaleUpdate: (details) {
          setState(() {
            overlay.scale = (overlay.scale * details.scale).clamp(0.5, 3.0);
          });
        },
        onLongPress: () => _editStickerOverlay(overlay),
        child: Transform.rotate(
          angle: overlay.rotation * pi / 180,
          child: Transform.scale(
            scale: overlay.scale,
            child: Opacity(
              opacity: overlay.opacity,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white.withOpacity(0.5)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  overlay.content,
                  style: const TextStyle(fontSize: 48),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeline() {
    return AnimatedBuilder(
      animation: _timelineAnimController,
      builder: (context, child) {
        return Container(
          height: 180 * _timelineAnimController.value,
          color: const Color(0xFF1A1A1A),
          child: child,
        );
      },
      child: Column(
        children: [
          // Timeline controls
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  _formatDuration(_currentPosition.toInt()),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                    ),
                    child: Slider(
                      value: _totalDuration > 0 ? 
                        (_currentPosition / _totalDuration).clamp(0.0, 1.0) : 0.0,
                      onChanged: (value) => _seekToPosition(value),
                      activeColor: Colors.blue,
                      inactiveColor: Colors.grey[600],
                    ),
                  ),
                ),
                Text(
                  _formatDuration(_totalDuration.toInt()),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                const SizedBox(width: 8),
                _buildTimelineZoomControls(),
              ],
            ),
          ),
          
          // Clips timeline
          Expanded(
            child: SingleChildScrollView(
              controller: _timelineScrollController,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ..._clips.asMap().entries.map((entry) => 
                    _buildTimelineClip(entry.key, entry.value)),
                  _buildAddClipButton(),
                ],
              ),
            ),
          ),
          
          // Audio tracks
          if (_audioTracks.isNotEmpty)
            Container(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _audioTracks.length,
                itemBuilder: (context, index) => _buildAudioTrackItem(index),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTimelineZoomControls() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.zoom_out, color: Colors.white, size: 20),
          onPressed: () => setState(() => 
            _timelineZoom = (_timelineZoom / 1.5).clamp(0.5, 5.0)),
        ),
        IconButton(
          icon: const Icon(Icons.zoom_in, color: Colors.white, size: 20),
          onPressed: () => setState(() => 
            _timelineZoom = (_timelineZoom * 1.5).clamp(0.5, 5.0)),
        ),
      ],
    );
  }

  Widget _buildTimelineClip(int index, VideoClip clip) {
    double clipWidth = 120 * _timelineZoom;
    bool isSelected = index == _currentClipIndex;
    
    return Container(
      width: clipWidth,
      margin: const EdgeInsets.all(2),
      child: Stack(
        children: [
          // Main clip container
          GestureDetector(
            onTap: () => _selectClip(index),
            onLongPress: () => _showClipContextMenu(index),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: isSelected ? Colors.blue : Colors.grey[600]!,
                  width: isSelected ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  color: Colors.grey[800],
                  child: Column(
                    children: [
                      // Thumbnail area
                      Expanded(
                        child: Stack(
                          children: [
                            Container(
                              width: double.infinity,
                              color: Colors.grey[700],
                              child: const Icon(Icons.videocam, color: Colors.white, size: 24),
                            ),
                            
                            // Trim indicators
                            if (clip.trimStart > 0)
                              Positioned(
                                left: 0,
                                top: 0,
                                bottom: 0,
                                child: Container(
                                  width: clipWidth * clip.trimStart,
                                  color: Colors.black.withOpacity(0.7),
                                  child: const Icon(Icons.content_cut, color: Colors.red, size: 16),
                                ),
                              ),
                            if (clip.trimEnd < 1.0)
                              Positioned(
                                right: 0,
                                top: 0,
                                bottom: 0,
                                child: Container(
                                  width: clipWidth * (1.0 - clip.trimEnd),
                                  color: Colors.black.withOpacity(0.7),
                                  child: const Icon(Icons.content_cut, color: Colors.red, size: 16),
                                ),
                              ),
                            
                            // Effects indicators
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if (clip.speed != 1.0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.orange,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '${clip.speed}x',
                                        style: const TextStyle(color: Colors.white, fontSize: 8),
                                      ),
                                    ),
                                  if (clip.filter != 'None')
                                    Container(
                                      margin: const EdgeInsets.only(top: 2),
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.purple,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Icon(Icons.filter, color: Colors.white, size: 8),
                                    ),
                                ],
                              ),
                            ),
                            
                            // Processing indicator
                            if (clip.needsReprocessing)
                              const Positioned(
                                top: 4,
                                left: 4,
                                child: Icon(Icons.sync, color: Colors.blue, size: 12),
                              ),
                          ],
                        ),
                      ),
                      
                      // Clip info
                      Container(
                        padding: const EdgeInsets.all(4),
                        child: Column(
                          children: [
                            Text(
                              'Clip ${index + 1}',
                              style: const TextStyle(color: Colors.white, fontSize: 10),
                            ),
                            if (clip.duration != null)
                              Text(
                                _formatDuration(clip.getEffectiveDuration().toInt()),
                                style: const TextStyle(color: Colors.grey, fontSize: 8),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          // Trim handles
          _buildTrimHandle(clip, clipWidth, true), // Left handle
          _buildTrimHandle(clip, clipWidth, false), // Right handle
        ],
      ),
    );
  }

  Widget _buildTrimHandle(VideoClip clip, double clipWidth, bool isLeft) {
    return Positioned(
      left: isLeft ? 0 : null,
      right: isLeft ? null : 0,
      top: 0,
      bottom: 20,
      child: GestureDetector(
        onPanUpdate: (details) {
          double delta = details.delta.dx / clipWidth;
          setState(() {
            if (isLeft) {
              clip.trimStart = (clip.trimStart + delta).clamp(0.0, clip.trimEnd - 0.05);
            } else {
              clip.trimEnd = (clip.trimEnd + delta).clamp(clip.trimStart + 0.05, 1.0);
            }
            clip.markForReprocessing();
            _calculateTotalDuration();
          });
        },
        onPanEnd: (details) => _processClip(clip),
        child: Container(
          width: 8,
          decoration: BoxDecoration(
            color: Colors.yellow,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Center(
            child: Icon(Icons.drag_handle, color: Colors.black, size: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildAddClipButton() {
    return Container(
      width: 80,
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[600]!, style: BorderStyle.solid),
        borderRadius: BorderRadius.circular(8),
      ),
      child: GestureDetector(
        onTap: _showAddMediaOptions,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, color: Colors.white, size: 32),
            Text('Add', style: TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioTrackItem(int index) {
    final audio = _audioTracks[index];
    return Container(
      width: 100,
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.green[800],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          const Icon(Icons.audiotrack, color: Colors.white, size: 16),
          Expanded(
            child: Text(
              'Audio ${index + 1}',
              style: const TextStyle(color: Colors.white, fontSize: 10),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _audioTracks.removeAt(index)),
            child: const Icon(Icons.close, color: Colors.white, size: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return AnimatedBuilder(
      animation: _toolbarAnimController,
      builder: (context, child) {
        return Container(
          height: 160 * _toolbarAnimController.value,
          color: Colors.black,
          child: child,
        );
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            // Primary tools
            Container(
              height: 80,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildToolButton('Trim', Icons.content_cut, () => _showTrimOptions()),
                    _buildToolButton('Split', Icons.call_split, () => _splitClip()),
                    _buildToolButton('Speed', Icons.speed, () => _showSpeedOptions()),
                    _buildToolButton('Filter', Icons.filter, () => _showFilterOptions()),
                    _buildToolButton('Crop', Icons.crop, () => _showCropOptions()),
                    _buildToolButton('Text', Icons.text_fields, () => _addTextOverlay()),
                    _buildToolButton('Sticker', Icons.emoji_emotions, () => _showStickerOptions()),
                    _buildToolButton('Audio', Icons.music_note, () => _showAudioOptions()),
                    _buildToolButton('Color', Icons.palette, () => _showColorOptions()),
                    _buildToolButton('Transform', Icons.transform, () => _showTransformOptions()),
                  ],
                ),
              ),
            ),
            
            // Secondary tools
            Container(
              height: 60,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildSmallToolButton('Duplicate', Icons.copy, () => _duplicateClip()),
                    _buildSmallToolButton('Delete', Icons.delete, () => _deleteCurrentClip()),
                    _buildSmallToolButton('Rotate', Icons.rotate_right, () => _rotateClip(90)),
                    _buildSmallToolButton('Flip H', Icons.flip, () => _flipClip(true)),
                    _buildSmallToolButton('Flip V', Icons.flip, () => _flipClip(false)),
                    _buildSmallToolButton('Undo', Icons.undo, () => _showSnackBar('Undo coming soon')),
                    _buildSmallToolButton('Redo', Icons.redo, () => _showSnackBar('Redo coming soon')),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolButton(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 70,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[700]!),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 10),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallToolButton(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: Colors.white, size: 16),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 8),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // Tool methods
  void _showTrimOptions() {
    if (_clips.isEmpty) return;
    
    final clip = _clips[_currentClipIndex];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Trim Video',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              
              Row(
                children: [
                  const Text('Start: ', style: TextStyle(color: Colors.white)),
                  Expanded(
                    child: Slider(
                      value: clip.trimStart,
                      onChanged: (value) {
                        if (value < clip.trimEnd - 0.05) {
                          setDialogState(() => clip.trimStart = value);
                          setState(() {
                            clip.markForReprocessing();
                            _calculateTotalDuration();
                          });
                        }
                      },
                      activeColor: Colors.blue,
                    ),
                  ),
                  Text(
                    '${(clip.trimStart * 100).toInt()}%',
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
              
              Row(
                children: [
                  const Text('End: ', style: TextStyle(color: Colors.white)),
                  Expanded(
                    child: Slider(
                      value: clip.trimEnd,
                      onChanged: (value) {
                        if (value > clip.trimStart + 0.05) {
                          setDialogState(() => clip.trimEnd = value);
                          setState(() {
                            clip.markForReprocessing();
                            _calculateTotalDuration();
                          });
                        }
                      },
                      activeColor: Colors.blue,
                    ),
                  ),
                  Text(
                    '${(clip.trimEnd * 100).toInt()}%',
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
              
              const SizedBox(height: 20),
              
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        setDialogState(() {
                          clip.trimStart = 0.0;
                          clip.trimEnd = 1.0;
                          clip.markForReprocessing();
                        });
                        setState(() => _calculateTotalDuration());
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[700],
                      ),
                      child: const Text('Reset'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _processClip(clip);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                      ),
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSpeedOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Speed Control',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0].map((speed) {
                bool isSelected = _clips.isNotEmpty && _clips[_currentClipIndex].speed == speed;
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    if (_clips.isNotEmpty) {
                      setState(() {
                        _clips[_currentClipIndex].speed = speed;
                        _clips[_currentClipIndex].markForReprocessing();
                        _calculateTotalDuration();
                      });
                      _processClip(_clips[_currentClipIndex]);
                      _showSnackBar('Speed set to ${speed}x');
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.blue : Colors.grey[700],
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Text(
                      '${speed}x',
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey[300],
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showFilterOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Filters',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            
            Container(
              height: 250,
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.2,
                ),
                itemCount: _availableFilters.length,
                itemBuilder: (context, index) {
                  final filter = _availableFilters[index];
                  bool isSelected = _clips.isNotEmpty && 
                    _clips[_currentClipIndex].filter == filter['name'];
                  
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      if (_clips.isNotEmpty) {
                        setState(() {
                          _clips[_currentClipIndex].filter = filter['name'];
                          _clips[_currentClipIndex].markForReprocessing();
                        });
                        _processClip(_clips[_currentClipIndex]);
                        _showSnackBar('Filter applied: ${filter['name']}');
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.blue : Colors.grey[700],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? Colors.blue : Colors.grey[600]!,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            filter['icon'],
                            color: Colors.white,
                            size: 24,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            filter['name'],
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCropOptions() {
    if (_clips.isEmpty) return;
    
    final clip = _clips[_currentClipIndex];
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Crop & Zoom', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSliderRow('Zoom', clip.zoom, 0.5, 3.0, (value) {
                  setDialogState(() => clip.zoom = value);
                  setState(() => clip.markForReprocessing());
                }),
                _buildSliderRow('Crop X', clip.cropX, 0.0, 0.5, (value) {
                  setDialogState(() => clip.cropX = value);
                  setState(() => clip.markForReprocessing());
                }),
                _buildSliderRow('Crop Y', clip.cropY, 0.0, 0.5, (value) {
                  setDialogState(() => clip.cropY = value);
                  setState(() => clip.markForReprocessing());
                }),
                _buildSliderRow('Width', clip.cropWidth, 0.5, 1.0, (value) {
                  setDialogState(() => clip.cropWidth = value);
                  setState(() => clip.markForReprocessing());
                }),
                _buildSliderRow('Height', clip.cropHeight, 0.5, 1.0, (value) {
                  setDialogState(() => clip.cropHeight = value);
                  setState(() => clip.markForReprocessing());
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setDialogState(() {
                  clip.cropX = 0.0;
                  clip.cropY = 0.0;
                  clip.cropWidth = 1.0;
                  clip.cropHeight = 1.0;
                  clip.zoom = 1.0;
                  clip.markForReprocessing();
                });
                setState(() {});
              },
              child: const Text('Reset', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _processClip(clip);
              },
              child: const Text('Apply', style: TextStyle(color: Colors.blue)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliderRow(String label, double value, double min, double max, Function(double) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text('$label:', style: const TextStyle(color: Colors.white)),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
              activeColor: Colors.blue,
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              value.toStringAsFixed(1),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showColorOptions() {
    if (_clips.isEmpty) return;
    
    final clip = _clips[_currentClipIndex];
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Color Adjustments', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSliderRow('Brightness', clip.brightness, -0.5, 0.5, (value) {
                  setDialogState(() => clip.brightness = value);
                  setState(() => clip.markForReprocessing());
                }),
                _buildSliderRow('Contrast', clip.contrast, 0.5, 2.0, (value) {
                  setDialogState(() => clip.contrast = value);
                  setState(() => clip.markForReprocessing());
                }),
                _buildSliderRow('Saturation', clip.saturation, 0.0, 2.0, (value) {
                  setDialogState(() => clip.saturation = value);
                  setState(() => clip.markForReprocessing());
                }),
                _buildSliderRow('Hue', clip.hue, -180, 180, (value) {
                  setDialogState(() => clip.hue = value);
                  setState(() => clip.markForReprocessing());
                }),
                _buildSliderRow('Opacity', clip.opacity, 0.0, 1.0, (value) {
                  setDialogState(() => clip.opacity = value);
                  setState(() => clip.markForReprocessing());
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setDialogState(() {
                  clip.brightness = 0.0;
                  clip.contrast = 1.0;
                  clip.saturation = 1.0;
                  clip.hue = 0.0;
                  clip.opacity = 1.0;
                  clip.markForReprocessing();
                });
                setState(() {});
              },
              child: const Text('Reset', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _processClip(clip);
              },
              child: const Text('Apply', style: TextStyle(color: Colors.blue)),
            ),
          ],
        ),
      ),
    );
  }

  void _showTransformOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Transform',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildTransformButton('Rotate 90°', Icons.rotate_right, () {
                  Navigator.pop(context);
                  _rotateClip(90);
                }),
                _buildTransformButton('Rotate -90°', Icons.rotate_left, () {
                  Navigator.pop(context);
                  _rotateClip(-90);
                }),
                _buildTransformButton('Flip H', Icons.flip, () {
                  Navigator.pop(context);
                  _flipClip(true);
                }),
                _buildTransformButton('Flip V', Icons.flip, () {
                  Navigator.pop(context);
                  _flipClip(false);
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransformButton(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }

  void _addTextOverlay() {
    final overlay = TextOverlay(
      id: 'text_${DateTime.now().millisecondsSinceEpoch}',
      text: 'Add Text',
      x: 100,
      y: 100,
    );
    
    setState(() => _textOverlays.add(overlay));
    _editTextOverlay(overlay);
  }

  void _editTextOverlay(TextOverlay overlay) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Edit Text', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Text',
                    labelStyle: TextStyle(color: Colors.grey),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.blue),
                    ),
                  ),
                  controller: TextEditingController(text: overlay.text),
                  onChanged: (value) {
                    overlay.text = value;
                    setState(() {});
                  },
                ),
                
                const SizedBox(height: 16),
                
                _buildSliderRow('Size', overlay.fontSize, 12, 72, (value) {
                  setDialogState(() => overlay.fontSize = value);
                  setState(() {});
                }),
                
                _buildSliderRow('Rotation', overlay.rotation, 0, 360, (value) {
                  setDialogState(() => overlay.rotation = value);
                  setState(() {});
                }),
                
                const SizedBox(height: 16),
                
                // Color picker
                const Text('Color:', style: TextStyle(color: Colors.white)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [Colors.white, Colors.black, Colors.red, Colors.blue, 
                           Colors.green, Colors.yellow, Colors.purple, Colors.orange]
                    .map((color) => GestureDetector(
                      onTap: () {
                        setDialogState(() => overlay.color = color);
                        setState(() {});
                      },
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: color,
                          border: Border.all(
                            color: overlay.color == color ? Colors.blue : Colors.transparent,
                            width: 3,
                          ),
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                    )).toList(),
                ),
                
                const SizedBox(height: 16),
                
                // Style options
                Row(
                  children: [
                    Expanded(
                      child: CheckboxListTile(
                        title: const Text('Bold', style: TextStyle(color: Colors.white, fontSize: 12)),
                        value: overlay.fontWeight == FontWeight.bold,
                        onChanged: (value) {
                          setDialogState(() {
                            overlay.fontWeight = value! ? FontWeight.bold : FontWeight.normal;
                          });
                          setState(() {});
                        },
                        activeColor: Colors.blue,
                      ),
                    ),
                    Expanded(
                      child: CheckboxListTile(
                        title: const Text('Italic', style: TextStyle(color: Colors.white, fontSize: 12)),
                        value: overlay.isItalic,
                        onChanged: (value) {
                          setDialogState(() => overlay.isItalic = value!);
                          setState(() {});
                        },
                        activeColor: Colors.blue,
                      ),
                    ),
                  ],
                ),
                
                CheckboxListTile(
                  title: const Text('Stroke/Outline', style: TextStyle(color: Colors.white)),
                  value: overlay.hasStroke,
                  onChanged: (value) {
                    setDialogState(() => overlay.hasStroke = value!);
                    setState(() {});
                  },
                  activeColor: Colors.blue,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() => _textOverlays.remove(overlay));
                Navigator.pop(context);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done', style: TextStyle(color: Colors.blue)),
            ),
          ],
        ),
      ),
    );
  }

  void _showStickerOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Choose Sticker',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            
            Container(
              height: 300,
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: _availableStickers.length,
                itemBuilder: (context, index) {
                  final sticker = _availableStickers[index];
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      _addSticker(sticker);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[600]!),
                      ),
                      child: Center(
                        child: Text(sticker, style: const TextStyle(fontSize: 32)),
                      ),
                    ),
                  );
                },
              ),
            ),
            
            const SizedBox(height: 16),
            
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                final picker = ImagePicker();
                final image = await picker.pickImage(source: ImageSource.gallery);
                if (image != null) {
                  // Use image path as sticker content for now
                  _addSticker('📷'); // Placeholder - in real app, you'd handle image stickers
                }
              },
              icon: const Icon(Icons.image),
              label: const Text('Custom Image'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addSticker(String content) {
    setState(() {
      _stickerOverlays.add(StickerOverlay(
        id: 'sticker_${DateTime.now().millisecondsSinceEpoch}',
        content: content,
        x: 150,
        y: 150,
      ));
    });
  }

  void _editStickerOverlay(StickerOverlay overlay) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Edit Sticker', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSliderRow('Scale', overlay.scale, 0.5, 3.0, (value) {
                setDialogState(() => overlay.scale = value);
                setState(() {});
              }),
              _buildSliderRow('Rotation', overlay.rotation, 0, 360, (value) {
                setDialogState(() => overlay.rotation = value);
                setState(() {});
              }),
              _buildSliderRow('Opacity', overlay.opacity, 0.0, 1.0, (value) {
                setDialogState(() => overlay.opacity = value);
                setState(() {});
              }),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() => _stickerOverlays.remove(overlay));
                Navigator.pop(context);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done', style: TextStyle(color: Colors.blue)),
            ),
          ],
        ),
      ),
    );
  }

  void _showAudioOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Audio Options',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            
            ListTile(
              leading: const Icon(Icons.library_music, color: Colors.white),
              title: const Text('Add Music', style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(context);
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.audio,
                );
                if (result != null && result.files.first.path != null) {
                  _audioTracks.add(AudioTrack(
                    id: 'audio_${DateTime.now().millisecondsSinceEpoch}',
                    file: File(result.files.first.path!),
                  ));
                  setState(() {});
                  _showSnackBar('Audio track added');
                }
              },
            ),
            
            ListTile(
              leading: Icon(
                _isRecordingAudio ? Icons.stop : Icons.mic,
                color: _isRecordingAudio ? Colors.red : Colors.white,
              ),
              title: Text(
                _isRecordingAudio ? 'Stop Recording' : 'Record Voiceover',
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _toggleAudioRecording();
              },
            ),
            
            if (_audioTracks.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.volume_up, color: Colors.white),
                title: const Text('Audio Settings', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _showAudioSettings();
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showAudioSettings() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Audio Settings', style: TextStyle(color: Colors.white)),
          content: Container(
            height: 400,
            width: double.maxFinite,
            child: ListView.builder(
              itemCount: _audioTracks.length,
              itemBuilder: (context, index) {
                final audio = _audioTracks[index];
                return Card(
                  color: Colors.grey[800],
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.audiotrack, color: Colors.white),
                            const SizedBox(width: 8),
                            Text('Audio ${index + 1}', style: const TextStyle(color: Colors.white)),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                setDialogState(() => _audioTracks.removeAt(index));
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                        
                        _buildSliderRow('Volume', audio.volume, 0.0, 2.0, (value) {
                          setDialogState(() => audio.volume = value);
                        }),
                        
                        Row(
                          children: [
                            const Text('Mute: ', style: TextStyle(color: Colors.white)),
                            Switch(
                              value: audio.isMuted,
                              onChanged: (value) {
                                setDialogState(() => audio.isMuted = value);
                              },
                              activeColor: Colors.blue,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done', style: TextStyle(color: Colors.blue)),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddMediaOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Add Media',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            
            ListTile(
              leading: const Icon(Icons.videocam, color: Colors.white),
              title: const Text('Record Video', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _recordVideo();
              },
            ),
            
            ListTile(
              leading: const Icon(Icons.video_library, color: Colors.white),
              title: const Text('Import Video', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _importVideo();
              },
            ),
            
            ListTile(
              leading: const Icon(Icons.image, color: Colors.white),
              title: const Text('Import Image', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _importImage();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showClipContextMenu(int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Clip ${index + 1} Options', 
                 style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            
            ListTile(
              leading: const Icon(Icons.call_split, color: Colors.white),
              title: const Text('Split Clip', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                setState(() => _currentClipIndex = index);
                _splitClip();
              },
            ),
            
            ListTile(
              leading: const Icon(Icons.copy, color: Colors.white),
              title: const Text('Duplicate', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _duplicateClipAtIndex(index);
              },
            ),
            
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.white),
              title: const Text('Delete', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _deleteClipAtIndex(index);
              },
            ),
            
            ListTile(
              leading: const Icon(Icons.tune, color: Colors.white),
              title: const Text('Adjust', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                setState(() => _currentClipIndex = index);
                _showColorOptions();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showExportDialog() {
    showDialog(
      context: context,
      barrierDismissible: !_isExporting,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Export Video', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                    if (!_isExporting)
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                  ],
                ),
                
                const SizedBox(height: 20),
                
                // Export settings
                if (!_isExporting) ...[
                  _buildExportSetting('Resolution', _exportResolution, 
                    ['480p', '720p', '1080p', '4K'], (value) {
                    setDialogState(() => _exportResolution = value);
                  }),
                  
                  _buildExportSetting('Frame Rate', '${_exportFrameRate}fps', 
                    ['24fps', '30fps', '60fps'], (value) {
                    setDialogState(() => _exportFrameRate = int.parse(value.replaceAll('fps', '')));
                  }),
                  
                  _buildExportSetting('Format', _exportFormat.toUpperCase(), 
                    ['MP4', 'MOV'], (value) {
                    setDialogState(() => _exportFormat = value.toLowerCase());
                  }),
                  
                  SwitchListTile(
                    title: const Text('Add Watermark', style: TextStyle(color: Colors.white)),
                    value: _addWatermark,
                    onChanged: (value) => setDialogState(() => _addWatermark = value),
                    activeColor: Colors.blue,
                  ),
                  
                  if (_addWatermark)
                    TextField(
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Watermark Text',
                        labelStyle: TextStyle(color: Colors.grey),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.blue)),
                      ),
                      onChanged: (value) => _watermarkText = value,
                    ),
                  
                  const SizedBox(height: 20),
                  
                  Text(
                    'Estimated Size: ${_calculateEstimatedSize()}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
                
                if (_isExporting) ...[
                  Column(
                    children: [
                      CircularProgressIndicator(
                        value: _exportProgress,
                        backgroundColor: Colors.grey[700],
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '${(_exportProgress * 100).toInt()}%',
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(_currentStep, style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                ],
                
                const SizedBox(height: 20),
                
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isExporting ? null : () => _exportVideo(setDialogState),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(_isExporting ? 'EXPORTING...' : 'SAVE TO GALLERY'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExportSetting(String title, String value, List<String> options, Function(String) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, color: Colors.white)),
          DropdownButton<String>(
            value: value,
            dropdownColor: Colors.grey[800],
            style: const TextStyle(color: Colors.white),
            onChanged: (newValue) => onChanged(newValue!),
            items: options.map((option) => DropdownMenuItem(
              value: option,
              child: Text(option),
            )).toList(),
          ),
        ],
      ),
    );
  }

  void _showExitDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Are you sure?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'If you leave without saving, your project will be lost.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('I\'m sure', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // Core functionality methods
  void _togglePlayPause() {
    if (_previewController?.value.isInitialized == true) {
      if (_isPlaying) {
        _previewController!.pause();
      } else {
        _previewController!.play();
      }
    }
  }

  void _seekToPosition(double value) {
    if (_previewController?.value.isInitialized == true) {
      final position = Duration(
        milliseconds: (value * _previewController!.value.duration.inMilliseconds).toInt(),
      );
      _previewController!.seekTo(position);
    }
  }

  void _selectClip(int index) {
    if (index < _clips.length) {
      setState(() {
        _currentClipIndex = index;
        _previewController?.removeListener(_videoListener);
        _previewController = _clips[index].previewController;
        _previewController?.addListener(_videoListener);
      });
    }
  }

  void _splitClip() {
    if (_clips.isEmpty || _previewController == null) return;

    final currentClip = _clips[_currentClipIndex];
    final position = _previewController!.value.position.inMilliseconds.toDouble();
    final clipDuration = currentClip.duration!.inMilliseconds.toDouble();
    
    double splitPoint = position / clipDuration;
    splitPoint = splitPoint.clamp(currentClip.trimStart + 0.05, currentClip.trimEnd - 0.05);
    
    // Create new clip for second part
    final newClip = VideoClip(
      id: 'clip_${DateTime.now().millisecondsSinceEpoch}',
      file: currentClip.file,
    );
    
    // Initialize controllers
    newClip.controller = VideoPlayerController.file(currentClip.file);
    newClip.previewController = VideoPlayerController.file(currentClip.file);
    
    // Copy properties
    newClip.trimStart = splitPoint;
    newClip.trimEnd = currentClip.trimEnd;
    newClip.speed = currentClip.speed;
    newClip.zoom = currentClip.zoom;
    newClip.cropX = currentClip.cropX;
    newClip.cropY = currentClip.cropY;
    newClip.cropWidth = currentClip.cropWidth;
    newClip.cropHeight = currentClip.cropHeight;
    newClip.rotation = currentClip.rotation;
    newClip.flipHorizontal = currentClip.flipHorizontal;
    newClip.flipVertical = currentClip.flipVertical;
    newClip.filter = currentClip.filter;
    newClip.brightness = currentClip.brightness;
    newClip.contrast = currentClip.contrast;
    newClip.saturation = currentClip.saturation;
    newClip.hue = currentClip.hue;
    newClip.opacity = currentClip.opacity;
    newClip.duration = currentClip.duration;
    newClip.markForReprocessing();
    
    // Update original clip
    currentClip.trimEnd = splitPoint;
    currentClip.markForReprocessing();
    
    // Insert new clip
    setState(() {
      _clips.insert(_currentClipIndex + 1, newClip);
      _calculateTotalDuration();
    });
    
    // Process clips
    _processClip(currentClip);
    _processClip(newClip);
    
    _showSnackBar('Clip split successfully');
  }

  void _duplicateClip() {
    _duplicateClipAtIndex(_currentClipIndex);
  }

  void _duplicateClipAtIndex(int index) {
    if (index < _clips.length) {
      final currentClip = _clips[index];
      final newClip = VideoClip(
        id: 'clip_${DateTime.now().millisecondsSinceEpoch}',
        file: currentClip.file,
      );
      
      // Copy all properties
      newClip.controller = VideoPlayerController.file(currentClip.file);
      newClip.previewController = VideoPlayerController.file(currentClip.file);
      newClip.trimStart = currentClip.trimStart;
      newClip.trimEnd = currentClip.trimEnd;
      newClip.speed = currentClip.speed;
      newClip.zoom = currentClip.zoom;
      newClip.cropX = currentClip.cropX;
      newClip.cropY = currentClip.cropY;
      newClip.cropWidth = currentClip.cropWidth;
      newClip.cropHeight = currentClip.cropHeight;
      newClip.rotation = currentClip.rotation;
      newClip.flipHorizontal = currentClip.flipHorizontal;
      newClip.flipVertical = currentClip.flipVertical;
      newClip.filter = currentClip.filter;
      newClip.brightness = currentClip.brightness;
      newClip.contrast = currentClip.contrast;
      newClip.saturation = currentClip.saturation;
      newClip.hue = currentClip.hue;
      newClip.opacity = currentClip.opacity;
      newClip.duration = currentClip.duration;
      newClip.markForReprocessing();
      
      setState(() {
        _clips.insert(index + 1, newClip);
        _calculateTotalDuration();
      });
      
      if (currentClip.processedFile != null || currentClip.needsReprocessing) {
        _processClip(newClip);
      }
      
      _showSnackBar('Clip duplicated');
    }
  }

  void _deleteCurrentClip() {
    _deleteClipAtIndex(_currentClipIndex);
  }

  void _deleteClipAtIndex(int index) {
    if (_clips.length > 1 && index < _clips.length) {
      setState(() {
        _clips[index].dispose();
        _clips.removeAt(index);
        if (_currentClipIndex >= _clips.length) {
          _currentClipIndex = _clips.length - 1;
        }
        if (_clips.isNotEmpty) {
          _previewController?.removeListener(_videoListener);
          _previewController = _clips[_currentClipIndex].previewController;
          _previewController?.addListener(_videoListener);
        }
        _calculateTotalDuration();
      });
      _showSnackBar('Clip deleted');
    } else {
      _showSnackBar('Cannot delete the last clip');
    }
  }

  void _rotateClip(double degrees) {
    if (_clips.isNotEmpty) {
      setState(() {
        _clips[_currentClipIndex].rotation += degrees;
        _clips[_currentClipIndex].rotation %= 360;
        _clips[_currentClipIndex].markForReprocessing();
      });
      _processClip(_clips[_currentClipIndex]);
      _showSnackBar('Clip rotated ${degrees.toInt()}°');
    }
  }

  void _flipClip(bool horizontal) {
    if (_clips.isNotEmpty) {
      setState(() {
        if (horizontal) {
          _clips[_currentClipIndex].flipHorizontal = !_clips[_currentClipIndex].flipHorizontal;
        } else {
          _clips[_currentClipIndex].flipVertical = !_clips[_currentClipIndex].flipVertical;
        }
        _clips[_currentClipIndex].markForReprocessing();
      });
      _processClip(_clips[_currentClipIndex]);
      _showSnackBar('Clip flipped ${horizontal ? 'horizontally' : 'vertically'}');
    }
  }

  Future<void> _toggleAudioRecording() async {
    if (_isRecordingAudio) {
      // Stop recording
      String? path = await _recorder!.stopRecorder();
      if (path != null) {
        _audioTracks.add(AudioTrack(
          id: 'audio_${DateTime.now().millisecondsSinceEpoch}',
          file: File(path),
        ));
        _showSnackBar('Audio recorded successfully');
      }
      setState(() => _isRecordingAudio = false);
    } else {
      // Start recording
      final permission = await Permission.microphone.request();
      if (permission.isGranted) {
        final tempDir = await getTemporaryDirectory();
        String path = '${tempDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.aac';
        
        await _recorder!.startRecorder(
          toFile: path,
          codec: Codec.aacADTS,
        );
        setState(() => _isRecordingAudio = true);
        _showSnackBar('Recording started...');
      } else {
        _showSnackBar('Microphone permission required');
      }
    }
  }

  Future<void> _recordVideo() async {
    final picker = ImagePicker();
    final video = await picker.pickVideo(source: ImageSource.camera);
    if (video != null) {
      await _addVideoClip(File(video.path));
      _showSnackBar('Video recorded and added');
    }
  }

  Future<void> _importVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );
    
    if (result != null && result.files.first.path != null) {
      await _addVideoClip(File(result.files.first.path!));
      _showSnackBar('Video imported and added');
    }
  }

  Future<void> _importImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      // Convert image to video using FFmpeg
      final tempDir = await getTemporaryDirectory();
      final outputPath = '${tempDir.path}/image_video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      
      final command = '-loop 1 -i "${image.path}" -c:v libx264 -t 5 -pix_fmt yuv420p -vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2" "$outputPath"';
      
      await FFmpegKit.execute(command);
      await _addVideoClip(File(outputPath));
      _showSnackBar('Image converted to video and added');
    }
  }

  Future<void> _addVideoClip(File file) async {
    final clip = VideoClip(
      id: 'clip_${DateTime.now().millisecondsSinceEpoch}',
      file: file,
    );
    
    try {
      clip.controller = VideoPlayerController.file(file);
      await clip.controller!.initialize();
      clip.duration = clip.controller!.value.duration;
      
      clip.previewController = VideoPlayerController.file(file);
      await clip.previewController!.initialize();
      
      setState(() {
        _clips.add(clip);
        _calculateTotalDuration();
      });
    } catch (e) {
      debugPrint('Error adding video clip: $e');
      _showSnackBar('Error adding video: $e');
    }
  }

  Future<void> _exportVideo(Function setDialogState) async {
    setState(() => _isExporting = true);
    setDialogState(() {
      _isExporting = true;
      _exportProgress = 0.0;
      _currentStep = 'Preparing export...';
    });

    try {
      // Request storage permission
      final permission = await Permission.storage.request();
      if (!permission.isGranted) {
        throw Exception('Storage permission required');
      }

      // Process all clips first
      setDialogState(() => _currentStep = 'Processing clips...');
      for (int i = 0; i < _clips.length; i++) {
        if (_clips[i].needsReprocessing) {
          setDialogState(() => _currentStep = 'Processing clip ${i + 1}/${_clips.length}...');
          await _processClip(_clips[i]);
        }
        setDialogState(() => _exportProgress = (i + 1) / (_clips.length + 1) * 0.5);
      }

      final outputDir = await getExternalStorageDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${outputDir!.path}/VideoEditor_${timestamp}.${_exportFormat}';
      
      setDialogState(() => _currentStep = 'Building final video...');
      String command = await _buildExportCommand(outputPath);
      
      setDialogState(() => _currentStep = 'Exporting final video...');
      
      await FFmpegKit.executeAsync(command, (session) async {
        final returnCode = await session.getReturnCode();
        
        setState(() => _isExporting = false);
        Navigator.pop(context);
        
        if (ReturnCode.isSuccess(returnCode)) {
          _showSuccessDialog(outputPath);
        } else {
          final logs = await session.getLogs();
          String errorMsg = 'Export failed.';
          if (logs.isNotEmpty) {
            errorMsg += ' ${logs.last.getMessage()}';
          }
          _showErrorDialog(errorMsg);
        }
      }, (log) {
        debugPrint('FFmpeg Log: ${log.getMessage()}');
      }, (statistics) {
        if (statistics.getTime() > 0) {
          double progress = 0.5 + (statistics.getTime() / (_totalDuration * 1000)) * 0.5;
          setDialogState(() => _exportProgress = progress.clamp(0.0, 1.0));
        }
      });
      
    } catch (e) {
      setState(() => _isExporting = false);
      Navigator.pop(context);
      _showErrorDialog('Export failed: $e');
    }
  }

  Future<String> _buildExportCommand(String outputPath) async {
    List<String> inputs = [];
    List<String> filters = [];
    
    // Add processed video inputs
    for (int i = 0; i < _clips.length; i++) {
      String inputPath = _clips[i].processedFile?.path ?? _clips[i].file.path;
      inputs.add('-i "$inputPath"');
    }
    
    // Add audio inputs
    for (int i = 0; i < _audioTracks.length; i++) {
      inputs.add('-i "${_audioTracks[i].file.path}"');
    }
    
    // Resolution settings
    String resolution = _exportResolution == '4K' ? '3840:2160' : 
                       _exportResolution == '1080p' ? '1920:1080' :
                       _exportResolution == '720p' ? '1280:720' : '854:480';
    
    // Scale each clip and prepare for concatenation
    for (int i = 0; i < _clips.length; i++) {
      filters.add('[$i:v]scale=$resolution:force_original_aspect_ratio=decrease,pad=$resolution:(ow-iw)/2:(oh-ih)/2[v$i];');
    }
    
    // Concatenate videos
    String concatFilter = '';
    for (int i = 0; i < _clips.length; i++) {
      concatFilter += '[v$i]';
    }
    concatFilter += 'concat=n=${_clips.length}:v=1:a=0[concated];';
    filters.add(concatFilter);
    
    // Add overlays
    String overlayFilter = '[concated]';
    
    // Add text overlays
    for (int i = 0; i < _textOverlays.length; i++) {
      final text = _textOverlays[i];
      String colorHex = text.color.value.toRadixString(16).substring(2);
      String fontweight = text.fontWeight == FontWeight.bold ? ':bold=1' : '';
      String italic = text.isItalic ? ':italic=1' : '';
      
      overlayFilter += "drawtext=text='${text.text.replaceAll("'", "\\'")}':x=${text.x}:y=${text.y}:fontsize=${text.fontSize}:fontcolor=0x$colorHex$fontweight$italic:enable='between(t,${text.startTime},${text.endTime})',";
    }
    
    // Add watermark
    if (_addWatermark && _watermarkText.isNotEmpty) {
      overlayFilter += "drawtext=text='$_watermarkText':x=w-tw-10:y=h-th-10:fontsize=16:fontcolor=white:alpha=0.7,";
    }
    
    if (overlayFilter.endsWith(',')) {
      overlayFilter = overlayFilter.substring(0, overlayFilter.length - 1);
    }
    overlayFilter += '[final]';
    filters.add(overlayFilter);
    
    // Build final command
    String audioMap = '';
    if (_audioTracks.isNotEmpty) {
      // Mix audio tracks
      String audioFilter = '';
      for (int i = 0; i < _audioTracks.length; i++) {
        int audioIndex = _clips.length + i;
        audioFilter += '[$audioIndex:a]';
      }
      if (_audioTracks.length > 1) {
        audioFilter += 'amix=inputs=${_audioTracks.length}[aout];';
        filters.add(audioFilter);
        audioMap = '-map "[aout]"';
      } else {
        audioMap = '-map ${_clips.length}:a';
      }
    }
    
    String fullCommand = '${inputs.join(' ')} -filter_complex "${filters.join('')}" -map "[final]" $audioMap -c:v libx264 -preset medium -crf 23 -b:v ${_exportBitrate}k -r $_exportFrameRate "$outputPath"';
    
    return fullCommand;
  }

  void _showSuccessDialog(String path) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Export Successful!', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 64),
            const SizedBox(height: 16),
            const Text('Video exported successfully!', style: TextStyle(color: Colors.white)),
            const SizedBox(height: 8),
            Text('Saved to: $path', style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Export Failed', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            Text(message, style: const TextStyle(color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  String _calculateEstimatedSize() {
    double totalDuration = _totalDuration / 1000; // Convert to seconds
    double sizeMultiplier = _exportResolution == '4K' ? 8.0 : 
                           _exportResolution == '1080p' ? 4.0 :
                           _exportResolution == '720p' ? 2.0 : 1.0;
    
    double estimatedMB = totalDuration * sizeMultiplier * (_exportBitrate / 1000);
    if (estimatedMB > 1024) {
      return '${(estimatedMB / 1024).toStringAsFixed(1)} GB';
    }
    return '${estimatedMB.toStringAsFixed(1)} MB';
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.grey[800],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  String _formatDuration(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

// Usage example:
class VideoEditorPage extends StatelessWidget {
  final List<File> files;
  
  const VideoEditorPage({super.key, required this.files});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Advanced Video Editor',
      theme: ThemeData.dark(),
      home: AdvancedVideoEditor(initialFiles: files),
      debugShowCheckedModeBanner: false,
    );
  }
}

// Helper function to launch the video editor
void launchVideoEditor(BuildContext context, List<File> videoFiles) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => AdvancedVideoEditor(initialFiles: videoFiles),
    ),
  );
}