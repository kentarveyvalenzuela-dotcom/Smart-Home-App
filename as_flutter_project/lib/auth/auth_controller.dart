import 'package:flutter/foundation.dart';

import 'auth_repository.dart';
import 'auth_state.dart';

/// State boundary for email authentication and account recovery.
/// Google/2FA platform handling remains behind the existing compatibility
/// services until platform-specific client ownership is consolidated.
class AuthController {
  AuthController({AuthRepository? repository})
      : _repository = repository ?? AuthRepository(),
        state = ValueNotifier(const AuthState());

  final AuthRepository _repository;
  final ValueNotifier<AuthState> state;

  Future<Map<String, dynamic>?> register(
    String email,
    String password,
    String name,
  ) => _run(() => _repository.registerWithEmail(email, password, name));

  Future<Map<String, dynamic>?> signIn(
    String email,
    String password,
  ) => _run(() => _repository.signInWithEmail(email, password));

  Future<Map<String, dynamic>?> verifyEmail(String email, String code) =>
      _run(() => _repository.verifyEmailAddress(email, code));

  Future<Map<String, dynamic>?> requestPasswordReset(String email) =>
      _run(() => _repository.requestPasswordReset(email));

  Future<Map<String, dynamic>?> verifyResetToken(String token) =>
      _run(() => _repository.verifyResetToken(token));

  Future<Map<String, dynamic>?> resetPassword(
    String token,
    String password,
  ) => _run(() => _repository.resetPassword(token, password));

  Future<Map<String, dynamic>?> restoreSession() =>
      _run(() => _repository.getCurrentUser());

  Future<void> logout() async {
    await _repository.logout();
    state.value = const AuthState();
  }

  void dispose() => state.dispose();

  Future<Map<String, dynamic>?> _run(
    Future<Map<String, dynamic>?> Function() operation,
  ) async {
    state.value = state.value.copyWith(
      status: AuthStatus.loading,
      clearMessage: true,
    );
    try {
      final result = await operation();
      final success = result?['success'] == true;
      final status = !success
          ? AuthStatus.error
          : result?['requiresEmailVerification'] == true
              ? AuthStatus.emailVerificationRequired
              : result?['requires2FA'] == true
                  ? AuthStatus.twoFactorRequired
                  : AuthStatus.authenticated;
      state.value = AuthState(
        status: status,
        user: result?['user'] is Map
            ? Map<String, dynamic>.from(result!['user'] as Map)
            : null,
        message: result?['error']?.toString() ?? result?['message']?.toString(),
      );
      return result;
    } catch (error) {
      state.value = AuthState(
        status: AuthStatus.error,
        message: error.toString(),
      );
      rethrow;
    }
  }
}
