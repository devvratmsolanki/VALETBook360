import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../models/company.dart';

enum CompaniesStatus { loading, ready, empty, error }

/// State for the admin Companies list (`GET /api/companies`). admin sees all;
/// manager sees only its own (server-scoped to a single-element list). Mirrors
/// FloorState/DriversState — a status enum, the payload, and an optional error.
@immutable
class CompaniesState {
  const CompaniesState({
    this.status = CompaniesStatus.loading,
    this.companies = const [],
    this.error,
  });

  final CompaniesStatus status;
  final List<Company> companies;
  final String? error;

  CompaniesState copyWith({
    CompaniesStatus? status,
    List<Company>? companies,
    String? error,
    bool clearError = false,
  }) {
    return CompaniesState(
      status: status ?? this.status,
      companies: companies ?? this.companies,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Loads + creates companies. Create is ADMIN-only on the backend; a manager
/// calling it gets a friendly 403 surfaced via [createError].
class CompaniesController extends StateNotifier<CompaniesState> {
  CompaniesController({required ApiClient client})
      : _client = client,
        super(const CompaniesState()) {
    load();
  }

  final ApiClient _client;

  /// The error from the last failed create action (distinct from the list-load
  /// error so a form can show it without clobbering the list).
  String? createError;

  Future<void> load() async {
    state = state.copyWith(status: CompaniesStatus.loading, clearError: true);
    try {
      final companies = await _client.fetchCompanies();
      state = state.copyWith(
        status:
            companies.isEmpty ? CompaniesStatus.empty : CompaniesStatus.ready,
        companies: companies,
        clearError: true,
      );
    } on ApiException catch (e) {
      if (e.isUnauthorized) return; // global 401 bounce owns it.
      state = state.copyWith(status: CompaniesStatus.error, error: e.message);
    } catch (_) {
      state = state.copyWith(
        status: CompaniesStatus.error,
        error: 'Could not load companies. Please try again.',
      );
    }
  }

  /// Create a company + its owner login (ADMIN only). Returns the company on
  /// success, or null on failure (caller reads [createError]).
  Future<Company?> create(CreateCompanyInput input) async {
    createError = null;
    try {
      final company = await _client.createCompany(input);
      // Refetch from the source of truth so the list stays authoritative.
      await load();
      return company;
    } on ApiException catch (e) {
      createError = e.message;
      return null;
    } catch (_) {
      createError = 'Could not create the company. Please try again.';
      return null;
    }
  }
}
