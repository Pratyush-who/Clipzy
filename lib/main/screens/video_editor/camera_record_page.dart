import 'dart:io';
import 'dart:async';
import 'dart:ui';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_ffmpeg_kit_full/ffmpeg_kit.dart';
import 'package:flutter_ffmpeg_kit_full/return_code.dart';

class CameraRecordPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  final Function(List<File>) onDone;

  const CameraRecordPage({
    super.key, 
    required this.cameras, 
    required this.onDone,
  });

  @override
  State<CameraRecordPage> createState() => _CameraRecordPageState();
}

class _CameraRecordPageState extends State<CameraRecordPage> with TickerProviderStateMixin {
  CameraController? _controller;
  bool _isRecording = false;
  bool _isInitialized = false;
  bool _isFlashOn = false;
  bool _isMuted = false;
  bool _isBeautyOn = false;
  int _currentCameraIndex = 0;
  int _selectedSpeed = 1; // 0: 0.5x, 1: 1x, 2: 2x
  int _selectedTimer = 0; // 0: off, 1: 3s, 2: 10s
  List<File> _recordedClips = [];
  List<String> _clipThumbnails = [];
  List<Uint8List?> _clipPreviews = [];
  bool _isProcessing = false;
  Timer? _recordingTimer;
  Timer? _countdownTimer;
  int _recordingSeconds = 0;
  int _countdownSeconds = 0;
  bool _isCountingDown = false;
  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 8.0;
  
  // Animation controllers for effects
  late AnimationController _beautyAnimationController;
  late AnimationController _speedAnimationController;
  late Animation<double> _beautyAnimation;
  
