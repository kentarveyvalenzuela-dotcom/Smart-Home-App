import 'package:flutter/foundation.dart';

enum AuthStatus {
  unauthenticated,
  loading,
  authenticated,
  emailVerificationRequired,
  twoFactorRequired,
  error,
}

@immutable
class AuthState {
  const AuthState({
    this.status = AuthStatus.unauthenticated,
    this.user,
    this.message,
  });

  final AuthStatus status;
  final Map<String, dynamic>? user;
  final String? message;

  AuthState copyWith({
    AuthStatus? status,
    Map<String, dynamic>? user,
    String? message,
    bool clearUser = false,
    bool clearMessage = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: clearUser ? null : user ?? this.user,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}
