import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/driver.dart';
import '../models/lifecycle_status.dart';
import '../models/transaction.dart';
import '../state/clock.dart';
import '../state/drivers_controller.dart';
import '../state/floor_controller.dart';
import '../state/providers.dart';
import '../theme/motion.dart';
import '../theme/v_colors.dart';
import '../theme/v_theme.dart';
import '../theme/v_tokens.dart';
import '../widgets/v_chips.dart';
import '../widgets/v_primary_button.dart';
import '../widgets/v_states.dart';
import '../widgets/v_status_rail.dart';
import 'operator_create_screen.dart';

/// Operator — live floor (doc §10.5: mutate cards in place ~240ms). Active
/// transactions grouped by lifecycle bucket; each card shows plate, guest, a
/// status pill, and the next-action button(s) for its state. A "+ New car" FAB
/// opens the create sheet. Realtime deltas animate cards in place via the
/// AnimatedSwitcher keyed on `id:status`.
class OperatorFloorScreen extends ConsumerWidget {
  const OperatorFloorScreen({super.key});

  /// The visible buckets, in floor order. Driver-held / terminal states don't
  /// surface their own group (assigned cars show under "Assigned" until handed
  /// to the driver's own app).
  static const _buckets = <_Bucket>[
    _Bucket('Waiting', [LifecycleStatus.waitingForDriver]),
    _Bucket('Parked', [LifecycleStatus.parked]),
    _Bucket('Key in', [LifecycleStatus.keyIn]),
    _Bucket('Requested', [LifecycleStatus.requested]),
    _Bucket('Assigned', [
      LifecycleStatus.driverAssigned,
      LifecycleStatus.enRoute,
      LifecycleStatus.arrived,
    ]),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final floor = ref.watch(floorControllerProvider);
    final user = ref.watch(authControllerProvider).user;

    return Scaffold(
      backgroundColor: VColors.surface950,
      appBar: AppBar(
        backgroundColor: VColors.surface950,
        titleSpacing: VSpace.x4,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('Floor',
                    style: VType.title.copyWith(color: VColors.contentStrong)),
                const SizedBox(width: VSpace.x2),
                _LiveDot(live: floor.live),
              ],
            ),
            Text(user?.displayName ?? 'Operator', style: VType.caption),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            constraints: const BoxConstraints(
              minWidth: VTarget.minTouch,
              minHeight: VTarget.minTouch,
            ),
            icon: const Icon(Icons.refresh_rounded, color: VColors.contentMuted),
            onPressed: () => ref.read(floorControllerProvider.notifier).load(),
          ),
          IconButton(
            tooltip: 'Sign out',
            constraints: const BoxConstraints(
              minWidth: VTarget.minTouch,
              minHeight: VTarget.minTouch,
            ),
            icon: const Icon(Icons.logout_rounded, color: VColors.contentMuted),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
          const SizedBox(width: VSpace.x2),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: VColors.brand500,
        foregroundColor: VColors.contentOnAccent,
        icon: const Icon(Icons.add_rounded),
        label: Text('New car', style: VType.label.copyWith(
            color: VColors.contentOnAccent)),
        onPressed: () => _openCreate(context),
      ),
      body: SafeArea(top: false, child: _body(context, ref, floor)),
    );
  }

  Future<void> _openCreate(BuildContext context) async {
    final plate = await OperatorCreateSheet.show(context);
    if (plate != null && context.mounted) {
      _toast(context, 'Added · $plate', VColors.alertSuccess);
    }
  }

  Widget _body(BuildContext context, WidgetRef ref, FloorState floor) {
    switch (floor.status) {
      case FloorStatus.loading:
        return const _FloorSkeleton();

      case FloorStatus.error:
        return Padding(
          padding: const EdgeInsets.all(VSpace.x4),
          child: Center(
            child: VBanner(
              message: floor.error ?? 'Something went wrong.',
              onRetry: () => ref.read(floorControllerProvider.notifier).load(),
            ),
          ),
        );

      case FloorStatus.empty:
        return RefreshIndicator(
          color: VColors.brand400,
          backgroundColor: VColors.surface800,
          onRefresh: () =>
              ref.read(floorControllerProvider.notifier).load(silent: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 120),
              VEmptyState(
                icon: Icons.local_parking_rounded,
                headline: 'The floor is clear',
                hint: 'Tap “New car” to check a vehicle in',
              ),
            ],
          ),
        );

      case FloorStatus.ready:
        return _list(context, ref, floor);
    }
  }

  Widget _list(BuildContext context, WidgetRef ref, FloorState floor) {
    final children = <Widget>[];
    for (final bucket in _buckets) {
      final items = floor.transactions
          .where((t) => bucket.statuses.contains(t.status))
          .toList();
      if (items.isEmpty) continue;
      children.add(_GroupHeader(label: bucket.label, count: items.length));
      for (final tx in items) {
        children.add(
          Padding(
            key: ValueKey('card-${tx.id}'),
            padding: const EdgeInsets.only(bottom: VSpace.x3),
            child: AnimatedSwitcher(
              duration: Motion.duration(context, VMotion.stateAdvance),
              switchInCurve: VMotion.emphasizedDecelerate,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SizeTransition(
                  sizeFactor: anim,
                  axisAlignment: -1,
                  child: child,
                ),
              ),
              child: _FloorCard(
                key: ValueKey('${tx.id}:${tx.status.wire}'),
                tx: tx,
                busy: floor.busyId == tx.id,
                onAction: (a) => _runAction(context, ref, tx, a),
              ),
            ),
          ),
        );
      }
    }

    return RefreshIndicator(
      color: VColors.brand400,
      backgroundColor: VColors.surface800,
      onRefresh: () =>
          ref.read(floorControllerProvider.notifier).load(silent: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          VSpace.x4,
          VSpace.x3,
          VSpace.x4,
          // room for the FAB.
          96,
        ),
        children: children,
      ),
    );
  }

  Future<void> _runAction(
    BuildContext context,
    WidgetRef ref,
    Transaction tx,
    OperatorAction action,
  ) async {
    String? driverId;
    if (action == OperatorAction.assign ||
        action == OperatorAction.assignPark) {
      driverId = await _AssignDriverSheet.show(
        context,
        isPark: action == OperatorAction.assignPark,
      );
      if (driverId == null) return; // cancelled / no selection.
    }

    final ok = await ref
        .read(floorControllerProvider.notifier)
        .act(tx, action, driverId: driverId);

    if (!context.mounted) return;
    if (ok) {
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.vibrate();
      final err = ref.read(floorControllerProvider).error;
      _toast(context, err ?? 'Could not update the car.', VColors.alertDanger);
      ref.read(floorControllerProvider.notifier).clearError();
    }
  }

  void _toast(BuildContext context, String message, Color color) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: VColors.surface700,
        margin: const EdgeInsets.all(VSpace.x4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VRadius.md),
          side: BorderSide(color: color, width: 1),
        ),
        content: Row(
          children: [
            Container(width: 3, height: 22, color: color),
            const SizedBox(width: VSpace.x3),
            Expanded(
              child: Text(message,
                  style: VType.body.copyWith(color: VColors.contentStrong)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bucket {
  const _Bucket(this.label, this.statuses);
  final String label;
  final List<LifecycleStatus> statuses;
}

/// A single floor card — plate + vehicle, guest/key chips, status pill + rail,
/// and the action button(s) for its lifecycle bucket.
class _FloorCard extends ConsumerWidget {
  const _FloorCard({
    super.key,
    required this.tx,
    required this.busy,
    required this.onAction,
  });

  final Transaction tx;
  final bool busy;
  final void Function(OperatorAction action) onAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).valueOrNull ?? DateTime.now();
    final elapsed = elapsedSince(tx.createdAtLocal, now);
    final actions = tx.status.operatorActions;

    return Container(
      decoration: BoxDecoration(
        color: VColors.surface900,
        borderRadius: BorderRadius.circular(VRadius.lg),
        border: Border.all(color: VColors.surface700, width: 1),
      ),
      padding: const EdgeInsets.all(VSpace.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tx.carPlate,
                        style: VType.monoLg.copyWith(
                            color: VColors.contentStrong)),
                    if (tx.vehicleSubline.isNotEmpty) ...[
                      const SizedBox(height: VSpace.x1),
                      Text(tx.vehicleSubline,
                          style: VType.caption,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              _StatusPill(status: tx.status),
            ],
          ),
          const SizedBox(height: VSpace.x3),
          // Context chips.
          Wrap(
            spacing: VSpace.x2,
            runSpacing: VSpace.x2,
            children: [
              if (tx.keyCode != null) VKeySlotChip(code: tx.keyCode!),
              if (tx.guestName != null)
                VMetaChip(
                  icon: Icons.person_outline_rounded,
                  label: tx.guestName!,
                  semanticLabel: 'Guest ${tx.guestName}',
                ),
              VMetaChip(
                icon: Icons.schedule_rounded,
                label: elapsed,
              ),
            ],
          ),
          const SizedBox(height: VSpace.x4),
          VStatusRail(status: tx.status),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: VSpace.x4),
            Row(
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: VSpace.x3),
                  Expanded(
                    child: _ActionButton(
                      action: actions[i],
                      busy: busy,
                      primary: i == actions.length - 1,
                      onPressed: () => onAction(actions[i]),
                    ),
                  ),
                ],
                const SizedBox(width: VSpace.x3),
                _CancelButton(
                  busy: busy,
                  onPressed: () => onAction(OperatorAction.cancel),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.action,
    required this.busy,
    required this.primary,
    required this.onPressed,
  });

  final OperatorAction action;
  final bool busy;
  final bool primary;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (primary) {
      return VPrimaryButton(
        label: action.label,
        icon: _iconFor(action),
        loading: busy,
        onPressed: busy ? null : onPressed,
      );
    }
    // Secondary action — tinted outline button.
    return SizedBox(
      height: 52,
      child: OutlinedButton.icon(
        onPressed: busy ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: VColors.contentStrong,
          side: const BorderSide(color: VColors.surface600, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(VRadius.md),
          ),
        ),
        icon: Icon(_iconFor(action), size: 18),
        label: Text(action.label,
            style: VType.label.copyWith(color: VColors.contentStrong)),
      ),
    );
  }
}

