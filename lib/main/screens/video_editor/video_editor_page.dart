import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

class VideoClip {
  final String id;
  final File file;
  VideoPlayerController? controller;
  double trimStart = 0.0;
  double trimEnd = 1.0;
  double speed = 1.0;
  double cropLeft = 0.0;
  double cropTop = 0.0;
  double cropRight = 0.0;
  double cropBottom = 0.0;
  double zoom = 1.0;
  
  VideoClip({required this.id, required this.file});
  
  void dispose() {
    controller?.dispose();
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
  
  TextOverlay({
    required this.id,
    required this.text,
    required this.x,
    required this.y,
    this.color = Colors.white,
    this.fontSize = 24,
    this.fontFamily = 'Arial',
    this.startTime = 0,
    this.endTime = 10,
  });
}

class StickerOverlay {
  String id;
  String assetPath;
  double x;
  double y;
  double scale;
  double startTime;
  double endTime;
  
  StickerOverlay({
    required this.id,
    required this.assetPath,
    required this.x,
    required this.y,
    this.scale = 1.0,
    this.startTime = 0,
    this.endTime = 10,
  });
}

class VideoEditorPage extends StatefulWidget {
  final List<File> files;
  
  const VideoEditorPage({super.key, required this.files});

  @override
  State<VideoEditorPage> createState() => _VideoEditorPageState();
}

class _VideoEditorPageState extends State<VideoEditorPage> with TickerProviderStateMixin {
  List<VideoClip> _clips = [];
  int _currentClipIndex = 0;
  VideoPlayerController? _previewController;
  
  List<TextOverlay> _textOverlays = [];
  List<StickerOverlay> _stickerOverlays = [];
  List<File> _audioFiles = [];
  
  bool _isExporting = false;
  double _exportProgress = 0.0;
  String _currentStep = '';
  
  // UI State
  bool _showTimeline = true;
  bool _isPlaying = false;
  double _currentPosition = 0.0;
  
  // Tools
  String _selectedTool = 'none';
  bool _isRecordingAudio = false;
  FlutterSoundRecorder? _recorder;
  
  // Export settings
  String _exportResolution = '1080p';
  int _exportFrameRate = 30;
  String _exportFormat = 'MOV';
  bool _autoHDR = true;
  
  final List<String> _availableStickers = [
    '😀', '😂', '🥰', '😎', '🤔', '👍', '❤️', '🔥', '⭐', '✨'
  ];

  @override
  void initState() {
    super.initState();
    _initializeClips();
    _initializeRecorder();
  }

  void _initializeRecorder() async {
    _recorder = FlutterSoundRecorder();
    await _recorder!.openRecorder();
  }

  void _initializeClips() async {
    for (int i = 0; i < widget.files.length; i++) {
      final clip = VideoClip(
        id: 'clip_$i',
        file: widget.files[i],
      );
      clip.controller = VideoPlayerController.file(widget.files[i]);
      await clip.controller!.initialize();
      _clips.add(clip);
    }
    
    if (_clips.isNotEmpty) {
      _previewController = _clips[0].controller;
      _previewController!.addListener(_videoListener);
    }
    
    setState(() {});
  }

  void _videoListener() {
    if (_previewController != null && _previewController!.value.isInitialized) {
      setState(() {
        _currentPosition = _previewController!.value.position.inMilliseconds.toDouble();
        _isPlaying = _previewController!.value.isPlaying;
      });
    }
  }

  @override
  void dispose() {
    _recorder?.closeRecorder();
    for (var clip in _clips) {
      clip.dispose();
    }
    super.dispose();
  }

  // Export Dialog - Similar to your reference image
  void _showExportDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Export', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                    IconButton(
                      onPressed: _isExporting ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                
                // Export Settings matching your UI
                _buildExportSetting('Resolution', _exportResolution, ['720p', '1080p', '4K'], (value) {
                  setDialogState(() => _exportResolution = value);
                }),
                _buildExportSetting('Frame rate', '${_exportFrameRate}fps', ['24fps', '30fps', '60fps'], (value) {
                  setDialogState(() => _exportFrameRate = int.parse(value.replaceAll('fps', '')));
                }),
                _buildExportSetting('Format', _exportFormat, ['MOV', 'MP4'], (value) {
                  setDialogState(() => _exportFormat = value);
                }),
                
