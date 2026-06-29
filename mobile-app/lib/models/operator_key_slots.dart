/// The effective key-slot pool for the operator's own location — `GET /key-slots`.
///
/// Contract shape: `{ locationId, keyCapacity, slots }`, where `slots` is the
/// ORDERED effective pool (custom names if the company set them, else
/// "1".."keyCapacity"). May be empty if the location has no capacity/slots.
class OperatorKeySlots {
  const OperatorKeySlots({
    required this.slots,
    this.locationId,
    this.keyCapacity = 0,
  });

  final String? locationId;
  final int keyCapacity;
  final List<String> slots;

  factory OperatorKeySlots.fromJson(Map<String, dynamic> json) {
    final raw = json['slots'];
    final slots = raw is List
        ? raw
            .map((e) => e?.toString().trim() ?? '')
            .where((s) => s.isNotEmpty)
            .toList(growable: false)
        : const <String>[];
    return OperatorKeySlots(
      locationId: json['locationId']?.toString(),
      keyCapacity: (json['keyCapacity'] is num)
          ? (json['keyCapacity'] as num).toInt()
          : int.tryParse('${json['keyCapacity']}') ?? 0,
      slots: slots,
    );
  }
}
