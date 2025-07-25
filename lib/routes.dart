import 'package:flutter/material.dart';
import 'main/screens/splashscreen/splash_screen.dart';
import 'main/screens/authscreens/login_screen.dart';
import 'main/screens/home_screen.dart';
import 'main/screens/mainscreens/dashboard_screen.dart';
import 'main/screens/video_editor/camera_permission_page.dart';
import 'main/screens/video_editor/camera_record_page.dart';

class AppRoutes {
  static const String splash = '/splash';
  static const String auth = '/auth';
  static const String home = '/home';
  static const String dashboard = '/dashboard';
  static const String cameraPermission = '/camera-permission';
  static const String cameraRecord = '/camera-record';

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return MaterialPageRoute(builder: (_) => const SplashScreen());
      case auth:
        return MaterialPageRoute(builder: (_) => const AuthScreen());
      case home:
        return MaterialPageRoute(builder: (_) => const HomeScreen());
      case dashboard:
        return MaterialPageRoute(builder: (_) => const DashboardScreen());
      case cameraPermission:
        final VoidCallback? onGranted = settings.arguments as VoidCallback?;
        return MaterialPageRoute(
          builder: (_) => CameraPermissionPage(onGranted: onGranted ?? () {}),
        );
      case cameraRecord:
        final args = settings.arguments as Map<String, dynamic>?;
        return MaterialPageRoute(
          builder: (_) => CameraRecordPage(
            cameras: args?['cameras'],
            onDone: args?['onDone'],
          ),
        );
      default:
        return MaterialPageRoute(
          builder: (_) =>
              const Scaffold(body: Center(child: Text('Page not found'))),
        );
    }
  }
}
