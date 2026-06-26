import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../models/driver.dart';

enum DriversStatus { idle, loading, ready, empty, error }

/// State for the operator's assign-driver picker: the company's drivers loaded
/// from `GET /drivers` (AUTH). Mirrors the FloorState/MissionsState shape — a
/// status enum plus the payload and an optional error message.
@immutable
class DriversState {
  const DriversState({
    this.status = DriversStatus.idle,
    this.drivers = const [],
    this.error,
  });

  final DriversStatus status;
  final List<Driver> drivers;
  final String? error;

  DriversState copyWith({
    DriversStatus? status,
    List<Driver>? drivers,
    String? error,
    bool clearError = false,
  }) {
    return DriversState(
      status: status ?? this.status,
      drivers: drivers ?? this.drivers,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Loads the company-scoped driver list for the assign picker. The list is
/// small and changes rarely, so we fetch on demand (when the picker opens) and
/// cache the result; callers can force a refresh via [load].
class DriversController extends StateNotifier<DriversState> {
  DriversController({required ApiClient client})
      : _client = client,
        super(const DriversState());

  final ApiClient _client;

  /// Fetch the company's drivers. A no-op while already loading. Surfaces an
  /// `empty` status when the company has no drivers so the UI can show a
  /// dedicated empty state instead of a blank list.
  Future<void> load() async {
    if (state.status == DriversStatus.loading) return;
    state = state.copyWith(status: DriversStatus.loading, clearError: true);
    try {
      final drivers = await _client.fetchDrivers();
      state = state.copyWith(
        status: drivers.isEmpty ? DriversStatus.empty : DriversStatus.ready,
        drivers: drivers,
        clearError: true,
      );
    } on ApiException catch (e) {
      if (e.isUnauthorized) return; // global 401 bounce handles it.
      state = state.copyWith(status: DriversStatus.error, error: e.message);
    } catch (_) {
      state = state.copyWith(
        status: DriversStatus.error,
        error: 'Could not load drivers. Please try again.',
      );
    }
  }
}
