/// A company (valet operator) from `GET /api/companies` (AUTH service).
///
/// Re-platforms the legacy `valet_companies` row surfaced in
/// `src/pages/admin/Companies.jsx`. admin sees all; manager sees only its own.
/// Contract shape (camelCase): `{ id, companyName, ownerName, phone, email,
/// createdAt }`. Optionals are tolerated as null.
class Company {
  const Company({
    required this.id,
    required this.companyName,
    this.ownerName,
    this.phone,
    this.email,
    this.createdAt,
  });

  final String id;
  final String companyName;
  final String? ownerName;
  final String? phone;
  final String? email;
  final String? createdAt;

  factory Company.fromJson(Map<String, dynamic> json) {
    return Company(
      id: (json['id'] ?? '').toString(),
      companyName: (json['companyName'] ?? '').toString().trim(),
      ownerName: _nullable(json['ownerName']),
      phone: _nullable(json['phone']),
      email: _nullable(json['email']),
      createdAt: _nullable(json['createdAt']),
    );
  }

  /// Display name, falling back to the email/owner if the name is blank.
  String get displayName => companyName.isNotEmpty
      ? companyName
      : (ownerName ?? email ?? 'Company');

  static String? _nullable(Object? v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }
}

/// Body for `POST /api/companies` (ADMIN only) — provisions the company plus its
/// owner login in one transactional call (mirrors `createCompanyWithOwner`).
class CreateCompanyInput {
  const CreateCompanyInput({
    required this.companyName,
    this.ownerName,
    this.phone,
    this.email,
    required this.password,
  });

  final String companyName;
  final String? ownerName;
  final String? phone;
  final String? email;
  final String password;

  Map<String, dynamic> toJson() {
    String? trimOrNull(String? v) {
      final s = v?.trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return {
      'companyName': companyName.trim(),
      if (trimOrNull(ownerName) != null) 'ownerName': trimOrNull(ownerName),
      if (trimOrNull(phone) != null) 'phone': trimOrNull(phone),
      'email': (email ?? '').trim(),
      'password': password,
    };
  }
}
