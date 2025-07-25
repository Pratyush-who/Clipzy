import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:ffmpeg_kit_flutter_minimal/ffmpeg_kit.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;

class CameraRecordPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  final void Function(List<File> clips) onDone;
  const CameraRecordPage({
    super.key,
    required this.cameras,
    required this.onDone,
  });

  @override
  State<CameraRecordPage> createState() => _CameraRecordPageState();
}

class _CameraRecordPageState extends State<CameraRecordPage> {
  late CameraController _controller;
  bool _isRecording = false;
  bool _isPaused = false;
  bool _showControls = true;
  int _selectedCameraIdx = 0;
  int _selectedQualityIdx = 0;
  double _zoom = 1.0;
  final List<double> _zoomLevels = [1, 2, 3, 5];
  final List<String> _qualities = ['HD', '2K', '4K'];
  final List<File> _clips = [];
  VideoPlayerController? _videoPlayerController;
  bool _flashOn = false;
  bool _beautifyOn = false;
  String? _lastVideoPath;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    _controller = CameraController(
      widget.cameras[_selectedCameraIdx],
      ResolutionPreset.high,
      enableAudio: true,
    );
    await _controller.initialize();
    setState(() {});
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final file = await _controller.stopVideoRecording();
      setState(() {
        _isRecording = false;
        _showControls = true;
        _lastVideoPath = file.path;
      });
      File processed = File(file.path);
      if (_beautifyOn) {
        // Apply beautify filter using ffmpeg_kit
        final outPath = file.path.replaceFirst('.mp4', '_beauty.mp4');
        await FFmpegKit.execute(
          '-i ${file.path} -vf "eq=contrast=1.2:brightness=0.05:saturation=1.3" $outPath',
        );
        processed = File(outPath);
      }
      _clips.add(processed);
      setState(() {});
    } else {
      await _controller.prepareForVideoRecording();
      await _controller.startVideoRecording();
      setState(() {
        _isRecording = true;
        _showControls = false;
      });
    }
  }

  void _togglePause() async {
    if (_isRecording) {
      if (_isPaused) {
        await _controller.resumeVideoRecording();
      } else {
        await _controller.pauseVideoRecording();
      }
      setState(() {
        _isPaused = !_isPaused;
      });
    }
  }

  void _toggleFlash() async {
    _flashOn = !_flashOn;
    await _controller.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
    setState(() {});
  }

  void _toggleBeautify() {
    setState(() {
      _beautifyOn = !_beautifyOn;
    });
  }

  void _flipCamera() async {
    _selectedCameraIdx = (_selectedCameraIdx + 1) % widget.cameras.length;
    await _controller.dispose();
    await _initCamera();
  }

  void _changeQuality() async {
    _selectedQualityIdx = (_selectedQualityIdx + 1) % _qualities.length;
    await _controller.dispose();
    _controller = CameraController(
      widget.cameras[_selectedCameraIdx],
      _selectedQualityIdx == 0
          ? ResolutionPreset.high
          : _selectedQualityIdx == 1
          ? ResolutionPreset.veryHigh
          : ResolutionPreset.ultraHigh,
      enableAudio: true,
    );
    await _controller.initialize();
    setState(() {});
  }

  void _setZoom(double zoom) async {
    _zoom = zoom;
    await _controller.setZoomLevel(_zoom);
    setState(() {});
  }

  void _playClip(File file) async {
    _videoPlayerController?.dispose();
    _videoPlayerController = VideoPlayerController.file(file);
    await _videoPlayerController!.initialize();
    setState(() {});
    _videoPlayerController!.play();
  }

  @override
  void dispose() {
    _controller.dispose();
    _videoPlayerController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          CameraPreview(_controller),
          if (_showControls) ...[
            Positioned(
              bottom: 120,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: _zoomLevels
                    .map(
                      (z) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _zoom == z
                                ? Colors.deepPurple
                                : Colors.white24,
                            shape: const CircleBorder(),
                          ),
                          onPressed: () => _setZoom(z),
                          child: Text(
                            '${z.toInt()}x',
                            style: TextStyle(
                              color: _zoom == z
                                  ? Colors.white
                                  : Colors.deepPurple,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: Icon(
                      _flashOn ? Icons.flash_on : Icons.flash_off,
                      color: Colors.white,
                      size: 32,
                    ),
                    onPressed: _toggleFlash,
                  ),
                  IconButton(
                    icon: Icon(
                      _beautifyOn ? Icons.auto_fix_high : Icons.auto_fix_normal,
                      color: Colors.white,
                      size: 32,
                    ),
                    onPressed: _toggleBeautify,
                  ),
                  GestureDetector(
                    onTap: _toggleRecording,
                    onLongPress: _togglePause,
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: _isRecording ? Colors.red : Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      child: Icon(
                        _isRecording
                            ? (_isPaused ? Icons.play_arrow : Icons.pause)
                            : Icons.fiber_manual_record,
                        color: _isRecording ? Colors.white : Colors.red,
                        size: 40,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.cameraswitch,
                      color: Colors.white,
                      size: 32,
                    ),
                    onPressed: _flipCamera,
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.high_quality,
                      color: Colors.white,
                      size: 32,
                    ),
                    onPressed: _changeQuality,
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 8,
              right: 16,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                ),
                onPressed: _clips.isNotEmpty
                    ? () {
                        Navigator.pop(context, _clips);
                        // Optionally: Navigator.pushNamed(context, '/editor', arguments: _clips);
                      }
                    : null,
                child: const Text('Done'),
              ),
            ),
            if (_clips.isNotEmpty)
              Positioned(
                bottom: 100,
                left: 0,
                right: 0,
                child: SizedBox(
                  height: 64,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: _clips
                        .map(
                          (file) => GestureDetector(
                            onTap: () => _playClip(file),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child:
                                  VideoPlayerController.file(
                                    file,
                                  ).value.isInitialized
                                  ? VideoPlayer(
                                      VideoPlayerController.file(file),
                                    )
                                  : const Icon(
                                      Icons.videocam,
                                      color: Colors.white,
                                    ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