class _CancelButton extends StatelessWidget {
  const _CancelButton({required this.busy, required this.onPressed});
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 52,
      child: IconButton(
        tooltip: 'Cancel car',
        onPressed: busy ? null : onPressed,
        style: IconButton.styleFrom(
          backgroundColor: VColors.surface800,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(VRadius.md),
            side: const BorderSide(color: VColors.surface600, width: 1),
          ),
        ),
        icon: const Icon(Icons.close_rounded,
            size: 20, color: VColors.contentMuted),
      ),
    );
  }
}

IconData _iconFor(OperatorAction action) => switch (action) {
      OperatorAction.assignPark => Icons.local_parking_rounded,
      OperatorAction.park => Icons.local_parking_rounded,
      OperatorAction.keyIn => Icons.vpn_key_rounded,
      OperatorAction.request => Icons.directions_car_filled_rounded,
      OperatorAction.assign => Icons.person_pin_circle_rounded,
      OperatorAction.cancel => Icons.close_rounded,
    };

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final LifecycleStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: VSpace.x3,
        vertical: VSpace.x1,
      ),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(VRadius.full),
        border: Border.all(
          color: status.color.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Text(
        status.label,
        style: VType.caption.copyWith(
          color: status.color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: VSpace.x2, bottom: VSpace.x3),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: VType.caption.copyWith(
              color: VColors.contentMuted,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: VSpace.x2),
          Text('$count', style: VType.caption.copyWith(
              color: VColors.contentFaint)),
        ],
      ),
    );
  }
}

