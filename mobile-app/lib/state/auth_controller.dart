import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../api/token_store.dart';
import '../models/auth_user.dart';

enum AuthStatus { unknown, unauthenticated, authenticating, authenticated }

@immutable
class AuthState {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.error,
  });

  final AuthStatus status;
  final AuthUser? user;

  /// Set when a login attempt fails (drives the login error banner).
  final String? error;

  bool get isAuthed => status == AuthStatus.authenticated && user != null;
  bool get isBusy => status == AuthStatus.authenticating;

  AuthState copyWith({
    AuthStatus? status,
    AuthUser? user,
    String? error,
    bool clearError = false,
    bool clearUser = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: clearUser ? null : (user ?? this.user),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AuthController extends StateNotifier<AuthState> {
  AuthController({required ApiClient client, required TokenStore tokens})
      : _client = client,
        _tokens = tokens,
        super(const AuthState()) {
    _restore();
  }

  final ApiClient _client;
  final TokenStore _tokens;

  /// On boot, restore a stored session so the user skips login.
  Future<void> _restore() async {
    final token = await _tokens.accessToken;
    final user = await _tokens.readUser();
    if (token != null && token.isNotEmpty && user != null) {
      state = AuthState(status: AuthStatus.authenticated, user: user);
    } else {
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(
      status: AuthStatus.authenticating,
      clearError: true,
    );
    try {
      final session = await _client.login(email.trim(), password);
      await _tokens.save(session);
      state = AuthState(
        status: AuthStatus.authenticated,
        user: session.user,
      );
      return true;
    } on ApiException catch (e) {
      state = AuthState(
        status: AuthStatus.unauthenticated,
        error: e.message,
      );
      return false;
    } catch (_) {
      state = const AuthState(
        status: AuthStatus.unauthenticated,
        error: 'Unexpected error. Please try again.',
      );
      return false;
    }
  }

  /// Triggered by a 401 on an authed call — wipe and bounce to login.
  Future<void> onExpired() async {
    if (state.status == AuthStatus.unauthenticated) return;
    await _tokens.clear();
    state = const AuthState(
      status: AuthStatus.unauthenticated,
      error: 'Your session has expired. Please sign in again.',
    );
  }

  Future<void> logout() async {
    await _tokens.clear();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  void clearError() {
    if (state.error != null) state = state.copyWith(clearError: true);
  }
}
