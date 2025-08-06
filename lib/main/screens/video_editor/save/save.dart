import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';

class SavedVideo {
  String id;
  String name;
  String filePath;
  DateTime createdAt;
  Duration duration;
  String thumbnailPath;
  int fileSizeBytes;

  SavedVideo({
    required this.id,
    required this.name,
    required this.filePath,
    required this.createdAt,
    required this.duration,
    required this.thumbnailPath,
    required this.fileSizeBytes,
  });

  String get formattedFileSize {
    if (fileSizeBytes < 1024) return '${fileSizeBytes}B';
    if (fileSizeBytes < 1024 * 1024)
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)}KB';
    if (fileSizeBytes < 1024 * 1024 * 1024)
      return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(fileSizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  String get formattedDuration {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class SaveLocalWidget extends StatefulWidget {
  final String videoPath;
  final Function(String savedPath, String name) onVideoSaved;
  final VoidCallback? onCancel;

  const SaveLocalWidget({
    Key? key,
    required this.videoPath,
    required this.onVideoSaved,
    this.onCancel,
  }) : super(key: key);

  @override
  State<SaveLocalWidget> createState() => _SaveLocalWidgetState();
}

class _SaveLocalWidgetState extends State<SaveLocalWidget>
    with TickerProviderStateMixin {
  late TextEditingController _nameController;
  late AnimationController _progressController;
  late AnimationController _successController;
  late Animation<double> _progressAnimation;
  late Animation<double> _successAnimation;

  bool _isSaving = false;
  bool _saveToGallery = true;
  bool _keepInApp = true;
  double _saveProgress = 0.0;
  String _saveStatus = '';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: 'EditedVideo_${DateTime.now().millisecondsSinceEpoch}',
    );
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _progressController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _successController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeInOut),
    );

    _successAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _successController, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _progressController.dispose();
    _successController.dispose();
    super.dispose();
  }

  Future<void> _saveVideo() async {
    if (_isSaving || _nameController.text.trim().isEmpty) return;

    setState(() {
      _isSaving = true;
      _saveProgress = 0.0;
      _saveStatus = 'Preparing to save...';
    });

    _progressController.forward();

    try {
      if (_saveToGallery) {
        final permission = Platform.isAndroid
            ? Permission.storage
            : Permission.photos;

        final status = await permission.request();
        if (status != PermissionStatus.granted) {
          throw Exception('Storage permission not granted');
        }
      }

      final fileName = '${_nameController.text.trim()}.mp4';
      String savedPath = '';

      if (_keepInApp) {
        setState(() {
          _saveStatus = 'Saving to app storage...';
          _saveProgress = 0.3;
        });

        final appDir = await getApplicationDocumentsDirectory();
        final appSavedDir = Directory('${appDir.path}/saved_videos');
        if (!await appSavedDir.exists()) {
          await appSavedDir.create(recursive: true);
        }

        savedPath = '${appSavedDir.path}/$fileName';
        final sourceFile = File(widget.videoPath);
        await sourceFile.copy(savedPath);

        setState(() {
          _saveProgress = 0.6;
        });
      }

      if (_saveToGallery) {
        setState(() {
          _saveStatus = 'Saving to gallery...';
          _saveProgress = 0.8;
        });

        // For now, we'll save to documents directory since gallery_saver is removed
        // In a real app, you might want to use a different gallery saving library
        final documentsDir = await getApplicationDocumentsDirectory();
        final galleryDir = Directory('${documentsDir.path}/gallery');
        if (!await galleryDir.exists()) {
          await galleryDir.create(recursive: true);
        }

        final galleryPath = '${galleryDir.path}/$fileName';
        final sourceFile = File(widget.videoPath);
        await sourceFile.copy(galleryPath);
      }

      setState(() {
        _saveProgress = 1.0;
        _saveStatus = 'Saved successfully!';
      });

      await _successController.forward();
      HapticFeedback.heavyImpact();

      widget.onVideoSaved(
        savedPath.isNotEmpty ? savedPath : widget.videoPath,
        fileName,
      );

      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) Navigator.pop(context);
      });
    } catch (e) {
      setState(() {
        _isSaving = false;
        _saveStatus = 'Error: ${e.toString()}';
        _saveProgress = 0.0;
      });
      _progressController.reverse();
      HapticFeedback.heavyImpact();
    }
  }

  Future<void> _shareVideo() async {
    try {
      await Share.shareXFiles([XFile(widget.videoPath)]);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sharing video: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[600],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              const Icon(Icons.save_alt, color: Colors.green, size: 24),
              const SizedBox(width: 12),
              const Text(
                'Save Video',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 30),

          if (!_isSaving) ...[
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[600]!, width: 1),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Enter video name...',
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear, color: Colors.grey),
                    onPressed: () => _nameController.clear(),
                  ),
                ),
                textCapitalization: TextCapitalization.words,
              ),
            ),

            const SizedBox(height: 30),

            Text(
              'Save Options',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 16),

            _buildSaveOption(
              'Save to Gallery',
              'Save video to device photo gallery',
              Icons.photo_library,
              _saveToGallery,
              (value) => setState(() => _saveToGallery = value),
            ),

            const SizedBox(height: 12),

            _buildSaveOption(
              'Keep in App',
              'Save copy in app for quick access',
              Icons.folder,
              _keepInApp,
              (value) => setState(() => _keepInApp = value),
            ),

            const SizedBox(height: 30),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildQuickAction(
                  'Share',
                  Icons.share,
                  Colors.blue,
                  _shareVideo,
                ),
                _buildQuickAction(
                  'Preview',
                  Icons.play_circle_outline,
                  Colors.purple,
                  () {},
                ),
              ],
            ),

            const SizedBox(height: 30),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: widget.onCancel ?? () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[800],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed:
                        (_saveToGallery || _keepInApp) &&
                            _nameController.text.trim().isNotEmpty
                        ? _saveVideo
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Save Video',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            AnimatedBuilder(
              animation: _successAnimation,
              builder: (context, child) {
                if (_successAnimation.value > 0) {
                  return Transform.scale(
                    scale: _successAnimation.value,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.green, width: 3),
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.green,
                        size: 60,
                      ),
                    ),
                  );
                }

                return Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.blue, width: 3),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 80,
                        height: 80,
                        child: CircularProgressIndicator(
                          value: _saveProgress,
                          strokeWidth: 6,
                          backgroundColor: Colors.grey[600],
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.blue,
                          ),
                        ),
                      ),
                      Text(
                        '${(_saveProgress * 100).toInt()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 20),

            Text(
              _saveStatus,
              style: TextStyle(
                color: _saveStatus.contains('Error')
                    ? Colors.red
                    : Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),

            if (_saveStatus.contains('Error')) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isSaving = false;
                    _saveProgress = 0.0;
                    _saveStatus = '';
                  });
                  _progressController.reset();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Try Again'),
              ),
            ],
          ],

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSaveOption(
    String title,
    String subtitle,
    IconData icon,
    bool value,
    Function(bool) onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value ? Colors.green : Colors.grey[600]!,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: value ? Colors.green : Colors.grey[400], size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.green,
            inactiveThumbColor: Colors.grey[400],
            inactiveTrackColor: Colors.grey[600],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SavedVideosManager {
  static const String _savedVideosKey = 'saved_videos';

  static Future<List<SavedVideo>> getSavedVideos() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final savedDir = Directory('${appDir.path}/saved_videos');

      if (!await savedDir.exists()) {
        return [];
      }

      final files = await savedDir
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.mp4'))
          .toList();

      List<SavedVideo> savedVideos = [];

      for (var file in files) {
        final fileStat = await file.stat();
        final fileName = file.path.split('/').last;
        final name = fileName.replaceAll('.mp4', '');

        savedVideos.add(
          SavedVideo(
            id: name,
            name: name,
            filePath: file.path,
            createdAt: fileStat.modified,
            duration: Duration.zero,
            thumbnailPath: '',
            fileSizeBytes: fileStat.size,
          ),
        );
      }

      savedVideos.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return savedVideos;
    } catch (e) {
      print('Error getting saved videos: $e');
      return [];
    }
  }

  static Future<bool> deleteVideo(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      print('Error deleting video: $e');
      return false;
    }
  }

  static Future<String?> renameVideo(String oldPath, String newName) async {
    try {
      final file = File(oldPath);
      if (!await file.exists()) return null;

      final directory = file.parent;
      final newPath = '${directory.path}/$newName.mp4';

      final renamedFile = await file.rename(newPath);
      return renamedFile.path;
    } catch (e) {
      print('Error renaming video: $e');
      return null;
    }
  }
}

