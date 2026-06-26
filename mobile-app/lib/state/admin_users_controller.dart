import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../models/admin_user.dart';

enum AdminUsersStatus { loading, ready, empty, error }

/// State for the admin hierarchical user view (`GET /api/admin/users`,
/// ADMIN only). Re-platforms `Users.jsx` — Super Admins at the top, then one
/// collapsible card per company bucketing Owners / Operators / Drivers.
@immutable
class AdminUsersState {
  const AdminUsersState({
    this.status = AdminUsersStatus.loading,
    this.users = const [],
    this.error,
  });

  final AdminUsersStatus status;
  final List<AdminUser> users;
  final String? error;

  AdminUsersState copyWith({
    AdminUsersStatus? status,
    List<AdminUser>? users,
    String? error,
    bool clearError = false,
  }) {
    return AdminUsersState(
      status: status ?? this.status,
      users: users ?? this.users,
      error: clearError ? null : (error ?? this.error),
    );
  }

  /// Super admins (no company scope).
  List<AdminUser> get superAdmins =>
      users.where((u) => u.isAdmin).toList(growable: false);

  /// Company-scoped users grouped by company name. Each group is keyed by the
  /// company display name and bucketed by role in the UI.
  Map<String, List<AdminUser>> get byCompany {
    final map = <String, List<AdminUser>>{};
    for (final u in users) {
      if (u.isAdmin) continue;
      final key = u.companyName ?? 'Unassigned';
      (map[key] ??= <AdminUser>[]).add(u);
    }
    return map;
  }
}

/// Loads every user for the admin hierarchy. Read-only here — staff/owner
/// creation lives in the company-detail and companies flows.
class AdminUsersController extends StateNotifier<AdminUsersState> {
  AdminUsersController({required ApiClient client})
      : _client = client,
        super(const AdminUsersState()) {
    load();
  }

  final ApiClient _client;

  Future<void> load() async {
    state = state.copyWith(status: AdminUsersStatus.loading, clearError: true);
    try {
      final users = await _client.fetchAllUsers();
      state = state.copyWith(
        status:
            users.isEmpty ? AdminUsersStatus.empty : AdminUsersStatus.ready,
        users: users,
        clearError: true,
      );
    } on ApiException catch (e) {
      if (e.isUnauthorized) return; // global 401 bounce owns it.
      state = state.copyWith(status: AdminUsersStatus.error, error: e.message);
    } catch (_) {
      state = state.copyWith(
        status: AdminUsersStatus.error,
        error: 'Could not load users. Please try again.',
      );
    }
  }
}
