import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Stream to listen to auth state changes
  Stream<User?> get userChanges => _auth.authStateChanges();

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Enhanced email/password authentication with provider check and linking
  Future<UserCredential?> authenticateWithEmail(
    String email,
    String password,
  ) async {
    try {
      // Try to sign in
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        // Try to create account
        try {
          return await _auth.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );
        } on FirebaseAuthException catch (signUpError) {
          if (signUpError.code == 'email-already-in-use') {
            // Email exists, check providers
            final methods = await _auth.fetchSignInMethodsForEmail(email);
            if (methods.contains('google.com')) {
              throw Exception(
                'This email is already registered with Google. Please sign in with Google and link your email/password in profile settings.',
              );
            } else {
              throw Exception('An account already exists with this email.');
            }
          } else {
            rethrow;
          }
        }
      } else if (e.code == 'wrong-password') {
        throw Exception('Incorrect password.');
      } else if (e.code == 'email-already-in-use') {
        // Email exists, check providers
        final methods = await _auth.fetchSignInMethodsForEmail(email);
        if (methods.contains('google.com')) {
          throw Exception(
            'This email is already registered with Google. Please sign in with Google and link your email/password in profile settings.',
          );
        } else {
          throw Exception('An account already exists with this email.');
        }
      } else {
        rethrow;
      }
    }
  }

  // Google Sign In with linking logic
  Future<UserCredential?> signInWithGoogle({
    String? linkEmail,
    String? linkPassword,
  }) async {
    try {
      final GoogleAuthProvider googleProvider = GoogleAuthProvider();
      UserCredential userCredential;
      if (Platform.isAndroid || Platform.isIOS) {
        userCredential = await _auth.signInWithProvider(googleProvider);
      } else {
        userCredential = await _auth.signInWithPopup(googleProvider);
      }
      // If linkEmail and linkPassword are provided, try to link
      if (linkEmail != null && linkPassword != null) {
        final emailCred = EmailAuthProvider.credential(
          email: linkEmail,
          password: linkPassword,
        );
        try {
          await userCredential.user?.linkWithCredential(emailCred);
        } on FirebaseAuthException catch (e) {
          if (e.code != 'provider-already-linked') {
            throw Exception('Failed to link email/password: ${e.message}');
          }
        }
      }
      return userCredential;
    } catch (e) {
      print('Google Sign-In Error: $e');
      rethrow;
    }
  }

  // Apple Sign In using Firebase Auth
  Future<UserCredential?> signInWithApple() async {
    try {
      // Check if Apple Sign In is available
      if (!Platform.isIOS && !Platform.isMacOS) {
        throw Exception('Apple Sign In is only available on iOS and macOS');
      }

      // Create and configure an Apple provider
      final appleProvider = AppleAuthProvider();

      // Sign in with Apple using Firebase Auth
      return await _auth.signInWithProvider(appleProvider);
    } catch (e) {
      rethrow;
    }
  }

  // Logout
  Future<void> signOut() async {
    await _auth.signOut();
  }
}
