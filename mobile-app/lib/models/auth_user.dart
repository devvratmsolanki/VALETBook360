import 'package:flutter/foundation.dart';

/// The authenticated user returned by `POST /auth/login`.
///
/// Contract shape (camelCase on the wire, per doc §10.7). Unknown/optional
/// fields are tolerated so a backend that returns extra keys won't break the
/// client, and missing optionals degrade gracefully.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.role,
    this.name,
    this.companyId,
    this.locationId,
  });

  final String id;
  final String email;

  /// 'admin' | 'company' | 'valet' | 'driver' (UI role vocabulary).
  final String role;
  final String? name;
  final String? companyId;
  final String? locationId;

  /// The valid DB role vocabulary. A user whose role is missing or outside this
  /// set is NOT silently treated as a driver — the auth layer rejects it.
  static const Set<String> knownRoles = {
    'admin', 'manager', 'valet', 'driver', 'facility_owner'
  };

  /// Whether [role] is one the router knows how to home. Callers (login /
  /// session-restore) must reject a user for which this is false rather than
  /// routing them to a default panel.
  bool get hasKnownRole => knownRoles.contains(role);

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    // Do NOT default a missing/unknown role to 'driver' — that silently routes
    // an unrecognised account to the driver panel. Keep the raw value (or '')
    // and let the auth layer reject it via [hasKnownRole].
    final rawRole = (json['role'] ?? '').toString();
    if (!knownRoles.contains(rawRole)) {
      if (kDebugMode) {
        debugPrint(
          '[AuthUser] unrecognised role "${json['role']}" for '
          'user ${json['id'] ?? json['userId']} — refusing to default to driver.',
        );
      }
    }
    return AuthUser(
      id: (json['id'] ?? json['userId'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      role: rawRole,
      name: json['name']?.toString(),
      companyId: json['companyId']?.toString(),
      locationId: json['locationId']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'role': role,
        if (name != null) 'name': name,
        if (companyId != null) 'companyId': companyId,
        if (locationId != null) 'locationId': locationId,
      };

  bool get isDriver => role == 'driver';
  bool get isFacilityOwner => role == 'facility_owner';

  /// Super admin — sees every company (no company scope of its own).
  bool get isAdmin => role == 'admin';

  /// Company owner. The DB stores this as `manager`; the legacy UI calls the
  /// role "company". Scoped to its own company server-side.
  bool get isManager => role == 'manager';
  bool get isCompany => isManager;

  /// The operator floor is run by valet only — admin/manager land on the admin
  /// panel instead (driver lands on the driver stack).
  bool get isOperator => role == 'valet';

  /// admin + manager run the company/admin hierarchy panel.
  bool get isAdminPanel => isAdmin || isManager;

  /// Home route for this role, used by the post-login redirect.
  ///   admin → /admin · manager (company owner) → /company ·
  ///   valet → /operator · driver → /driver · facility_owner → /facility-owner
  String get homeRoute {
    if (isDriver) return '/driver';
    if (isFacilityOwner) return '/facility-owner';
    if (isManager) return '/company';
    if (isAdmin) return '/admin';
    return '/operator';
  }

  String get displayName =>
      (name != null && name!.trim().isNotEmpty) ? name!.trim() : email;
}

/// The full `POST /auth/login` 200 response: tokens + user.
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final AuthUser user;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    // Tolerate either a flat shape or a nested { tokens: {...}, user: {...} }.
    final tokens = json['tokens'] is Map<String, dynamic>
        ? json['tokens'] as Map<String, dynamic>
        : json;
    final userJson = json['user'] is Map<String, dynamic>
        ? json['user'] as Map<String, dynamic>
        : json;

    return AuthSession(
      accessToken:
          (tokens['accessToken'] ?? tokens['access_token'] ?? '').toString(),
      refreshToken:
          (tokens['refreshToken'] ?? tokens['refresh_token'] ?? '').toString(),
      user: AuthUser.fromJson(userJson),
    );
  }
}
