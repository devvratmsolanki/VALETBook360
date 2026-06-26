import 'lifecycle_status.dart';

/// A driver assignment from `GET /api/driver/assignments`.
///
/// Contract shape (EXACT keys):
/// `{ id, carPlate, carMake, carModel, carColor, keyCode, status,
///    guestName, locationId, requestedAt }`
class Assignment {
  const Assignment({
    required this.id,
    required this.carPlate,
    required this.status,
    this.carMake,
    this.carModel,
    this.carColor,
    this.keyCode,
    this.guestName,
    this.locationId,
    this.requestedAt,
    this.missionType = 'retrieval',
  });

  final String id;
  final String carPlate;
  final LifecycleStatus status;
  final String? carMake;
  final String? carModel;
  final String? carColor;
  final String? keyCode;
  final String? guestName;
  final String? locationId;

  /// Parsed as UTC. The contract sends ISO-8601; we normalise to local for
  /// display via [requestedAtLocal] (mirrors the parseUTC pitfall note).
  final DateTime? requestedAt;

  /// `"park"` (intake — go park this incoming car) or `"retrieval"` (go fetch +
  /// deliver). Drives the mission card label and which action the driver gets.
  final String missionType;

  /// True for an intake (go-park) mission.
  bool get isPark => missionType == 'park';

  factory Assignment.fromJson(Map<String, dynamic> json) {
    return Assignment(
      id: (json['id'] ?? '').toString(),
      carPlate: (json['carPlate'] ?? '').toString(),
      status: LifecycleStatus.fromWire(json['status']?.toString()),
      carMake: _str(json['carMake']),
      carModel: _str(json['carModel']),
      carColor: _str(json['carColor']),
      keyCode: _str(json['keyCode']),
      guestName: _str(json['guestName']),
      locationId: _str(json['locationId']),
      requestedAt: _parseUtc(json['requestedAt']),
      missionType: (json['missionType'] ?? 'retrieval').toString(),
    );
  }

  Assignment copyWith({LifecycleStatus? status}) => Assignment(
        id: id,
        carPlate: carPlate,
        status: status ?? this.status,
        carMake: carMake,
        carModel: carModel,
        carColor: carColor,
        keyCode: keyCode,
        guestName: guestName,
        locationId: locationId,
        requestedAt: requestedAt,
        missionType: missionType,
      );

  /// "Make Model" with graceful blanks, e.g. "Tesla Model 3".
  String get vehicleLine {
    final parts = [carMake, carModel].where((p) => p != null && p.isNotEmpty);
    return parts.join(' ');
  }

  DateTime? get requestedAtLocal => requestedAt?.toLocal();

  static String? _str(Object? v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  /// Parses an ISO timestamp, treating a missing TZ marker as UTC (the
  /// Supabase/Postgres pitfall the web app guards against).
  static DateTime? _parseUtc(Object? v) {
    if (v == null) return null;
    final raw = v.toString().trim();
    if (raw.isEmpty) return null;
    final hasZone = raw.endsWith('Z') ||
        RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(raw);
    final normalized = hasZone ? raw : '${raw}Z';
    return DateTime.tryParse(normalized);
  }
}
