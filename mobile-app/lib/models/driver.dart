/// A selectable driver from `GET /drivers` (AUTH service), scoped server-side
/// to the operator's own company.
///
/// Contract shape (EXACT keys): `{ id, name, email }`. Only what the assign
/// picker needs — no role, tenancy, or credential fields are carried.
class Driver {
  const Driver({
    required this.id,
    required this.name,
    required this.email,
  });

  final String id;
  final String name;
  final String email;

  factory Driver.fromJson(Map<String, dynamic> json) {
    return Driver(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString().trim(),
      email: (json['email'] ?? '').toString().trim(),
    );
  }

  /// Name when present, otherwise the email (mirrors AuthUser.displayName).
  String get displayName => name.isNotEmpty ? name : email;
}
