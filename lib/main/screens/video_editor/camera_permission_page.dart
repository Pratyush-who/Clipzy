import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraPermissionPage extends StatelessWidget {
  final VoidCallback onGranted;
  const CameraPermissionPage({super.key, required this.onGranted});

  Future<void> _requestPermissions(BuildContext context) async {
    final statuses = await [Permission.camera, Permission.microphone].request();
    if (statuses[Permission.camera]?.isGranted == true &&
        statuses[Permission.microphone]?.isGranted == true) {
      onGranted();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera and microphone permissions are required.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.deepPurple.shade50,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam, size: 80, color: Colors.deepPurple),
              const SizedBox(height: 24),
              Text(
                'Allow "Clipzy" to access your camera and microphone',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple.shade900,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'We need access to your camera and microphone to record and edit videos.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 24),
                  ElevatedButton(
                    onPressed: () async {
                      final statuses = await [
                        Permission.camera,
                        Permission.microphone,
                      ].request();
                      if (statuses[Permission.camera]?.isGranted == true &&
                          statuses[Permission.microphone]?.isGranted == true) {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/camera-record');
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Camera and microphone permissions are required.',
                            ),
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                    ),
                    child: const Text('Continue'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