/// Small connection indicator — brand dot when live, faint when polling.
class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.live});
  final bool live;

  @override
  Widget build(BuildContext context) {
    final color = live ? VColors.statusReady : VColors.contentFaint;
    return Tooltip(
      message: live ? 'Live' : 'Reconnecting…',
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: live
              ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)]
              : null,
        ),
      ),
    );
  }
}

/// Assign-driver picker. Presents the operator's own-company drivers (loaded
/// from `GET /drivers` on the AUTH service, company-scoped server-side) as a
/// tappable list; selecting one pops its id so the existing assign endpoint is
/// called with a real driver. Falls back to a graceful empty state when the
/// company has no drivers yet. Returns null on cancel / no selection.
class _AssignDriverSheet extends ConsumerStatefulWidget {
  const _AssignDriverSheet({this.isPark = false});

  /// True when assigning a driver to PARK an incoming car (intake), false for a
  /// retrieval dispatch. Only changes the copy + the picked endpoint upstream.
  final bool isPark;

  static Future<String?> show(BuildContext context, {bool isPark = false}) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: VColors.surface800,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(VRadius.lg)),
      ),
      builder: (_) => _AssignDriverSheet(isPark: isPark),
    );
  }

  @override
  ConsumerState<_AssignDriverSheet> createState() => _AssignDriverSheetState();
}

class _AssignDriverSheetState extends ConsumerState<_AssignDriverSheet> {
  @override
  void initState() {
    super.initState();
    // Load (or refresh) the company's drivers as the sheet opens.
    Future.microtask(
        () => ref.read(driversControllerProvider.notifier).load());
  }

  /// Least-busy auto-assignment, computed client-side from the live floor: the
  /// driver currently carrying the fewest active cars (park missions still
  /// awaiting parking + retrievals in flight). No GPS — on a single valet floor
  /// the fair metric is workload, not metres. Deterministic id tie-break.
  String? _leastLoadedDriverId(List<Driver> roster) {
    if (roster.isEmpty) return null;
    final floor = ref.read(floorControllerProvider).transactions;

    int loadFor(String driverId) {
      return floor.where((t) {
        final parking = t.parkedByDriverId == driverId &&
            t.status == LifecycleStatus.waitingForDriver;
        final retrieving = t.retrievedByDriverId == driverId &&
            (t.status == LifecycleStatus.driverAssigned ||
                t.status == LifecycleStatus.enRoute ||
                t.status == LifecycleStatus.arrived);
        return parking || retrieving;
      }).length;
    }

    final sorted = [...roster]..sort((a, b) {
      final byLoad = loadFor(a.id).compareTo(loadFor(b.id));
      return byLoad != 0 ? byLoad : a.id.compareTo(b.id);
    });
    return sorted.first.id;
  }

