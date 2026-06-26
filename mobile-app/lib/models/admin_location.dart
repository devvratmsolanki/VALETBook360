/// A location from the company-detail or admin-locations endpoints.
///
/// Re-platforms `src/pages/admin/AdminLocations.jsx` + the Locations tab of
/// `CompanyDetail.jsx`. Contract `LocationResponse`:
/// `{ id, companyId, companyName, name, address, city, state, country,
///    keyCapacity, createdAt }`. `companyName` is populated on the admin flat
/// listing and null on the per-company nested listing.
class AdminLocation {
  const AdminLocation({
    required this.id,
    required this.companyId,
    this.companyName,
    required this.name,
    this.address,
    this.city,
    this.state,
    this.country,
    this.keyCapacity = 0,
    this.createdAt,
  });

  final String id;
  final String companyId;
  final String? companyName;
  final String name;
  final String? address;
  final String? city;
  final String? state;
  final String? country;
  final int keyCapacity;
  final String? createdAt;

  factory AdminLocation.fromJson(Map<String, dynamic> json) {
    return AdminLocation(
      id: (json['id'] ?? '').toString(),
      companyId: (json['companyId'] ?? '').toString(),
      companyName: _nullable(json['companyName']),
      name: (json['name'] ?? '').toString().trim(),
      address: _nullable(json['address']),
      city: _nullable(json['city']),
      state: _nullable(json['state']),
      country: _nullable(json['country']),
      keyCapacity: _asInt(json['keyCapacity']),
      createdAt: _nullable(json['createdAt']),
    );
  }

  /// A single readable line of the place (e.g. "100 Market St · Metropolis, CA").
  String get locationLine {
    final parts = <String>[
      if (address != null) address!,
      [
        if (city != null) city!,
        if (state != null) state!,
      ].join(', '),
      if (country != null) country!,
    ].where((p) => p.trim().isNotEmpty).toList();
    return parts.join(' · ');
  }

  static int _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static String? _nullable(Object? v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }
}

/// Body for `POST /api/companies/{id}/locations` and `PUT /api/locations/{id}`.
class CreateLocationInput {
  const CreateLocationInput({
    required this.name,
    this.address,
    this.city,
    this.state,
    this.country,
    this.keyCapacity = 0,
  });

  final String name;
  final String? address;
  final String? city;
  final String? state;
  final String? country;
  final int keyCapacity;

  Map<String, dynamic> toJson() {
    String? trimOrNull(String? v) {
      final s = v?.trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return {
      'name': name.trim(),
      if (trimOrNull(address) != null) 'address': trimOrNull(address),
      if (trimOrNull(city) != null) 'city': trimOrNull(city),
      if (trimOrNull(state) != null) 'state': trimOrNull(state),
      if (trimOrNull(country) != null) 'country': trimOrNull(country),
      'keyCapacity': keyCapacity,
    };
  }
}
