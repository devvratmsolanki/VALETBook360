import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persisted theme preference (light / dark / follow-system).
///
/// Default on first launch is LIGHT — the logbook360 default. The user's last
/// choice is persisted via flutter_secure_storage (same store family as the
/// auth TokenStore) under [_kThemeMode]. We load it synchronously-ish at boot
/// (async read, then a state update) so the app honours the saved preference.
class ThemeStore {
  ThemeStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _storage;
  static const _kThemeMode = 'valet.themeMode'; // values: system | light | dark
  static const _readTimeout = Duration(seconds: 3);

  Future<ThemeMode> read() async {
    try {
      final raw = await _storage.read(key: _kThemeMode).timeout(_readTimeout);
      switch (raw) {
        case 'dark':
          return ThemeMode.dark;
        case 'system':
          return ThemeMode.system;
        case 'light':
          return ThemeMode.light;
        default:
          return ThemeMode.light; // first launch / unreadable → light default
      }
    } catch (_) {
      return ThemeMode.light;
    }
  }

  Future<void> write(ThemeMode mode) async {
    final value = switch (mode) {
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
      ThemeMode.light => 'light',
    };
    try {
      await _storage.write(key: _kThemeMode, value: value);
    } catch (_) {
      // Persistence is best-effort; a failed write must not crash the toggle.
    }
  }
}

/// Drives [MaterialApp.themeMode]. Starts at light, then restores the saved
/// preference on construction. [toggle] flips light↔dark (the in-app-bar
/// control); [setMode] supports an explicit 3-way choice (e.g. from Settings).
class ThemeController extends StateNotifier<ThemeMode> {
  ThemeController(this._store) : super(ThemeMode.light) {
    _restore();
  }

  final ThemeStore _store;

  Future<void> _restore() async {
    state = await _store.read();
  }

  /// Resolve the effective brightness for the current [state], honouring the
  /// platform brightness when in system mode. Callers pass the platform value
  /// (from MediaQuery) so this stays pure.
  Brightness resolve(Brightness platform) => switch (state) {
        ThemeMode.dark => Brightness.dark,
        ThemeMode.light => Brightness.light,
        ThemeMode.system => platform,
      };

  /// In-app-bar sun/moon control: flips between explicit light and dark.
  /// (If currently following system, the flip resolves to an explicit mode so
  /// the tap always produces a visible, predictable change.)
  void toggle(Brightness platform) {
    final effective = resolve(platform);
    setMode(effective == Brightness.dark ? ThemeMode.light : ThemeMode.dark);
  }

  void setMode(ThemeMode mode) {
    if (mode == state) return;
    state = mode;
    _store.write(mode);
  }
}
