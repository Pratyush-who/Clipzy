import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../routes.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  void _showBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: HugeIcon(
                icon: HugeIcons.strokeRoundedFiles01,
                color: Colors.deepPurple,
                size: 32,
              ),
              title: const Text('Gallery', style: TextStyle(fontSize: 18)),
              onTap: () async {
                Navigator.pop(sheetContext);
                _onGalleryTap(context); // Use parent context for navigation
              },
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: HugeIcon(
                icon: HugeIcons.strokeRoundedCamera01,
                color: Colors.deepPurple,
                size: 32,
              ),
              title: const Text('Camera', style: TextStyle(fontSize: 18)),
              onTap: () => _onCameraTap(context),
            ),
          ],
        ),
      ),
    );
  }

  void _onGalleryTap(BuildContext parentContext) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: true,
    );
    if (result != null && result.files.isNotEmpty) {
      final cacheDir = await getTemporaryDirectory();
      final files = <File>[];
      for (final file in result.files) {
        final src = File(file.path!);
        final dest = File('${cacheDir.path}/${file.name}');
        await dest.writeAsBytes(await src.readAsBytes());
        files.add(dest);
      }
      // Navigate to video editor page with picked files
      Navigator.pushNamed(
        parentContext,
        '/video-editor',
        arguments: {'files': files},
      );
    }
  }

  void _onCameraTap(BuildContext context) async {
    final cameraStatus = await Permission.camera.status;
    final micStatus = await Permission.microphone.status;
    if (cameraStatus.isGranted && micStatus.isGranted) {
      final cameras = await availableCameras();
      Navigator.pop(context);
      Navigator.pushNamed(
        context,
        AppRoutes.cameraRecord,
        arguments: {'cameras': cameras, 'onDone': (List<File> clips) {}},
      );
    } else {
      Navigator.pop(context);
      Navigator.pushNamed(context, AppRoutes.cameraPermission);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: const Center(
        child: Text('Dashboard', style: TextStyle(fontSize: 24)),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showBottomSheet(context),
        backgroundColor: Colors.deepPurple,
        child: const Icon(Icons.add, color: Colors.white),
        tooltip: 'Add',
      ),
    );
  }
}