                SwitchListTile(
                  title: const Text('Auto HDR', style: TextStyle(color: Colors.white)),
                  value: _autoHDR,
                  onChanged: (value) => setDialogState(() => _autoHDR = value),
                  activeColor: Colors.white,
                ),
                
                const SizedBox(height: 20),
                
                if (_isExporting) ...[
                  LinearProgressIndicator(
                    value: _exportProgress,
                    backgroundColor: Colors.grey[700],
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(_currentStep, style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 20),
                ],
                
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isExporting ? null : () => _exportVideo(setDialogState),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(_isExporting ? 'EXPORTING...' : 'SAVE'),
                  ),
                ),
                
                const SizedBox(height: 12),
                
                Text(
                  'Estimated Size: ${_calculateEstimatedSize()}',
                  style: const TextStyle(color: Colors.grey),
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

  String _calculateEstimatedSize() {
    double totalDuration = _clips.fold(0.0, (sum, clip) {
      if (clip.controller?.value.isInitialized == true) {
        final duration = clip.controller!.value.duration.inSeconds;
        return sum + (duration * (clip.trimEnd - clip.trimStart));
      }
      return sum;
    });
    
    double sizeMultiplier = _exportResolution == '4K' ? 4.0 : 
                           _exportResolution == '1080p' ? 2.0 : 1.0;
    
    double estimatedMB = totalDuration * sizeMultiplier * 2;
    return '${estimatedMB.toStringAsFixed(1)}MB';
  }

  Future<void> _exportVideo(Function setDialogState) async {
    setState(() => _isExporting = true);
    setDialogState(() {
      _isExporting = true;
      _exportProgress = 0.0;
      _currentStep = 'Preparing export...';
    });

    try {
      final outputDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${outputDir.path}/exported_video_$timestamp.${_exportFormat.toLowerCase()}';
      
      String command = await _buildExportCommand(outputPath, setDialogState);
      
      setDialogState(() => _currentStep = 'Processing video...');
      
      await FFmpegKit.executeAsync(command, (session) async {
        final returnCode = await session.getReturnCode();
        
        setState(() => _isExporting = false);
        
        if (ReturnCode.isSuccess(returnCode)) {
          Navigator.pop(context);
          _showSuccessDialog(outputPath);
        } else {
          Navigator.pop(context);
          _showErrorDialog('Export failed. Please try again.');
        }
      }, (log) {
        setDialogState(() => _exportProgress = min(_exportProgress + 0.01, 0.9));
      }, (statistics) {
        // Progress tracking
      });
      
    } catch (e) {
      setState(() => _isExporting = false);
      Navigator.pop(context);
      _showErrorDialog('Export failed: $e');
    }
  }

  Future<String> _buildExportCommand(String outputPath, Function setDialogState) async {
    List<String> inputs = [];
    List<String> filters = [];
    
    setDialogState(() => _currentStep = 'Building video timeline...');
    
    // Add video inputs
    for (int i = 0; i < _clips.length; i++) {
      inputs.add('-i "${_clips[i].file.path}"');
    }
    
    // Add audio inputs
    for (int i = 0; i < _audioFiles.length; i++) {
      inputs.add('-i "${_audioFiles[i].path}"');
    }
    
    // Build complex filter for concatenation and overlays
    String videoFilter = '';
    
    // Process each clip with trim, speed, crop, zoom
    for (int i = 0; i < _clips.length; i++) {
      final clip = _clips[i];
      String clipFilter = '[$i:v]';
      
      // Trim
      if (clip.trimStart > 0 || clip.trimEnd < 1.0) {
        final duration = clip.controller!.value.duration.inSeconds;
        final start = clip.trimStart * duration;
        final end = clip.trimEnd * duration;
        clipFilter += 'trim=start=$start:end=$end,setpts=PTS-STARTPTS,';
      }
      
      if (clip.speed != 1.0) {
        clipFilter += 'setpts=${1/clip.speed}*PTS,';
      }
      
      clipFilter += 'scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2[v$i];';
      filters.add(clipFilter);
    }
    
    // Concatenate videos
    String concatFilter = '';
    for (int i = 0; i < _clips.length; i++) {
      concatFilter += '[v$i]';
    }
    concatFilter += 'concat=n=${_clips.length}:v=1:a=0[outv];';
    filters.add(concatFilter);
    
    // Add text overlays
    setDialogState(() => _currentStep = 'Adding text overlays...');
    String overlayFilter = '[outv]';
    for (int i = 0; i < _textOverlays.length; i++) {
      final text = _textOverlays[i];
      overlayFilter += "drawtext=text='${text.text}':x=${text.x}:y=${text.y}:fontsize=${text.fontSize}:fontcolor=white:enable='between(t,${text.startTime},${text.endTime})',";
    }
    if (_textOverlays.isNotEmpty) {
      overlayFilter = overlayFilter.substring(0, overlayFilter.length - 1);
      filters.add('$overlayFilter[texted];');
    }
    
    // Add watermark
    final watermarkFilter = _textOverlays.isEmpty ? '[outv]' : '[texted]';
    filters.add("${watermarkFilter}drawtext=text='Made with VideoEditor':x=w-tw-10:y=h-th-10:fontsize=16:fontcolor=white:alpha=0.7[final]");
    
    String resolution = _exportResolution == '4K' ? '3840:2160' : 
                       _exportResolution == '1080p' ? '1920:1080' : '1280:720';
    
    String fullCommand = '${inputs.join(' ')} -filter_complex "${filters.join('')}" -map "[final]" -c:v libx264 -preset medium -crf 23 -s $resolution -r $_exportFrameRate "$outputPath"';
    
    return fullCommand;
  }

  void _showSuccessDialog(String path) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Export Successful', style: TextStyle(color: Colors.white)),
        content: Text('Video saved to: $path', style: const TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
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
        title: const Text('Export Failed', style: TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // Audio Recording
  Future<void> _recordAudio() async {
    if (_isRecordingAudio) {
      // Stop recording
      String? path = await _recorder!.stopRecorder();
      if (path != null) {
        _audioFiles.add(File(path));
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
      }
    }
  }

  // Tool Methods
  void _addTextOverlay() {
    setState(() {
      _textOverlays.add(TextOverlay(
        id: 'text_${DateTime.now().millisecondsSinceEpoch}',
        text: 'Sample Text',
        x: 100,
        y: 100,
      ));
    });
  }

  void _addSticker(String emoji) {
    setState(() {
      _stickerOverlays.add(StickerOverlay(
        id: 'sticker_${DateTime.now().millisecondsSinceEpoch}',
        assetPath: emoji,
        x: 150,
        y: 150,
      ));
    });
  }

  void _splitClip() {
    if (_clips.isNotEmpty && _previewController != null) {
      final currentClip = _clips[_currentClipIndex];
      final position = _previewController!.value.position.inMilliseconds.toDouble();
      final duration = _previewController!.value.duration.inMilliseconds.toDouble();
      final splitPoint = position / duration;
      
      final newClip = VideoClip(
        id: 'clip_${DateTime.now().millisecondsSinceEpoch}',
        file: currentClip.file,
      );
      newClip.controller = VideoPlayerController.file(currentClip.file);
      newClip.trimStart = splitPoint;
      newClip.trimEnd = currentClip.trimEnd;
      
      currentClip.trimEnd = splitPoint;
      
      _clips.insert(_currentClipIndex + 1, newClip);
      
      setState(() {});
    }
  }

  void _reorderClips(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final clip = _clips.removeAt(oldIndex);
      _clips.insert(newIndex, clip);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _buildAppBar(),
      body: _clips.isEmpty 
        ? const Center(child: CircularProgressIndicator(color: Colors.white))
        : Column(
            children: [
              Expanded(child: _buildPreviewArea()),
              if (_showTimeline) _buildTimeline(),
              _buildToolbar(),
            ],
          ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.black,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close, color: Colors.white),
        onPressed: () {
          if (_isRecordingAudio) {
            _recorder?.stopRecorder();
          }
          Navigator.pop(context);
        },
      ),
      title: const Text('Edit', style: TextStyle(color: Colors.white)),
      actions: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: ElevatedButton(
            onPressed: _showExportDialog,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey[800],
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('Export'),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewArea() {
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          Center(
            child: _previewController?.value.isInitialized == true
              ? AspectRatio(
                  aspectRatio: _previewController!.value.aspectRatio,
                  child: VideoPlayer(_previewController!),
                )
              : const CircularProgressIndicator(color: Colors.white),
          ),
          
          // Text Overlays
          ..._textOverlays.map((overlay) => Positioned(
            left: overlay.x,
            top: overlay.y,
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  overlay.x += details.delta.dx;
                  overlay.y += details.delta.dy;
                });
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  overlay.text,
                  style: TextStyle(
                    color: overlay.color,
                    fontSize: overlay.fontSize,
                  ),
                ),
              ),
            ),
          )),
          
