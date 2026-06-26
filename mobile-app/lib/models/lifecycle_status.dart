import 'package:flutter/material.dart';
import '../theme/v_colors.dart';

/// The canonical transaction lifecycle (mirrors STATUS_FLOW in the web app's
/// transactionService.js). The driver slice only acts on the dispatched →
/// moving → ready → done tail, but the full ramp drives the status rail.
enum LifecycleStatus {
  waitingForDriver('waiting_for_driver', 'Queued', VColors.statusQueued),
  parked('parked', 'Parked', VColors.statusSettled),
  keyIn('key_in', 'Secured', VColors.statusSecured),
  requested('requested', 'Requested', VColors.statusActive),
  driverAssigned('driver_assigned', 'Assigned', VColors.statusDispatched),
  enRoute('en_route', 'En route', VColors.statusMoving),
  arrived('arrived', 'Arrived', VColors.statusReady),
  delivered('delivered', 'Delivered', VColors.statusDone),
  cancelled('cancelled', 'Cancelled', VColors.alertDanger);

  const LifecycleStatus(this.wire, this.label, this.color);

  /// The exact string used on the wire / in Postgres.
  final String wire;

  /// Short human label for the rail and chips.
  final String label;

  /// The single status hue for this state (doc §6.1.4).
  final Color color;

  /// Ordered rail of the 8 lifecycle states (cancelled is off-rail).
  static const List<LifecycleStatus> rail = [
    waitingForDriver,
    parked,
    keyIn,
    requested,
    driverAssigned,
    enRoute,
    arrived,
    delivered,
  ];

  static LifecycleStatus fromWire(String? value) {
    for (final s in LifecycleStatus.values) {
      if (s.wire == value) return s;
    }
    return waitingForDriver;
  }

  /// Index along the 8-node rail; -1 for off-rail (cancelled).
  int get railIndex => rail.indexOf(this);

  /// `requested` and `arrived` are the only two that "shout" (doc §6.1.4).
  bool get shouldPulse =>
      this == LifecycleStatus.requested || this == LifecycleStatus.arrived;

  /// The next driver action for this state, or null if none in this slice.
  /// `waitingForDriver` is the INTAKE (park) side: a driver assigned to park
  /// confirms it parked. The rest are the retrieval tail.
  DriverAction? get nextAction => switch (this) {
        waitingForDriver => DriverAction.confirmParked,
        driverAssigned => DriverAction.enRoute,
        enRoute => DriverAction.arrived,
        arrived => DriverAction.deliver,
        _ => null,
      };

  /// The operator-side next actions for this state (a state can offer more than
  /// one, e.g. `parked` → Key in *or* Request). Empty once the car is in the
  /// driver's hands (driver_assigned → delivered) or terminal.
  List<OperatorAction> get operatorActions => switch (this) {
        // Intake: the operator hands the incoming car to a driver to park it.
        waitingForDriver => const [OperatorAction.assignPark],
        parked => const [OperatorAction.keyIn, OperatorAction.request],
        keyIn => const [OperatorAction.request],
        requested => const [OperatorAction.assign],
        _ => const [],
      };
}

/// The driver-initiated transitions in this slice.
enum DriverAction {
  /// Intake side: the assigned park driver confirms the incoming car is parked.
  confirmParked(
    verb: 'Slide — Parked',
    short: 'Parked',
    from: LifecycleStatus.waitingForDriver,
    to: LifecycleStatus.parked,
  ),
  enRoute(
    verb: 'Slide — On my way',
    short: 'En route',
    from: LifecycleStatus.driverAssigned,
    to: LifecycleStatus.enRoute,
  ),
  arrived(
    verb: 'Slide — Arrived',
    short: 'Arrived',
    from: LifecycleStatus.enRoute,
    to: LifecycleStatus.arrived,
  ),
  deliver(
    verb: 'Slide to deliver',
    short: 'Delivered',
    from: LifecycleStatus.arrived,
    to: LifecycleStatus.delivered,
  );

  const DriverAction({
    required this.verb,
    required this.short,
    required this.from,
    required this.to,
  });

  /// Thumb-zone slide-track label (doc §7.5).
  final String verb;

  /// Compact label for buttons / toasts.
  final String short;

  final LifecycleStatus from;
  final LifecycleStatus to;
}

/// The operator-initiated transitions (the floor side of the lifecycle).
/// Each maps to one `/api/operator/transactions/{id}/{verb}` endpoint and a
/// target status, mirroring [DriverAction] for the driver side.
enum OperatorAction {
  /// Intake: assign a driver to PARK the incoming car. Carries a {@code driverId}
  /// body; the car stays {@code waiting_for_driver} until that driver confirms.
  assignPark(
    label: 'Assign to park',
    icon: 'person_pin_circle',
    to: LifecycleStatus.waitingForDriver,
  ),
  park(
    label: 'Park',
    icon: 'local_parking',
    to: LifecycleStatus.parked,
  ),
  keyIn(
    label: 'Key in',
    icon: 'vpn_key',
    to: LifecycleStatus.keyIn,
  ),
  request(
    label: 'Request',
    icon: 'directions_car',
    to: LifecycleStatus.requested,
  ),
  assign(
    label: 'Assign driver',
    icon: 'person_pin_circle',
    to: LifecycleStatus.driverAssigned,
  ),
  cancel(
    label: 'Cancel',
    icon: 'close',
    to: LifecycleStatus.cancelled,
  );

  const OperatorAction({
    required this.label,
    required this.icon,
    required this.to,
  });

  /// Button / menu label.
  final String label;

  /// Icon key (resolved to an [IconData] in the screen layer).
  final String icon;

  /// The status this action transitions the transaction into.
  final LifecycleStatus to;
}