  @override
  Widget build(BuildContext context) {
    final drivers = ref.watch(driversControllerProvider);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            VSpace.x4, VSpace.x4, VSpace.x4, VSpace.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(widget.isPark ? 'Assign park driver' : 'Assign driver',
                      style: VType.title
                          .copyWith(color: VColors.contentStrong)),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded,
                      color: VColors.contentMuted),
                ),
              ],
            ),
            const SizedBox(height: VSpace.x1),
            Text(
                widget.isPark
                    ? 'Pick a driver to go park this incoming car — or auto-assign the least busy.'
                    : 'Pick a driver to dispatch this retrieval — or auto-assign the least busy.',
                style: VType.caption),
            const SizedBox(height: VSpace.x4),
            if (drivers.status == DriversStatus.ready &&
                drivers.drivers.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: VSpace.x3),
                child: VPrimaryButton(
                  label: 'Auto — assign least busy',
                  icon: Icons.bolt_rounded,
                  onPressed: () {
                    final pick = _leastLoadedDriverId(drivers.drivers);
                    if (pick != null) Navigator.of(context).pop(pick);
                  },
                ),
              ),
            _content(context, drivers),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, DriversState drivers) {
    switch (drivers.status) {
      case DriversStatus.idle:
      case DriversStatus.loading:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: VSpace.x6),
          child: Center(
            child: CircularProgressIndicator(color: VColors.brand400),
          ),
        );

      case DriversStatus.error:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: VSpace.x4),
          child: VBanner(
            message: drivers.error ?? 'Could not load drivers.',
            onRetry: () =>
                ref.read(driversControllerProvider.notifier).load(),
          ),
        );

      case DriversStatus.empty:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: VSpace.x4),
          child: VEmptyState(
            icon: Icons.person_off_outlined,
            headline: 'No drivers yet',
            hint: 'No drivers in your company yet. Add one to dispatch cars.',
          ),
        );

      case DriversStatus.ready:
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.5,
          ),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: drivers.drivers.length,
            separatorBuilder: (_, __) => const SizedBox(height: VSpace.x2),
            itemBuilder: (_, i) => _DriverTile(
              driver: drivers.drivers[i],
              onTap: () =>
                  Navigator.of(context).pop(drivers.drivers[i].id),
            ),
          ),
        );
    }
  }
}

/// A single tappable driver row in the assign picker.
class _DriverTile extends StatelessWidget {
  const _DriverTile({required this.driver, required this.onTap});

  final Driver driver;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: VColors.surface900,
      borderRadius: BorderRadius.circular(VRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VRadius.md),
        child: Container(
          constraints: const BoxConstraints(minHeight: VTarget.minTouch),
          padding: const EdgeInsets.symmetric(
              horizontal: VSpace.x4, vertical: VSpace.x3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(VRadius.md),
            border: Border.all(color: VColors.surface700, width: 1),
          ),
          child: Row(
            children: [
              const Icon(Icons.person_pin_circle_rounded,
                  size: 20, color: VColors.brand300),
              const SizedBox(width: VSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(driver.displayName,
                        style: VType.label
                            .copyWith(color: VColors.contentStrong),
                        overflow: TextOverflow.ellipsis),
                    if (driver.email.isNotEmpty &&
                        driver.email != driver.displayName) ...[
                      const SizedBox(height: VSpace.x1),
                      Text(driver.email,
                          style: VType.caption,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: VColors.contentMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton list while the floor loads.
class _FloorSkeleton extends StatelessWidget {
  const _FloorSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(VSpace.x4),
      child: VShimmer(
        child: Column(
          children: List.generate(
            3,
            (_) => Container(
              margin: const EdgeInsets.only(bottom: VSpace.x3),
              decoration: BoxDecoration(
                color: VColors.surface900,
                borderRadius: BorderRadius.circular(VRadius.lg),
                border: Border.all(color: VColors.surface700, width: 1),
              ),
              padding: const EdgeInsets.all(VSpace.x4),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  VSkeletonBox(width: 140, height: 24),
                  SizedBox(height: VSpace.x3),
                  VSkeletonBox(width: 200, height: 14),
                  SizedBox(height: VSpace.x4),
                  VSkeletonBox(
                      width: double.infinity, height: 48, radius: VRadius.md),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
