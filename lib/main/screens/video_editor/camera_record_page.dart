import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';

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

class _CameraRecordPageState extends State<CameraRecordPage> {
  CameraController? _controller;
  bool _isRecording = false;
  bool _isInitialized = false;
  int _currentCameraIndex = 0;
  List<File> _recordedClips = [];
  
  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isNotEmpty) {
      _controller = CameraController(
        widget.cameras[_currentCameraIndex],
        ResolutionPreset.high,
        enableAudio: true,
      );
      
      try {
        await _controller!.initialize();
        setState(() => _isInitialized = true);
      } catch (e) {
        print('Camera initialization error: $e');
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (!_isInitialized || _controller == null) return;

    try {
      if (_isRecording) {
        // Stop recording
        final video = await _controller!.stopVideoRecording();
        _recordedClips.add(File(video.path));
        setState(() => _isRecording = false);
      } else {
        // Start recording
        final directory = await getTemporaryDirectory();
        final fileName = 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
        final filePath = '${directory.path}/$fileName';
        
        await _controller!.startVideoRecording();
        setState(() => _isRecording = true);
      }
    } catch (e) {
      print('Recording error: $e');
    }
  }

  Future<void> _switchCamera() async {
    if (widget.cameras.length > 1) {
      await _controller?.dispose();
      _currentCameraIndex = (_currentCameraIndex + 1) % widget.cameras.length;
      await _initializeCamera();
    }
  }

  void _finishRecording() {
    if (_recordedClips.isNotEmpty) {
      widget.onDone(_recordedClips);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (widget.cameras.length > 1)
            IconButton(
              icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
              onPressed: _switchCamera,
            ),
        ],
      ),
      body: _isInitialized
          ? Stack(
              children: [
                // Camera preview
                Positioned.fill(
                  child: AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: CameraPreview(_controller!),
                  ),
                ),
                
                // Recording indicator
                if (_isRecording)
                  Positioned(
                    top: 50,
                    left: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'REC',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
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
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${_recordedClips.length}',
                          style: const TextStyle(color: Colors.white, fontSize: 16),
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
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                        ),
                      ),
                      
                      // Done button
                      GestureDetector(
                        onTap: _recordedClips.isNotEmpty ? _finishRecording : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          decoration: BoxDecoration(
                            color: _recordedClips.isNotEmpty ? Colors.white : Colors.grey,
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: Text(
                            'Done',
                            style: TextStyle(
                              color: _recordedClips.isNotEmpty ? Colors.black : Colors.grey[600],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}