  final List<double> _speedOptions = [0.5, 1.0, 2.0];
  final List<int> _timerOptions = [0, 3, 10];
  final List<String> _speedLabels = ['0.5x', '1x', '2x'];
  
  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeCamera();
  }

  void _initializeAnimations() {
    _beautyAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _speedAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _beautyAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _beautyAnimationController, curve: Curves.easeInOut),
    );
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isNotEmpty) {
      _controller = CameraController(
        widget.cameras[_currentCameraIndex],
        ResolutionPreset.high,
        enableAudio: !_isMuted,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      
      try {
        await _controller!.initialize();
        _minZoom = await _controller!.getMinZoomLevel();
        _maxZoom = await _controller!.getMaxZoomLevel();
        
        // Apply initial settings
        await _controller!.setFlashMode(_isFlashOn ? FlashMode.torch : FlashMode.off);
        
        if (mounted) {
          setState(() => _isInitialized = true);
        }
      } catch (e) {
        print('Camera initialization error: $e');
      }
    }
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _countdownTimer?.cancel();
    _beautyAnimationController.dispose();
    _speedAnimationController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (!_isInitialized || _controller == null) return;
    if (_isCountingDown) return;

    try {
      if (_isRecording) {
        await _stopRecording();
      } else {
        if (_timerOptions[_selectedTimer] > 0) {
          await _startCountdown();
        } else {
          await _startRecording();
        }
      }
    } catch (e) {
      print('Recording error: $e');
    }
  }

  Future<void> _startCountdown() async {
    setState(() {
      _isCountingDown = true;
      _countdownSeconds = _timerOptions[_selectedTimer];
    });
    
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      setState(() => _countdownSeconds--);
      
      if (_countdownSeconds <= 0) {
        timer.cancel();
        setState(() => _isCountingDown = false);
        await _startRecording();
      }
    });
  }

  Future<void> _startRecording() async {
    try {
      final directory = await getTemporaryDirectory();
      final fileName = 'clip_${DateTime.now().millisecondsSinceEpoch}.mp4';
      
      // Apply speed settings before recording
      if (_speedOptions[_selectedSpeed] != 1.0) {
        // Note: Camera package doesn't directly support speed changes during recording
        // This would typically require post-processing or using a different approach
        print('Speed set to: ${_speedOptions[_selectedSpeed]}x');
      }
      
      await _controller!.startVideoRecording();
      
      setState(() {
        _isRecording = true;
        _recordingSeconds = 0;
      });
      
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() => _recordingSeconds++);
        }
      });
      
      // Apply beauty filter animation
      if (_isBeautyOn) {
        _beautyAnimationController.forward();
      }
      
    } catch (e) {
      print('Start recording error: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      _recordingTimer?.cancel();
      _beautyAnimationController.reverse();
      
      final video = await _controller!.stopVideoRecording();
      final videoFile = File(video.path);
      
      setState(() {
        _isRecording = false;
        _recordingSeconds = 0;
        _isProcessing = true; // Show processing indicator
      });
      
      // Process video in background without blocking UI
      _processVideoInBackground(videoFile);
      
    } catch (e) {
      print('Stop recording error: $e');
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _processVideoInBackground(File videoFile) async {
    try {
      // Process video with effects if needed
      final processedVideo = await _processVideoWithEffects(videoFile);
      
      _recordedClips.add(processedVideo);
      await _generateThumbnail(processedVideo);
      
      if (mounted) {
        setState(() => _isProcessing = false);
      }
      
    } catch (e) {
      print('Background processing error: $e');
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<File> _processVideoWithEffects(File originalVideo) async {
    try {
      final double speedMultiplier = _speedOptions[_selectedSpeed];
      
      // If no speed change, return original immediately
      if (speedMultiplier == 1.0) {
        return originalVideo;
      }
      
      final directory = await getTemporaryDirectory();
      final outputPath = '${directory.path}/processed_${DateTime.now().millisecondsSinceEpoch}.mp4';
      
      print('Processing video at ${speedMultiplier}x speed...');
      
      // FFmpeg command for speed change
      String command;
      if (speedMultiplier == 0.5) {
        // Slow motion: 0.5x speed
        command = '-i "${originalVideo.path}" -filter:v "setpts=2.0*PTS" -filter:a "atempo=0.5" -c:v libx264 -preset veryfast -crf 28 -y "$outputPath"';
      } else if (speedMultiplier == 2.0) {
        // Fast motion: 2x speed  
        command = '-i "${originalVideo.path}" -filter:v "setpts=0.5*PTS" -filter:a "atempo=2.0" -c:v libx264 -preset veryfast -crf 28 -y "$outputPath"';
      } else {
        // Default case
        return originalVideo;
      }
      
      print('FFmpeg command: $command');
      
      // Execute FFmpeg with timeout
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();
      
      if (ReturnCode.isSuccess(returnCode)) {
        print('✅ Video processing successful!');
        
        final processedFile = File(outputPath);
        if (await processedFile.exists()) {
          final fileSize = await processedFile.length();
          if (fileSize > 0) {
            // Delete original to save space
            try {
              await originalVideo.delete();
            } catch (e) {
              print('Could not delete original file: $e');
            }
            return processedFile;
          }
        }
      } else {
        print('❌ Video processing failed with return code: $returnCode');
      }
      
      // If processing failed, return original
      return originalVideo;
      
    } catch (e) {
      print('Video processing error: $e');
      return originalVideo;
    }
  }

  Future<void> _generateThumbnail(File videoFile) async {
    try {
      // Alternative 1: Use FFmpeg to generate thumbnail
      final directory = await getTemporaryDirectory();
      final thumbnailPath = '${directory.path}/thumb_${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      // FFmpeg command to extract frame at 0.5 seconds
      final command = '-i "${videoFile.path}" -ss 0.5 -vframes 1 -q:v 2 -s 150x150 -y "$thumbnailPath"';
      
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();
      
      if (ReturnCode.isSuccess(returnCode)) {
        final thumbFile = File(thumbnailPath);
        if (await thumbFile.exists()) {
          final bytes = await thumbFile.readAsBytes();
          _clipPreviews.add(bytes);
          _clipThumbnails.add(thumbnailPath);
          print('✅ Thumbnail generated successfully');
          return;
        }
      }
      
      // Fallback: Add empty preview
      _clipPreviews.add(null);
      _clipThumbnails.add('');
      print('❌ Thumbnail generation failed');
      
    } catch (e) {
      print('Thumbnail generation error: $e');
      _clipPreviews.add(null);
      _clipThumbnails.add('');
    }
  }

  Future<void> _switchCamera() async {
    if (widget.cameras.length > 1 && !_isRecording) {
      await _controller?.dispose();
      _currentCameraIndex = (_currentCameraIndex + 1) % widget.cameras.length;
      await _initializeCamera();
    }
  }

  Future<void> _toggleFlash() async {
    if (_controller != null && !_isRecording) {
      try {
        _isFlashOn = !_isFlashOn;
        await _controller!.setFlashMode(_isFlashOn ? FlashMode.torch : FlashMode.off);
        setState(() {});
      } catch (e) {
        print('Flash toggle error: $e');
      }
    }
  }

  void _toggleMute() {
    if (!_isRecording) {
      setState(() => _isMuted = !_isMuted);
    }
  }

  void _toggleBeauty() {
    setState(() => _isBeautyOn = !_isBeautyOn);
    if (_isBeautyOn) {
      _beautyAnimationController.forward();
    } else {
      _beautyAnimationController.reverse();
    }
  }

  void _cycleSpeed() {
    if (!_isRecording) {
      setState(() {
        _selectedSpeed = (_selectedSpeed + 1) % _speedOptions.length;
      });
    }
  }

  void _cycleTimer() {
    if (!_isRecording) {
      setState(() {
        _selectedTimer = (_selectedTimer + 1) % _timerOptions.length;
      });
    }
  }

  void _onZoomChanged(double zoom) {
    if (_controller != null) {
      final clampedZoom = zoom.clamp(_minZoom, _maxZoom);
      _controller!.setZoomLevel(clampedZoom);
      setState(() => _currentZoom = clampedZoom);
    }
  }

  void _reorderClips(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final File clip = _recordedClips.removeAt(oldIndex);
    final String thumbnail = _clipThumbnails.removeAt(oldIndex);
    final Uint8List? preview = _clipPreviews.removeAt(oldIndex);
    
    _recordedClips.insert(newIndex, clip);
    _clipThumbnails.insert(newIndex, thumbnail);
    _clipPreviews.insert(newIndex, preview);
    setState(() {});
  }

  void _removeClip(int index) {
    _recordedClips.removeAt(index);
    _clipThumbnails.removeAt(index);
    _clipPreviews.removeAt(index);
    setState(() {});
  }

  void _finishRecording() {
    if (_recordedClips.isNotEmpty) {
      Navigator.pushNamed(
        context,
        '/video-editor',
        arguments: {'files': _recordedClips},
      );
    }
  }

  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
    String? activeLabel,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        height: 70,
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isActive 
                    ? Colors.white.withOpacity(0.3) 
                    : Colors.black.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isActive ? Colors.yellow : Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              activeLabel ?? label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClipsList() {
  if (_recordedClips.isEmpty) return const SizedBox.shrink();
  
  return Container(
    height: 60,
    margin: const EdgeInsets.only(bottom: 10),
    child: ReorderableListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: _recordedClips.length,
      onReorder: _reorderClips,
      proxyDecorator: (child, index, animation) {
        // Custom drag appearance
        return Material(
          type: MaterialType.transparency,
          child: Container(
            width: 50,
            height: 50,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withOpacity(0.5)),
            ),
            child: _buildClipContent(index),
          ),
        );
      },
      itemBuilder: (context, index) {
        return Container(
          key: ValueKey(index),
          width: 50,
          height: 50,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withOpacity(0.5)),
          ),
          child: _buildClipContent(index),
        );
      },
    ),
  );
}

