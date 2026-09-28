import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'config_service.dart';

/// Google Sign-In with 2FA Authentication Service
/// Integrates with backend for two-factor authentication
class GoogleSignIn2FAService {
  static final GoogleSignIn2FAService _instance = GoogleSignIn2FAService._internal();
  factory GoogleSignIn2FAService() => _instance;
  GoogleSignIn2FAService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  // Backend URL - Update this to your backend server
  String backendUrl = ConfigService().backendUrl;

  User? get currentUser => _auth.currentUser;
  bool get isSignedIn => _auth.currentUser != null;

  /// Step 1: Sign in with Google
  /// Returns: Map with 'requires2FA' and 'email' if 2FA is needed
  Future<Map<String, dynamic>> signInWithGoogle() async {
    try {
      // First, sign out to clear any stale tokens
      await _googleSignIn.signOut();

      // Trigger Google Sign-In flow (fresh)
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        // User canceled the sign-in
        return {'success': false, 'message': 'Sign-in canceled'};
      }

      // Obtain FRESH auth details
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // Verify we have tokens
      if (googleAuth.idToken == null) {
        debugPrint('❌ No ID token received from Google');
        return {'success': false, 'message': 'Failed to get authentication token'};
      }

      // Create Firebase credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase
      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      
      // Get FRESH Firebase ID token (force refresh)
      final String? idToken = await userCredential.user?.getIdToken(true);

      if (idToken == null) {
        throw Exception('Failed to get ID token');
      }

      debugPrint('✅ Got fresh Firebase ID token (length: ${idToken.length})');

      // Send to backend to check if 2FA is required
      final response = await http.post(
        Uri.parse('$backendUrl/auth/google-signin'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'id_token': idToken}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['requires_2fa'] == true) {
          // 2FA required
          return {
            'success': true,
            'requires2FA': true,
            'email': userCredential.user?.email,
            'message': data['message'] ?? '2FA code sent to your email'
          };
        } else {
          // No 2FA required, sign-in complete
          return {
            'success': true,
            'requires2FA': false,
            'user': userCredential.user,
            'message': 'Sign-in successful'
          };
        }
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Backend error');
      }
      
    } catch (e) {
      debugPrint('❌ Google Sign-In error: $e');

      // If token is stale, try to sign out and suggest retry
      if (e.toString().contains('stale') || e.toString().contains('expired')) {
        await _googleSignIn.signOut();
        await _auth.signOut();
        return {
          'success': false,
          'message': 'Session expired. Please try again.'
        };
      }

      return {
        'success': false,
        'message': 'Sign-in failed: ${e.toString()}'
      };
    }
  }

  /// Step 2: Verify 2FA code
  Future<Map<String, dynamic>> verify2FACode(String email, String code) async {
    try {
      final response = await http.post(
        Uri.parse('$backendUrl/auth/verify-2fa'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email,
          'code': code,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Sign in with custom token from backend
        if (data['token'] != null) {
          await _auth.signInWithCustomToken(data['token']);
        }
        
        return {
          'success': true,
          'user': _auth.currentUser,
          'message': data['message'] ?? '2FA verification successful'
        };
      } else {
        final error = json.decode(response.body);
        return {
          'success': false,
          'message': error['detail'] ?? 'Invalid 2FA code'
        };
      }
      
    } catch (e) {
      debugPrint('❌ 2FA verification error: $e');
      return {
        'success': false,
        'message': 'Verification failed: ${e.toString()}'
      };
    }
  }

  /// Request new 2FA code
  Future<Map<String, dynamic>> request2FACode(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$backendUrl/auth/request-2fa'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email,
          'method': 'email',
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'message': data['message'] ?? '2FA code sent'
        };
      } else {
        final error = json.decode(response.body);
        return {
          'success': false,
          'message': error['detail'] ?? 'Failed to send code'
        };
      }
      
    } catch (e) {
      debugPrint('❌ Request 2FA error: $e');
      return {
        'success': false,
        'message': 'Failed to request code: ${e.toString()}'
      };
    }
  }

  /// Enable 2FA for current user
  Future<bool> enable2FA() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final idToken = await user.getIdToken();
      
      final response = await http.post(
        Uri.parse('$backendUrl/auth/enable-2fa'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': user.email,
          'id_token': idToken,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ Enable 2FA error: $e');
      return false;
    }
  }

  /// Disable 2FA for current user
  Future<bool> disable2FA() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final idToken = await user.getIdToken();
      
      final response = await http.post(
        Uri.parse('$backendUrl/auth/disable-2fa'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': user.email,
          'id_token': idToken,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ Disable 2FA error: $e');
      return false;
    }
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      await _auth.signOut();
      debugPrint('✅ Signed out successfully');
    } catch (e) {
      debugPrint('❌ Sign out error: $e');
    }
  }

  /// Get user profile from backend
  Future<Map<String, dynamic>?> getUserProfile() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      final idToken = await user.getIdToken();
      
      final response = await http.get(
        Uri.parse('$backendUrl/auth/user/${user.uid}?id_token=$idToken'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['user'];
      }
      return null;
    } catch (e) {
      debugPrint('❌ Get profile error: $e');
      return null;
    }
  }
}
