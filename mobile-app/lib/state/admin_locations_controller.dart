import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../models/admin_location.dart';

enum AdminLocationsStatus { loading, ready, empty, error }

/// State for the admin all-locations view (`GET /api/admin/locations`,
/// ADMIN only). Re-platforms `AdminLocations.jsx` — every location across every
/// company, grouped by company in the UI. Each row carries `companyName`.
@immutable
class AdminLocationsState {
  const AdminLocationsState({
    this.status = AdminLocationsStatus.loading,
    this.locations = const [],
    this.error,
  });

  final AdminLocationsStatus status;
  final List<AdminLocation> locations;
  final String? error;

  AdminLocationsState copyWith({
    AdminLocationsStatus? status,
    List<AdminLocation>? locations,
    String? error,
    bool clearError = false,
  }) {
    return AdminLocationsState(
      status: status ?? this.status,
      locations: locations ?? this.locations,
      error: clearError ? null : (error ?? this.error),
    );
  }

  /// Locations grouped by company name, for the grouped list rendering.
  Map<String, List<AdminLocation>> get byCompany {
    final map = <String, List<AdminLocation>>{};
    for (final loc in locations) {
      final key = (loc.companyName ?? 'Unassigned');
      (map[key] ??= <AdminLocation>[]).add(loc);
    }
    return map;
  }
}

/// Loads + creates/edits locations across all companies. create/edit refetch
/// the full flat list (it's small and changes rarely).
class AdminLocationsController extends StateNotifier<AdminLocationsState> {
  AdminLocationsController({required ApiClient client})
      : _client = client,
        super(const AdminLocationsState()) {
    load();
  }

  final ApiClient _client;

  String? createError;

  Future<void> load() async {
    state =
        state.copyWith(status: AdminLocationsStatus.loading, clearError: true);
    try {
      final locations = await _client.fetchAllLocations();
      state = state.copyWith(
        status: locations.isEmpty
            ? AdminLocationsStatus.empty
            : AdminLocationsStatus.ready,
        locations: locations,
        clearError: true,
      );
    } on ApiException catch (e) {
      if (e.isUnauthorized) return; // global 401 bounce owns it.
      state =
          state.copyWith(status: AdminLocationsStatus.error, error: e.message);
    } catch (_) {
      state = state.copyWith(
        status: AdminLocationsStatus.error,
        error: 'Could not load locations. Please try again.',
      );
    }
  }

  /// Add a location under a given company, then refresh the flat list.
  Future<bool> addLocation(
    String companyId,
    CreateLocationInput input,
  ) async {
    createError = null;
    try {
      await _client.createLocation(companyId, input);
      await load();
      return true;
    } on ApiException catch (e) {
      createError = e.message;
      return false;
    } catch (_) {
      createError = 'Could not add the location. Please try again.';
      return false;
    }
  }

  /// Edit an existing location, then refresh the flat list.
  Future<bool> editLocation(
    String locationId,
    CreateLocationInput input,
  ) async {
    createError = null;
    try {
      await _client.updateLocation(locationId, input);
      await load();
      return true;
    } on ApiException catch (e) {
      createError = e.message;
      return false;
    } catch (_) {
      createError = 'Could not save the location. Please try again.';
      return false;
    }
  }
}
