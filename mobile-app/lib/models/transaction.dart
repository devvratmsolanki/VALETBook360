import 'lifecycle_status.dart';

/// A floor transaction from the operator endpoints (`/api/operator/transactions`).
///
/// Contract shape (camelCase on the wire):
/// `{ id, companyId, locationId, carPlate, carMake, carModel, carColor,
///    keyCode, status, parkedByDriverId, retrievedByDriverId, guestName,
///    guestPhone, requestedAt, arrivedAt, deliveredAt, createdAt, updatedAt }`
///
/// Reuses [LifecycleStatus] (which already models the full 9-state lifecycle).
class Transaction {
  const Transaction({
    required this.id,
    required this.carPlate,
    required this.status,
    this.companyId,
    this.locationId,
    this.carMake,
    this.carModel,
    this.carColor,
    this.keyCode,
    this.parkedByDriverId,
    this.retrievedByDriverId,
    this.guestName,
    this.guestPhone,
    this.requestedAt,
    this.arrivedAt,
    this.deliveredAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String carPlate;
  final LifecycleStatus status;
  final String? companyId;
  final String? locationId;
  final String? carMake;
  final String? carModel;
  final String? carColor;
  final String? keyCode;
  final String? parkedByDriverId;
  final String? retrievedByDriverId;
  final String? guestName;
  final String? guestPhone;

  /// Parsed as UTC (the no-TZ Postgres pitfall the web app guards against).
  final DateTime? requestedAt;
  final DateTime? arrivedAt;
  final DateTime? deliveredAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: (json['id'] ?? '').toString(),
      carPlate: (json['carPlate'] ?? '').toString(),
      status: LifecycleStatus.fromWire(json['status']?.toString()),
      companyId: _str(json['companyId']),
      locationId: _str(json['locationId']),
      carMake: _str(json['carMake']),
      carModel: _str(json['carModel']),
      carColor: _str(json['carColor']),
      keyCode: _str(json['keyCode']),
      parkedByDriverId: _str(json['parkedByDriverId']),
      retrievedByDriverId: _str(json['retrievedByDriverId']),
      guestName: _str(json['guestName']),
      guestPhone: _str(json['guestPhone']),
      requestedAt: _parseUtc(json['requestedAt']),
      arrivedAt: _parseUtc(json['arrivedAt']),
      deliveredAt: _parseUtc(json['deliveredAt']),
      createdAt: _parseUtc(json['createdAt']),
      updatedAt: _parseUtc(json['updatedAt']),
    );
  }

  Transaction copyWith({LifecycleStatus? status, String? parkedByDriverId}) =>
      Transaction(
        id: id,
        carPlate: carPlate,
        status: status ?? this.status,
        companyId: companyId,
        locationId: locationId,
        carMake: carMake,
        carModel: carModel,
        carColor: carColor,
        keyCode: keyCode,
        parkedByDriverId: parkedByDriverId ?? this.parkedByDriverId,
        retrievedByDriverId: retrievedByDriverId,
        guestName: guestName,
        guestPhone: guestPhone,
        requestedAt: requestedAt,
        arrivedAt: arrivedAt,
        deliveredAt: deliveredAt,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  /// "Make Model" with graceful blanks, e.g. "Tesla Model 3".
  String get vehicleLine {
    final parts = [carMake, carModel].where((p) => p != null && p.isNotEmpty);
    return parts.join(' ');
  }

  /// Color · vehicle, for the card subline.
  String get vehicleSubline => [carColor, vehicleLine]
      .where((p) => p != null && p.isNotEmpty)
      .join(' · ');

  DateTime? get createdAtLocal => createdAt?.toLocal();

  static String? _str(Object? v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static DateTime? _parseUtc(Object? v) {
    if (v == null) return null;
    final raw = v.toString().trim();
    if (raw.isEmpty) return null;
    final hasZone =
        raw.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(raw);
    final normalized = hasZone ? raw : '${raw}Z';
    return DateTime.tryParse(normalized);
  }
}

/// The whitelisted create-transaction body (`POST /api/operator/transactions`).
class CreateTransactionInput {
  const CreateTransactionInput({
    required this.carPlate,
    this.carMake,
    this.carModel,
    this.carColor,
    this.guestName,
    this.guestPhone,
    this.keyCode,
  });

  final String carPlate;
  final String? carMake;
  final String? carModel;
  final String? carColor;
  final String? guestName;
  final String? guestPhone;
  final String? keyCode;

  Map<String, dynamic> toJson() => {
        'carPlate': carPlate,
        if (_has(carMake)) 'carMake': carMake!.trim(),
        if (_has(carModel)) 'carModel': carModel!.trim(),
        if (_has(carColor)) 'carColor': carColor!.trim(),
        if (_has(guestName)) 'guestName': guestName!.trim(),
        if (_has(guestPhone)) 'guestPhone': guestPhone!.trim(),
        if (_has(keyCode)) 'keyCode': keyCode!.trim(),
      };

  static bool _has(String? v) => v != null && v.trim().isNotEmpty;
}
