/// A company ↔ venue service agreement — `GET /api/companies/{id}/contracts`.
///
/// Contract shape: `{ id, locationId, locationName, locationCity, locationState,
/// name, type, status, active, managerName, managerPhone, managerEmail }`.
class Contract {
  const Contract({
    required this.id,
    required this.name,
    required this.active,
    this.locationName,
    this.locationCity,
    this.locationState,
    this.type,
    this.status,
    this.managerName,
    this.managerPhone,
    this.managerEmail,
  });

  final String id;
  final String name;
  final bool active;
  final String? locationName;
  final String? locationCity;
  final String? locationState;
  final String? type;
  final String? status;
  final String? managerName;
  final String? managerPhone;
  final String? managerEmail;

  factory Contract.fromJson(Map<String, dynamic> json) {
    return Contract(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      active: json['active'] == true,
      locationName: _str(json['locationName']),
      locationCity: _str(json['locationCity']),
      locationState: _str(json['locationState']),
      type: _str(json['type']),
      status: _str(json['status']),
      managerName: _str(json['managerName']),
      managerPhone: _str(json['managerPhone']),
      managerEmail: _str(json['managerEmail']),
    );
  }

  static String? _str(Object? v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }
}

/// Whitelisted create-contract body.
class CreateContractInput {
  const CreateContractInput({
    required this.name,
    this.locationId,
    this.type,
    this.status,
    this.active = true,
    this.managerName,
    this.managerPhone,
    this.managerEmail,
  });

  final String name;
  final String? locationId;
  final String? type;
  final String? status;
  final bool active;
  final String? managerName;
  final String? managerPhone;
  final String? managerEmail;

  Map<String, dynamic> toJson() => {
        'name': name.trim(),
        if (locationId != null) 'locationId': locationId,
        if (_has(type)) 'type': type!.trim(),
        if (_has(status)) 'status': status!.trim(),
        'active': active,
        if (_has(managerName)) 'managerName': managerName!.trim(),
        if (_has(managerPhone)) 'managerPhone': managerPhone!.trim(),
        if (_has(managerEmail)) 'managerEmail': managerEmail!.trim(),
      };

  static bool _has(String? v) => v != null && v.trim().isNotEmpty;
}
