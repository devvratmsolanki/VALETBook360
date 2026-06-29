import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/auth_user.dart';

/// Secure persistence for the JWT pair + cached user (doc §9.1:
/// flutter_secure_storage for tokens). Session is intentionally NOT in plain
/// shared-prefs — mirrors the web app keeping auth out of localStorage.
class TokenStore {
  TokenStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                // unlocked_this_device: tokens are readable only while the device
                // is actively unlocked, and are never migrated to a new device or
                // included in iCloud/iTunes backups. first_unlock left them
                // readable by background processes while the screen was locked.
                accessibility: KeychainAccessibility.unlocked_this_device,
              ),
            );

  final FlutterSecureStorage _storage;

  static const _kAccess = 'valet.accessToken';
  static const _kRefresh = 'valet.refreshToken';
  static const _kUser = 'valet.user';

  /// In-memory mirror of the session, populated on [save] and lazily on the
  /// first read. The HTTP bearer interceptor and the realtime connect both hit
  /// [accessToken] on every request; on web `flutter_secure_storage` reads can
  /// stall (SubtleCrypto / storage quirks), which would hang every API call
  /// behind the interceptor. Serving the hot path from memory makes auth
  /// reads instant and immune to that, while storage stays the source of
  /// truth across reloads.
  String? _accessCache;
  String? _refreshCache;
  AuthUser? _userCache;

  /// Hard ceiling on any secure-storage read so a stalled web read can never
  /// hang the app — we fall back to the in-memory value (or null) instead.
  static const _readTimeout = Duration(seconds: 3);

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key).timeout(_readTimeout);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(AuthSession session) async {
    // Memory first so the very next request is authenticated even if the
    // (awaited) writes below are slow OR fail on web.
    _accessCache = session.accessToken;
    _refreshCache = session.refreshToken;
    _userCache = session.user;
    // Best-effort persistence. `flutter_secure_storage` on web relies on
    // SubtleCrypto, which the browser only exposes in a SECURE CONTEXT (HTTPS
    // or localhost). Served over plain http on a LAN IP (e.g. phone testing),
    // the write throws — but the in-memory cache above already holds the
    // session, so login must NOT fail just because we couldn't persist it.
    // Persistence simply degrades to "this tab only" until the app is on HTTPS.
    try {
      await Future.wait([
        _storage.write(key: _kAccess, value: session.accessToken),
        _storage.write(key: _kRefresh, value: session.refreshToken),
        _storage.write(key: _kUser, value: jsonEncode(session.user.toJson())),
      ]);
    } catch (_) {
      // Ignore — memory cache is the session's source of truth.
    }
  }

  Future<String?> get accessToken async =>
      _accessCache ??= await _read(_kAccess);

  Future<String?> get refreshToken async =>
      _refreshCache ??= await _read(_kRefresh);

  Future<AuthUser?> readUser() async {
    if (_userCache != null) return _userCache;
    final raw = await _read(_kUser);
    if (raw == null || raw.isEmpty) return null;
    try {
      return _userCache =
          AuthUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    _accessCache = null;
    _refreshCache = null;
    _userCache = null;
    // Best-effort (see note in [save]) — clearing the in-memory cache above is
    // what actually signs the user out for this session.
    try {
      await Future.wait([
        _storage.delete(key: _kAccess),
        _storage.delete(key: _kRefresh),
        _storage.delete(key: _kUser),
      ]);
    } catch (_) {
      // Ignore — storage may be unavailable in a non-secure web context.
    }
  }
}
