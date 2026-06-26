/// A custom key-storage slot for a location — `GET /api/locations/{id}/slots`.
///
/// Contract shape: `{ id, locationId, slotName, sortOrder }`.
class KeySlot {
  const KeySlot({
    required this.id,
    required this.slotName,
    required this.sortOrder,
    this.locationId,
  });

  final String id;
  final String slotName;
  final int sortOrder;
  final String? locationId;

  factory KeySlot.fromJson(Map<String, dynamic> json) {
    return KeySlot(
      id: (json['id'] ?? '').toString(),
      slotName: (json['slotName'] ?? '').toString(),
      sortOrder: (json['sortOrder'] is num)
          ? (json['sortOrder'] as num).toInt()
          : int.tryParse('${json['sortOrder']}') ?? 0,
      locationId: json['locationId']?.toString(),
    );
  }

  KeySlot copyWith({String? slotName}) => KeySlot(
        id: id,
        slotName: slotName ?? this.slotName,
        sortOrder: sortOrder,
        locationId: locationId,
      );
}
