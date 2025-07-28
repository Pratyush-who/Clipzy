import 'package:flutter/material.dart';
import 'package:clipzy/routes.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () {
      Navigator.pushReplacementNamed(context, AppRoutes.auth);
    });
  }

  @override
  Widget build(BuildContext context) {
     return Scaffold(
      backgroundColor: Colors.deepPurple,  
      body: Center(
        child: Image.asset(
          'assets/images/bg3.png', 
          fit: BoxFit.cover, 
          height: double.infinity,
          width: double.infinity,
        ),
     ),
);
  }
}