import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:image_picker/image_picker.dart';

class VideoEditorPage extends StatefulWidget {
  final List<File> files;
  const VideoEditorPage({super.key, required this.files});

  @override
  State<VideoEditorPage> createState() => _VideoEditorPageState();
}

class _VideoEditorPageState extends State<VideoEditorPage> {
  late VideoPlayerController _controller;
  double _trimStart = 0.0;
  double _trimEnd = 1.0;
  bool _isExporting = false;
  String? _exportedPath;
  final List<_Sticker> _stickers = [];
  final List<_TextOverlay> _texts = [];
  File? _audioFile;
  double _cropLeft = 0, _cropTop = 0, _cropRight = 0, _cropBottom = 0;
  double _zoom = 1.0;

  @override
  void initState() {
    super.initState();
    if (widget.files.isNotEmpty) {
      _controller = VideoPlayerController.file(widget.files.first)
        ..initialize().then((_) => setState(() {}));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickAudio() async {
    // For now, we'll use file picker to select audio files
    // In a real implementation, you might want to use a dedicated audio picker
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Audio picker not implemented yet')),
    );
  }

  Future<void> _exportTrim() async {
    if (widget.files.isEmpty) return;

    setState(() => _isExporting = true);
    try {
      final duration = _controller.value.duration;
      final start = (_trimStart * duration.inMilliseconds).toInt() ~/ 1000;
      final end = (_trimEnd * duration.inMilliseconds).toInt() ~/ 1000;
      final outPath = widget.files.first.path.replaceFirst(
        '.mp4',
        '_trimmed.mp4',
      );
      final cmd =
          '-i "${widget.files.first.path}" -ss $start -to $end -c copy "$outPath"';
      await FFmpegKit.execute(cmd);
      setState(() {
        _isExporting = false;
        _exportedPath = outPath;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Exported to $outPath')));
      }
    } catch (e) {
      setState(() => _isExporting = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  void _addTextOverlay() {
    setState(() {
      _texts.add(_TextOverlay(text: 'Sample Text', left: 50, top: 50));
    });
  }

  void _addSticker() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _stickers.add(_Sticker(image: File(picked.path)));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.files.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('No video files provided')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Editor'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _isExporting ? null : _exportTrim,
            tooltip: 'Export Trim',
          ),
        ],
      ),
      body: _controller.value.isInitialized
          ? Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Center(
                        child: AspectRatio(
                          aspectRatio: _controller.value.aspectRatio,
                          child: VideoPlayer(_controller),
                        ),
                      ),
                      // Stickers
                      ..._stickers.map((sticker) => sticker.build(context)),
                      // Text overlays
                      ..._texts.map((t) => t.build(context)),
                    ],
                  ),
                ),
                // Timeline for trim
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const Text('Trim:'),
                      Expanded(
                        child: RangeSlider(
                          values: RangeValues(_trimStart, _trimEnd),
                          onChanged: (v) => setState(() {
                            _trimStart = v.start;
                            _trimEnd = v.end;
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
                // Feature buttons
                Wrap(
                  spacing: 8,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.cut),
                      label: const Text('Trim'),
                      onPressed: _isExporting ? null : _exportTrim,
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.call_split),
                      label: const Text('Split'),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Split not implemented yet'),
                          ),
                        );
                      },
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.crop),
                      label: const Text('Crop'),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Crop not implemented yet'),
                          ),
                        );
                      },
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.zoom_in),
                      label: const Text('Zoom'),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Zoom not implemented yet'),
                          ),
                        );
                      },
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.audiotrack),
                      label: const Text('Audio'),
                      onPressed: _pickAudio,
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.text_fields),
                      label: const Text('Text'),
                      onPressed: _addTextOverlay,
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.emoji_emotions),
                      label: const Text('Sticker'),
                      onPressed: _addSticker,
                    ),
                  ],
                ),
                if (_isExporting) const LinearProgressIndicator(),
                if (_exportedPath != null)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text('Exported: $_exportedPath'),
                  ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}

class _TextOverlay {
  String text;
  double left;
  double top;
  _TextOverlay({required this.text, required this.left, required this.top});
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      child: Draggable(
        feedback: Material(
          color: Colors.transparent,
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 24,
              color: Colors.white,
              backgroundColor: Colors.black54,
            ),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 24,
            color: Colors.white,
            backgroundColor: Colors.black54,
          ),
        ),
        onDragEnd: (details) {
          // TODO: Update position
        },
      ),
    );
  }
}

class _Sticker {
  final File image;
  double left;
  double top;
  _Sticker({required this.image, this.left = 100, this.top = 100});
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      child: Draggable(
        feedback: Image.file(image, width: 64, height: 64),
        child: Image.file(image, width: 64, height: 64),
        onDragEnd: (details) {
          // TODO: Update position
        },
      ),
    );
  }
}
