import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  void _authenticate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService().signIn(_emailController.text.trim(), _passwordController.text.trim());
    } catch (e) {
      // If sign in fails, try to register
      try {
        await AuthService().signUp(_emailController.text.trim(), _passwordController.text.trim());
      } catch (e) {
        setState(() {
          _error = 'Authentication failed. Please check your credentials or try again.';
        });
      }
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign In or Register')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _authenticate,
                child: _loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
