import 'dart:io';

import 'package:clipzy/main/auth/auth_wrapper.dart';
import 'package:clipzy/main/screens/authscreens/login_screen.dart';
import 'package:flutter/material.dart';
import 'main/screens/splashscreen/splash_screen.dart';
import 'main/screens/home_screen.dart';
import 'main/screens/mainscreens/dashboard_screen.dart';
import 'main/screens/video_editor/camera_permission_page.dart';
import 'main/screens/video_editor/camera_record_page.dart';
import 'main/screens/video_editor/video_editor_page.dart';

class AppRoutes {
  static const String splash = '/splash';
  static const String auth = '/';
  static const String home = '/home';
  static const String dashboard = '/dashboard';
  static const String cameraPermission = '/camera-permission';
  static const String cameraRecord = '/camera-record';
  static const String login = '/login';

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return MaterialPageRoute(builder: (_) => const SplashScreen());
      case auth:
        return MaterialPageRoute(builder: (_) => const AuthWrapper());
      case home:
        return MaterialPageRoute(builder: (_) => const HomeScreen());
      case login:
        return MaterialPageRoute(builder: (_) => const AuthScreen());
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
      case '/video-editor':
        final args = settings.arguments as Map<String, dynamic>?;
        return MaterialPageRoute(
          builder: (_) => VideoEditorPage(files: args?['files'] as List<File>),
        );
      default:
        return MaterialPageRoute(
          builder: (_) =>
              const Scaffold(body: Center(child: Text('Page not found'))),
        );
    }
  }
}