          // Sticker Overlays
          ..._stickerOverlays.map((overlay) => Positioned(
            left: overlay.x,
            top: overlay.y,
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  overlay.x += details.delta.dx;
                  overlay.y += details.delta.dy;
                });
              },
              child: Transform.scale(
                scale: overlay.scale,
                child: Text(
                  overlay.assetPath,
                  style: const TextStyle(fontSize: 48),
                ),
              ),
            ),
          )),
          
          // Watermark
          Positioned(
            bottom: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Made with VideoEditor',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
          
          // Play/Pause button
          Center(
            child: GestureDetector(
              onTap: () {
                if (_previewController?.value.isPlaying == true) {
                  _previewController?.pause();
                } else {
                  _previewController?.play();
                }
              },
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(16),
                child: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    return Container(
      height: 120,
      color: Colors.grey[900],
      child: Column(
        children: [
          // Clip thumbnails
          Expanded(
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _clips.length,
              onReorder: _reorderClips,
              itemBuilder: (context, index) {
                final clip = _clips[index];
                return Container(
                  key: ValueKey(clip.id),
                  width: 80,
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: index == _currentClipIndex ? Colors.white : Colors.grey,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _currentClipIndex = index;
                        _previewController = clip.controller;
                        _previewController?.addListener(_videoListener);
                      });
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        color: Colors.grey[800],
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.videocam, color: Colors.white, size: 24),
                            Text(
                              '${index + 1}',
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          
          // Timeline scrubber
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  _formatDuration(_currentPosition.toInt()),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                Expanded(
                  child: Slider(
                    value: _previewController?.value.isInitialized == true
                      ? _currentPosition / _previewController!.value.duration.inMilliseconds
                      : 0.0,
                    onChanged: (value) {
                      if (_previewController?.value.isInitialized == true) {
                        final position = Duration(
                          milliseconds: (value * _previewController!.value.duration.inMilliseconds).toInt(),
                        );
                        _previewController?.seekTo(position);
                      }
                    },
                    activeColor: Colors.white,
                    inactiveColor: Colors.grey,
                  ),
                ),
                Text(
                  _previewController?.value.isInitialized == true
                    ? _formatDuration(_previewController!.value.duration.inMilliseconds)
                    : '0:00',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 120,
      color: Colors.black,
      child: Column(
        children: [
          // Primary tools
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildToolButton(Icons.music_note, 'Audio', () => _showAudioOptions()),
              _buildToolButton(Icons.text_fields, 'Text', _addTextOverlay),
              _buildToolButton(Icons.mic, 'Voice', _recordAudio),
              _buildToolButton(Icons.filter, 'Filter', () => _showFilterOptions()),
              _buildToolButton(Icons.timer, 'Timer', () => _showTimerOptions()),
              _buildToolButton(Icons.speed, 'Speed', () => _showSpeedOptions()),
              _buildToolButton(Icons.crop, 'Crop', () => _showCropOptions()),
              _buildToolButton(Icons.emoji_emotions, 'Sticker', () => _showStickerOptions()),
              _buildToolButton(Icons.delete, 'Remove', () => _removeCurrentClip()),
            ],
          ),
          
          // Secondary tools
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildSmallToolButton(Icons.cut, 'Split', _splitClip),
              _buildSmallToolButton(Icons.copy, 'Duplicate', () => _duplicateClip()),
              _buildSmallToolButton(Icons.flip, 'Flip', () => _flipClip()),
              _buildSmallToolButton(Icons.rotate_right, 'Rotate', () => _rotateClip()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToolButton(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildSmallToolButton(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 8)),
        ],
      ),
    );
  }

  // Tool option dialogs
  void _showAudioOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.library_music, color: Colors.white),
              title: const Text('Add Music', style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(context);
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.audio,
                );
                if (result != null) {
                  _audioFiles.add(File(result.files.first.path!));
                  setState(() {});
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
                _recordAudio();
              },
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
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Choose Sticker', style: TextStyle(color: Colors.white, fontSize: 18)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: _availableStickers.map((sticker) => GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  _addSticker(sticker);
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(sticker, style: const TextStyle(fontSize: 32)),
                ),
              )).toList(),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.image, color: Colors.white),
              title: const Text('Custom Image', style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(context);
                final picker = ImagePicker();
                final image = await picker.pickImage(source: ImageSource.gallery);
                if (image != null) {
                  _addSticker(image.path);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSpeedOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Speed Control', style: TextStyle(color: Colors.white, fontSize: 18)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [0.3, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0].map((speed) => 
                GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    if (_clips.isNotEmpty) {
                      setState(() {
                        _clips[_currentClipIndex].speed = speed;
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _clips.isNotEmpty && _clips[_currentClipIndex].speed == speed 
                        ? Colors.white : Colors.grey[700],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${speed}x',
                      style: TextStyle(
                        color: _clips.isNotEmpty && _clips[_currentClipIndex].speed == speed 
                          ? Colors.black : Colors.white,
                      ),
                    ),
                  ),
                ),
              ).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _showCropOptions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Crop Video', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Adjust crop area:', style: TextStyle(color: Colors.white)),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Zoom: ', style: TextStyle(color: Colors.white)),
                Expanded(
                  child: Slider(
                    value: _clips.isNotEmpty ? _clips[_currentClipIndex].zoom : 1.0,
                    min: 0.5,
                    max: 3.0,
                    onChanged: (value) {
                      if (_clips.isNotEmpty) {
                        setState(() => _clips[_currentClipIndex].zoom = value);
                      }
                    },
                    activeColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showFilterOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Filters', style: TextStyle(color: Colors.white, fontSize: 18)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: ['None', 'Vintage', 'B&W', 'Sepia', 'Bright', 'Contrast'].map((filter) => 
                GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    // Apply filter logic here
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey[700],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(filter, style: const TextStyle(color: Colors.white)),
                  ),
                ),
              ).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _showTimerOptions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Set Timer', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Start Time (seconds)',
                labelStyle: TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey),
                ),
              ),
              keyboardType: TextInputType.number,
            ),
            TextField(
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'End Time (seconds)',
                labelStyle: TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey),
                ),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Apply', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // Clip manipulation methods
  void _removeCurrentClip() {
    if (_clips.length > 1 && _currentClipIndex < _clips.length) {
      setState(() {
        _clips[_currentClipIndex].dispose();
        _clips.removeAt(_currentClipIndex);
        if (_currentClipIndex >= _clips.length) {
          _currentClipIndex = _clips.length - 1;
        }
        if (_clips.isNotEmpty) {
          _previewController = _clips[_currentClipIndex].controller;
          _previewController?.addListener(_videoListener);
        }
      });
    }
  }

  void _duplicateClip() {
    if (_clips.isNotEmpty) {
      final currentClip = _clips[_currentClipIndex];
      final newClip = VideoClip(
        id: 'clip_${DateTime.now().millisecondsSinceEpoch}',
        file: currentClip.file,
      );
      newClip.controller = VideoPlayerController.file(currentClip.file);
      newClip.trimStart = currentClip.trimStart;
      newClip.trimEnd = currentClip.trimEnd;
      newClip.speed = currentClip.speed;
      
      setState(() {
        _clips.insert(_currentClipIndex + 1, newClip);
      });
    }
  }

  void _flipClip() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Flip feature will be applied on export')),
    );
  }

  void _rotateClip() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Rotate feature will be applied on export')),
    );
  }

  String _formatDuration(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}