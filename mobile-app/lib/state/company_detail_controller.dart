import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../models/admin_location.dart';
import '../models/admin_user.dart';
import '../models/company.dart';

enum DetailStatus { loading, ready, error }

/// State for one company's drill-down (`CompanyDetail.jsx` re-platform): the
/// overview plus the Locations / Operators / Drivers tabs. Each collection
/// loads in one pass; create actions refetch the affected slice.
@immutable
class CompanyDetailState {
  const CompanyDetailState({
    this.status = DetailStatus.loading,
    this.company,
    this.locations = const [],
    this.operators = const [],
    this.drivers = const [],
    this.error,
  });

  final DetailStatus status;
  final Company? company;
  final List<AdminLocation> locations;

  /// `valet` users.
  final List<AdminUser> operators;

  /// `driver` users.
  final List<AdminUser> drivers;
  final String? error;

  CompanyDetailState copyWith({
    DetailStatus? status,
    Company? company,
    List<AdminLocation>? locations,
    List<AdminUser>? operators,
    List<AdminUser>? drivers,
    String? error,
    bool clearError = false,
  }) {
    return CompanyDetailState(
      status: status ?? this.status,
      company: company ?? this.company,
      locations: locations ?? this.locations,
      operators: operators ?? this.operators,
      drivers: drivers ?? this.drivers,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Drill-down controller for a single company. Loads the overview + all three
/// people/location collections, and exposes create actions for each. Mirrors
/// the FloorController shape: a status enum, optimistic-or-refetch creates, and
/// a `createError` slot the forms read on failure.
class CompanyDetailController extends StateNotifier<CompanyDetailState> {
  CompanyDetailController({required ApiClient client, required this.companyId})
      : _client = client,
        super(const CompanyDetailState()) {
    load();
  }

  final ApiClient _client;
  final String companyId;

  /// Last create-action error (location/operator/driver), surfaced in the form.
  String? createError;

  Future<void> load() async {
    state = state.copyWith(status: DetailStatus.loading, clearError: true);
    try {
      final results = await Future.wait([
        _client.fetchCompany(companyId),
        _client.fetchCompanyLocations(companyId),
        _client.fetchCompanyUsers(companyId, role: 'valet'),
        _client.fetchCompanyUsers(companyId, role: 'driver'),
      ]);
      state = CompanyDetailState(
        status: DetailStatus.ready,
        company: results[0] as Company,
        locations: results[1] as List<AdminLocation>,
        operators: results[2] as List<AdminUser>,
        drivers: results[3] as List<AdminUser>,
      );
    } on ApiException catch (e) {
      if (e.isUnauthorized) return; // global 401 bounce owns it.
      state = state.copyWith(status: DetailStatus.error, error: e.message);
    } catch (_) {
      state = state.copyWith(
        status: DetailStatus.error,
        error: 'Could not load this company. Please try again.',
      );
    }
  }

  Future<void> _refreshLocations() async {
    final locations = await _client.fetchCompanyLocations(companyId);
    state = state.copyWith(locations: locations);
  }

  Future<void> _refreshOperators() async {
    final operators =
        await _client.fetchCompanyUsers(companyId, role: 'valet');
    state = state.copyWith(operators: operators);
  }

  Future<void> _refreshDrivers() async {
    final drivers = await _client.fetchCompanyUsers(companyId, role: 'driver');
    state = state.copyWith(drivers: drivers);
  }

  /// Add a location. Returns true on success; false + [createError] on failure.
  Future<bool> addLocation(CreateLocationInput input) async {
    createError = null;
    try {
      await _client.createLocation(companyId, input);
      await _refreshLocations();
      return true;
    } on ApiException catch (e) {
      createError = e.message;
      return false;
    } catch (_) {
      createError = 'Could not add the location. Please try again.';
      return false;
    }
  }

  /// Edit an existing location.
  Future<bool> editLocation(
    String locationId,
    CreateLocationInput input,
  ) async {
    createError = null;
    try {
      await _client.updateLocation(locationId, input);
      await _refreshLocations();
      return true;
    } on ApiException catch (e) {
      createError = e.message;
      return false;
    } catch (_) {
      createError = 'Could not save the location. Please try again.';
      return false;
    }
  }

  /// Add a staff member (`valet` operator or `driver`) and refresh that slice.
  Future<bool> addStaff(CreateStaffInput input) async {
    createError = null;
    try {
      await _client.createStaff(companyId, input);
      if (input.role == 'driver') {
        await _refreshDrivers();
      } else {
        await _refreshOperators();
      }
      return true;
    } on ApiException catch (e) {
      createError = e.message;
      return false;
    } catch (_) {
      createError = 'Could not add the staff member. Please try again.';
      return false;
    }
  }

  /// Activate/deactivate a staff (operator/driver) account and refresh both
  /// people slices (the user could be in either). Returns true on success.
  Future<bool> setUserActive(String userId, bool active, {required bool isDriver}) async {
    createError = null;
    try {
      await _client.setUserActive(userId, active);
      if (isDriver) {
        await _refreshDrivers();
      } else {
        await _refreshOperators();
      }
      return true;
    } on ApiException catch (e) {
      createError = e.message;
      return false;
    } catch (_) {
      createError = 'Could not update the account. Please try again.';
      return false;
    }
  }

  /// Delete a staff (operator/driver) account and refresh that slice.
  Future<bool> deleteUser(String userId, {required bool isDriver}) async {
    createError = null;
    try {
      await _client.deleteUser(userId);
      if (isDriver) {
        await _refreshDrivers();
      } else {
        await _refreshOperators();
      }
      return true;
    } on ApiException catch (e) {
      createError = e.message;
      return false;
    } catch (_) {
      createError = 'Could not delete the account. Please try again.';
      return false;
    }
  }
}
