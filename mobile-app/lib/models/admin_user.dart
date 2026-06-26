/// A user row for the admin hierarchy + company-detail people tabs.
///
/// Re-platforms `src/pages/admin/Users.jsx` and the Operators/Drivers tabs of
/// `CompanyDetail.jsx`. Contract `AdminUserResponse`:
/// `{ id, email, name, role, companyId, companyName, locationId, active }`.
///
/// `role` is the DB vocabulary: `admin | manager | valet | driver`. The legacy
/// UI buckets these as Super Admins (admin), Company Owners (manager),
/// Operators (valet), Drivers (driver).
class AdminUser {
  const AdminUser({
    required this.id,
    required this.email,
    this.name,
    required this.role,
    this.companyId,
    this.companyName,
    this.locationId,
    this.active = true,
  });

  final String id;
  final String email;
  final String? name;
  final String role;
  final String? companyId;
  final String? companyName;
  final String? locationId;
  final bool active;

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    return AdminUser(
      id: (json['id'] ?? '').toString(),
      email: (json['email'] ?? '').toString().trim(),
      name: _nullable(json['name']),
      role: (json['role'] ?? '').toString().trim(),
      companyId: _nullable(json['companyId']),
      companyName: _nullable(json['companyName']),
      locationId: _nullable(json['locationId']),
      active: json['active'] == null ? true : json['active'] == true,
    );
  }

  bool get isAdmin => role == 'admin';
  bool get isManager => role == 'manager';
  bool get isOperator => role == 'valet';
  bool get isDriver => role == 'driver';

  String get displayName =>
      (name != null && name!.trim().isNotEmpty) ? name!.trim() : email;

  /// Human label for the DB role, in the legacy UI vocabulary.
  String get roleLabel => switch (role) {
        'admin' => 'Super Admin',
        'manager' => 'Company Owner',
        'valet' => 'Operator',
        'driver' => 'Driver',
        _ => role,
      };

  static String? _nullable(Object? v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }
}

/// Body for `POST /api/companies/{id}/staff`. `role` MUST be `valet` (operator)
/// or `driver`; the backend rejects manager/admin (400 INVALID_STAFF_ROLE).
class CreateStaffInput {
  const CreateStaffInput({
    required this.email,
    required this.password,
    required this.name,
    required this.role,
    this.locationId,
  });

  final String email;
  final String password;
  final String name;

  /// `valet` | `driver`.
  final String role;
  final String? locationId;

  Map<String, dynamic> toJson() => {
        'email': email.trim(),
        'password': password,
        'name': name.trim(),
        'role': role,
        if (locationId != null && locationId!.isNotEmpty)
          'locationId': locationId,
      };
}