class SavedVideosListWidget extends StatefulWidget {
  final Function(SavedVideo)? onVideoSelected;

  const SavedVideosListWidget({Key? key, this.onVideoSelected})
    : super(key: key);

  @override
  State<SavedVideosListWidget> createState() => _SavedVideosListWidgetState();
}

class _SavedVideosListWidgetState extends State<SavedVideosListWidget> {
  List<SavedVideo> _savedVideos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSavedVideos();
  }

  Future<void> _loadSavedVideos() async {
    setState(() => _isLoading = true);

    final videos = await SavedVideosManager.getSavedVideos();

    if (mounted) {
      setState(() {
        _savedVideos = videos;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteVideo(SavedVideo video) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Delete Video',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to delete "${video.name}"?',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (result == true) {
      final success = await SavedVideosManager.deleteVideo(video.filePath);
      if (success) {
        _loadSavedVideos();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[600],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              const Icon(Icons.video_library, color: Colors.blue, size: 24),
              const SizedBox(width: 12),
              const Text(
                'Saved Videos',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: _loadSavedVideos,
              ),
            ],
          ),

          const SizedBox(height: 20),

          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: Colors.blue))
          else if (_savedVideos.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              child: Column(
                children: [
                  Icon(
                    Icons.video_library_outlined,
                    color: Colors.grey[600],
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No saved videos yet',
                    style: TextStyle(color: Colors.grey[400], fontSize: 18),
                  ),
                  Text(
                    'Export your edited videos to see them here',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _savedVideos.length,
                itemBuilder: (context, index) {
                  final video = _savedVideos[index];
                  return _buildVideoItem(video);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVideoItem(SavedVideo video) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[700]!, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.grey[700],
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.play_circle_outline,
              color: Colors.white,
              size: 24,
            ),
          ),

          const SizedBox(width: 16),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  video.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      video.formattedFileSize,
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '• ${_formatDate(video.createdAt)}',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),

          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: Colors.grey[400]),
            color: Colors.grey[800],
            onSelected: (value) async {
              switch (value) {
                case 'play':
                  widget.onVideoSelected?.call(video);
                  break;
                case 'share':
                  await Share.shareXFiles([XFile(video.filePath)]);
                  break;
                case 'delete':
                  await _deleteVideo(video);
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'play',
                child: Row(
                  children: [
                    Icon(Icons.play_arrow, color: Colors.white, size: 20),
                    SizedBox(width: 12),
                    Text('Play', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    Icon(Icons.share, color: Colors.white, size: 20),
                    SizedBox(width: 12),
                    Text('Share', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: Colors.red, size: 20),
                    SizedBox(width: 12),
                    Text('Delete', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}