Widget _buildClipContent(int index) {
  return Stack(
    children: [
      // Video preview background
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 50,
          height: 50,
          child: _clipPreviews.length > index && _clipPreviews[index] != null
              ? Image.memory(
                  _clipPreviews[index]!,
                  fit: BoxFit.cover,
                  width: 50,
                  height: 50,
                  errorBuilder: (context, error, stackTrace) {
                    return _buildFallbackPreview();
                  },
                )
              : _buildFallbackPreview(),
        ),
      ),
      
      // Dark overlay for better visibility
      Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.black.withOpacity(0.2),
        ),
      ),
      
      // Play button indicator
      const Center(
        child: Icon(
          Icons.play_arrow,
          color: Colors.white,
          size: 16,
          shadows: [
            Shadow(
              blurRadius: 2,
              color: Colors.black,
              offset: Offset(1, 1),
            ),
          ],
        ),
      ),
      
      // Clip number
      Positioned(
        bottom: 2,
        right: 2,
        child: Container(
          width: 16,
          height: 16,
          decoration: const BoxDecoration(
            color: Colors.red,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
      
      // Delete button
      Positioned(
        top: 2,
        right: 2,
        child: GestureDetector(
          onTap: () => _removeClip(index),
          child: Container(
            width: 16,
            height: 16,
            decoration: const BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.close,
              color: Colors.white,
              size: 10,
            ),
          ),
        ),
      ),
      
      // Speed indicator (if not 1x)
      if (_speedOptions.isNotEmpty && _speedOptions[_selectedSpeed] != 1.0)
        Positioned(
          top: 2,
          left: 2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.purple.withOpacity(0.8),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              '${_speedLabels[_selectedSpeed]}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
    ],
  );
}

  Widget _buildFallbackPreview() {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.grey[800]!,
            Colors.grey[900]!,
          ],
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(
        Icons.videocam,
        color: Colors.white70,
        size: 20,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/bg.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: _isInitialized
            ? Stack(
                children: [
                  // Camera preview - adjusted size
                  Positioned(
                    top: 80,
                    left: 0,
                    right: 0,
                    bottom: 140,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(0),
                      child: GestureDetector(
                        onScaleUpdate: _isRecording ? null : (details) {
                          double zoom = _currentZoom * details.scale;
                          _onZoomChanged(zoom);
                        },
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: CameraPreview(_controller!),
                            ),
                            // Beauty filter overlay
                            if (_isBeautyOn)
                              AnimatedBuilder(
                                animation: _beautyAnimation,
                                builder: (context, child) {
                                  return Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.pink.withOpacity(0.1 * _beautyAnimation.value),
                                          Colors.transparent,
                                          Colors.pink.withOpacity(0.05 * _beautyAnimation.value),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  
                  // Top bar
                  Positioned(
                    top: MediaQuery.of(context).padding.top,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back, color: Colors.white),
                            onPressed: () => Navigator.pop(context),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.music_note, color: Colors.white, size: 16),
                                SizedBox(width: 4),
                                Text('Music', style: TextStyle(color: Colors.white, fontSize: 12)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 48), // Placeholder for symmetry
                        ],
                      ),
                    ),
                  ),
                  
                  // Processing indicator - blended
                  if (_isProcessing)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 100,
                      left: 20,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withOpacity(0.3)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Processing...',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 60,
                      left: 20,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _isCountingDown ? Colors.orange : Colors.red,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!_isCountingDown) ...[
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'REC ${_formatTime(_recordingSeconds)}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ] else ...[
                              Text(
                                '$_countdownSeconds',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  
                  // Right side controls
                  Positioned(
                    right: 20,
                    top: MediaQuery.of(context).padding.top + 80,
                    child: Column(
                      children: [
                        _buildControlButton(
                          icon: Icons.cameraswitch,
                          label: 'Toggle',
                          onTap: _switchCamera,
                        ),
                        _buildControlButton(
                          icon: _isFlashOn ? Icons.flash_on : Icons.flash_off,
                          label: _isFlashOn ? 'flash' : 'no-flash',
                          onTap: _toggleFlash,
                          isActive: _isFlashOn,
                        ),
                        _buildControlButton(
                          icon: Icons.timer,
                          label: _timerOptions[_selectedTimer] == 0 ? 'Timer' : '${_timerOptions[_selectedTimer]}s',
                          onTap: _cycleTimer,
                          isActive: _timerOptions[_selectedTimer] != 0,
                        ),
                        _buildControlButton(
                          icon: Icons.speed,
                          label: _speedLabels[_selectedSpeed],
                          onTap: _cycleSpeed,
                          isActive: _speedOptions[_selectedSpeed] != 1.0,
                        ),
                        _buildControlButton(
                          icon: _isMuted ? Icons.mic_off : Icons.mic,
                          label: 'Sound',
                          onTap: _toggleMute,
                          isActive: !_isMuted,
                        ),
                      ],
                    ),
                  ),
                  
                  // Left side controls
                  Positioned(
                    left: 20,
                    bottom: 250,
                    child: Column(
                      children: [
                        _buildControlButton(
                          icon: Icons.music_note,
                          label: 'Music',
                          onTap: () {},
                        ),
                        _buildControlButton(
                          icon: Icons.auto_fix_high,
                          label: 'Beauty',
                          onTap: _toggleBeauty,
                          isActive: _isBeautyOn,
                        ),
                        _buildControlButton(
                          icon: Icons.filter,
                          label: 'Filter',
                          onTap: () {},
                        ),
                        _buildControlButton(
                          icon: Icons.face,
                          label: 'Masks',
                          onTap: () {},
                        ),
                      ],
                    ),
                  ),
                  
                  // Clips list
                  Positioned(
                    bottom: 120,
                    left: 20,
                    right: 20,
                    child: _buildClipsList(),
                  ),
                  
                  // Bottom controls
                  Positioned(
                    bottom: 50,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Recorded clips count
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${_recordedClips.length}',
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        
                        // Record button
                        GestureDetector(
                          onTap: _toggleRecording,
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                              color: _isRecording ? Colors.red : Colors.transparent,
                            ),
                            child: _isRecording
                                ? const Icon(Icons.stop, color: Colors.white, size: 40)
                                : Container(
                                    margin: const EdgeInsets.all(8),
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                          ),
                        ),
                        
                        // Next button
                        GestureDetector(
                          onTap: _recordedClips.isNotEmpty ? _finishRecording : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            decoration: BoxDecoration(
                              color: _recordedClips.isNotEmpty ? Colors.purple : Colors.grey.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: const Text(
                              'Next',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Zoom indicator
                  if (_currentZoom != 1.0)
                    Positioned(
                      bottom: 200,
                      right: 20,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_currentZoom.toStringAsFixed(1)}x',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ),
                ],
              )
            : Container(
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('assets/images/bg.png'),
                    fit: BoxFit.cover,
                  ),
                ),
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
      ),
    );
  }
}