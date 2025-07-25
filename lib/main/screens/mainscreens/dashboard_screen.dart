import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../routes.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  void _showBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
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
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(
                  context,
                  AppRoutes.dashboard,
                ); // Replace with actual gallery route if needed
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
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, AppRoutes.cameraPermission);
              },
            ),
          ],
        ),
      ),
    );
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
