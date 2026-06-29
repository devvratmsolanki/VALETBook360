import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_exception.dart';
import '../models/admin_location.dart';
import '../models/admin_user.dart';
import '../models/key_slot.dart';
import '../models/lifecycle_status.dart';
import '../models/transaction.dart';
import '../state/company_detail_controller.dart';
import '../state/providers.dart';
import '../theme/v_breakpoints.dart';
import '../theme/v_colors.dart';
import '../theme/v_theme.dart';
import '../theme/v_tokens.dart';
import '../widgets/app_logo.dart';
import '../widgets/v_primary_button.dart';
import '../widgets/v_states.dart';

/// Location Detail — re-platforms the legacy `LocationDetail.jsx`: 4 KPI cards
/// (Total Visits / Active Now / Keys In / Completed) + tabs Overview, Key Slots,
/// Drivers, Activity. The Key Slots tab carries the bulk generator (the "Bulk
/// Key Slot Setup" modal), inline rename, and delete.
class LocationDetailScreen extends ConsumerWidget {
  const LocationDetailScreen({super.key, required this.location});
  final AdminLocation location;

  static const _active = {
    LifecycleStatus.parked,
    LifecycleStatus.keyIn,
    LifecycleStatus.requested,
    LifecycleStatus.driverAssigned,
    LifecycleStatus.enRoute,
    LifecycleStatus.arrived,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(companyHistoryProvider);
    final slots = ref.watch(locationSlotsProvider(location.id));

    // Transactions for THIS location (from the company history feed).
    final txns = history.maybeWhen(
      data: (all) =>
          all.where((t) => t.locationId == location.id).toList(),
      orElse: () => const <Transaction>[],
    );
    final activeTxns = txns.where((t) => _active.contains(t.status)).toList();
    final delivered =
        txns.where((t) => t.status == LifecycleStatus.delivered).length;
    // Keys In = distinct occupied key codes among active cars.
    final occupied = activeTxns
        .map((t) => t.keyCode)
        .where((k) => k != null && k.isNotEmpty)
        .toSet()
        .length;
    final capacity = slots.maybeWhen(
      data: (s) => s.isNotEmpty ? s.length : location.keyCapacity,
      orElse: () => location.keyCapacity,
    );

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: VColors.surface950,
        appBar: AppBar(
          backgroundColor: VColors.surface950,
          elevation: 0,
          iconTheme: IconThemeData(color: VColors.contentMuted),
          titleSpacing: 0,
          title: Row(
            children: [
              const AppLogo(height: 22),
              const SizedBox(width: VSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(location.name,
                        style:
                            VType.title.copyWith(color: VColors.contentStrong),
                        overflow: TextOverflow.ellipsis),
                    Text(
                        [location.address, location.city, location.state]
                            .where((p) => p != null && p.isNotEmpty)
                            .join(', '),
                        style: VType.caption,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          bottom: TabBar(
            isScrollable: true,
            indicatorColor: VColors.brand400,
            labelColor: VColors.contentStrong,
            unselectedLabelColor: VColors.contentMuted,
            labelStyle: VType.label,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Key Slots'),
              Tab(text: 'Drivers'),
              Tab(text: 'Activity'),
            ],
          ),
        ),
        body: Column(
          children: [
            // KPI cards
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  VSpace.x4, VSpace.x4, VSpace.x4, VSpace.x2),
              child: Row(
                children: [
                  _Kpi(
                      value: '${txns.length}',
                      label: 'Total Visits',
                      color: VColors.brand400),
                  const SizedBox(width: VSpace.x2),
                  _Kpi(
                      value: '${activeTxns.length}',
                      label: 'Active Now',
                      color: VColors.statusReady),
                  const SizedBox(width: VSpace.x2),
                  _Kpi(
                      value: '$occupied/$capacity',
                      label: 'Keys In',
                      color: VColors.brand300),
                  const SizedBox(width: VSpace.x2),
                  _Kpi(
                      value: '$delivered',
                      label: 'Completed',
                      color: VColors.alertSuccess),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _OverviewTab(location: location),
                  _KeySlotsTab(location: location),
                  _DriversTab(location: location),
                  _ActivityTab(txns: txns),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.value, required this.label, required this.color});
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: VSpace.x2, vertical: VSpace.x3),
        decoration: BoxDecoration(
          color: VColors.surface900,
          borderRadius: BorderRadius.circular(VRadius.md),
          border: Border.all(color: VColors.surface700),
        ),
        child: Column(
          children: [
            FittedBox(
              child: Text(value,
                  style: VType.titleLg.copyWith(color: color)),
            ),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                style: VType.caption.copyWith(
                    fontSize: context.responsive(compact: 9, expanded: 11),
                    letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Overview

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.location});
  final AdminLocation location;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Name', location.name),
      ('Address', location.address ?? '—'),
      ('City', location.city ?? '—'),
      ('State', location.state ?? '—'),
      ('Country', location.country ?? '—'),
      ('Key Capacity', '${location.keyCapacity}'),
    ];
    return ListView(
      padding: const EdgeInsets.all(VSpace.x4),
      children: [
        Text('Location Profile',
            style: VType.label.copyWith(color: VColors.contentStrong)),
        const SizedBox(height: VSpace.x3),
        for (final r in rows)
          Container(
            margin: const EdgeInsets.only(bottom: VSpace.x2),
            padding: const EdgeInsets.all(VSpace.x3),
            decoration: BoxDecoration(
              color: VColors.surface900,
              borderRadius: BorderRadius.circular(VRadius.md),
              border: Border.all(color: VColors.surface700),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(r.$1.toUpperCase(),
                    style: VType.caption
                        .copyWith(color: VColors.contentFaint)),
                Flexible(
                  child: Text(r.$2,
                      textAlign: TextAlign.right,
                      style: VType.body
                          .copyWith(color: VColors.contentStrong)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Key Slots

class _KeySlotsTab extends ConsumerWidget {
  const _KeySlotsTab({required this.location});
  final AdminLocation location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slotsAsync = ref.watch(locationSlotsProvider(location.id));

    Future<void> openBulk() async {
      final created = await _BulkSlotSheet.show(context, ref, location);
      if (created == true) ref.invalidate(locationSlotsProvider(location.id));
    }

    return slotsAsync.when(
      loading: () => Center(
          child: CircularProgressIndicator(color: VColors.brand400)),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(VSpace.x4),
        child: VBanner(
            message: 'Could not load key slots.',
            onRetry: () => ref.invalidate(locationSlotsProvider(location.id))),
      ),
      data: (slots) {
        return Column(
          children: [
            // Header / advanced key management
            Padding(
              padding: const EdgeInsets.all(VSpace.x4),
              child: Container(
                padding: const EdgeInsets.all(VSpace.x3),
                decoration: BoxDecoration(
                  color: VColors.surface900,
                  borderRadius: BorderRadius.circular(VRadius.md),
                  border: Border.all(color: VColors.surface700),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Advanced Key Management',
                              style: VType.body),
                          Text('Custom labels for your key storage (e.g. VIP-1, Box A)',
                              style: VType.caption),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: VColors.brand500,
                          foregroundColor: VColors.contentOnAccent),
                      onPressed: openBulk,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Bulk Setup'),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: slots.isEmpty
                  ? _StandardNumbering(
                      capacity: location.keyCapacity, onSetup: openBulk)
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(
                          VSpace.x4, 0, VSpace.x4, VSpace.x4),
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: context.responsive(
                            compact: 2, medium: 3, expanded: 4, large: 5),
                        mainAxisSpacing: VSpace.x2,
                        crossAxisSpacing: VSpace.x2,
                        childAspectRatio: 1.6,
                      ),
                      itemCount: slots.length,
                      itemBuilder: (_, i) => _SlotCard(
                        slot: slots[i],
                        onRename: (name) async {
                          await ref
                              .read(apiClientProvider)
                              .renameSlot(slots[i].id, name);
                          ref.invalidate(locationSlotsProvider(location.id));
                        },
                        onDelete: () async {
                          await ref
                              .read(apiClientProvider)
                              .deleteSlot(slots[i].id);
                          ref.invalidate(locationSlotsProvider(location.id));
                        },
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _StandardNumbering extends StatelessWidget {
  const _StandardNumbering({required this.capacity, required this.onSetup});
  final int capacity;
  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(VSpace.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.vpn_key_outlined,
                size: 44, color: VColors.surface600),
            const SizedBox(height: VSpace.x4),
            Text('Standard Numbering Active',
                style: VType.body.copyWith(color: VColors.contentStrong)),
            const SizedBox(height: VSpace.x1),
            Text('Currently using generic slots 1 through $capacity',
                textAlign: TextAlign.center, style: VType.caption),
            const SizedBox(height: VSpace.x5),
            VPrimaryButton(
                label: 'Setup Custom Labels',
                icon: Icons.dashboard_customize_rounded,
                onPressed: onSetup),
          ],
        ),
      ),
    );
  }
}

class _SlotCard extends StatefulWidget {
  const _SlotCard(
      {required this.slot, required this.onRename, required this.onDelete});
  final KeySlot slot;
  final Future<void> Function(String name) onRename;
  final Future<void> Function() onDelete;

  @override
  State<_SlotCard> createState() => _SlotCardState();
}

class _SlotCardState extends State<_SlotCard> {
  bool _editing = false;
  late final TextEditingController _ctl =
      TextEditingController(text: widget.slot.slotName);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(VSpace.x2),
      decoration: BoxDecoration(
        color: VColors.surface900,
        borderRadius: BorderRadius.circular(VRadius.md),
        border: Border.all(
            color: _editing ? VColors.brand500 : VColors.surface700),
      ),
      child: _editing
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextField(
                  controller: _ctl,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  style: VType.body.copyWith(color: VColors.contentStrong),
                  decoration: const InputDecoration(
                      isDense: true, border: InputBorder.none),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      iconSize: 16,
                      onPressed: () => setState(() => _editing = false),
                      icon: Icon(Icons.close_rounded,
                          color: VColors.contentMuted),
                    ),
                    IconButton(
                      iconSize: 16,
                      onPressed: () async {
                        final name = _ctl.text.trim();
                        if (name.isEmpty) return;
                        setState(() => _editing = false);
                        await widget.onRename(name);
                      },
                      icon: Icon(Icons.check_rounded,
                          color: VColors.alertSuccess),
                    ),
                  ],
                ),
              ],
            )
          : Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _miniIcon(Icons.edit_outlined,
                          () => setState(() => _editing = true)),
                      _miniIcon(Icons.delete_outline_rounded, widget.onDelete,
                          danger: true),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(widget.slot.slotName,
                        style: VType.titleLg
                            .copyWith(color: VColors.contentStrong)),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _miniIcon(IconData icon, VoidCallback onTap, {bool danger = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(VRadius.sm),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(icon,
            size: 15,
            color: danger ? VColors.alertDanger : VColors.contentFaint),
      ),
    );
  }
}

// ---------------------------------------------------------------- Drivers

class _DriversTab extends ConsumerWidget {
  const _DriversTab({required this.location});
  final AdminLocation location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail =
        ref.watch(companyDetailControllerProvider(location.companyId));
    // Drivers assigned to this location, plus unassigned (mirrors legacy).
    final drivers = detail.drivers
        .where((d) => d.locationId == null || d.locationId == location.id)
        .toList();
    if (detail.status == DetailStatus.loading) {
      return Center(
          child: CircularProgressIndicator(color: VColors.brand400));
    }
    if (drivers.isEmpty) {
      return const VEmptyState(
        icon: Icons.person_off_outlined,
        headline: 'No drivers here',
        hint: 'Drivers assigned to this location will appear here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(VSpace.x4),
      itemCount: drivers.length,
      separatorBuilder: (_, __) => const SizedBox(height: VSpace.x2),
      itemBuilder: (_, i) => _DriverRow(driver: drivers[i]),
    );
  }
}

class _DriverRow extends StatelessWidget {
  const _DriverRow({required this.driver});
  final AdminUser driver;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(VSpace.x3),
      decoration: BoxDecoration(
        color: VColors.surface900,
        borderRadius: BorderRadius.circular(VRadius.md),
        border: Border.all(color: VColors.surface700),
      ),
      child: Row(
        children: [
          Icon(Icons.directions_car_filled_rounded,
              color: VColors.brand400, size: 18),
          const SizedBox(width: VSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(driver.name ?? driver.email,
                    style:
                        VType.body.copyWith(color: VColors.contentStrong)),
                Text(driver.email, style: VType.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Activity

class _ActivityTab extends StatelessWidget {
  const _ActivityTab({required this.txns});
  final List<Transaction> txns;

  @override
  Widget build(BuildContext context) {
    if (txns.isEmpty) {
      return const VEmptyState(
        icon: Icons.history_rounded,
        headline: 'No activity yet',
        hint: 'Transactions at this location will appear here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(VSpace.x4),
      itemCount: txns.length,
      separatorBuilder: (_, __) => const SizedBox(height: VSpace.x2),
      itemBuilder: (_, i) {
        final t = txns[i];
        return Container(
          padding: const EdgeInsets.all(VSpace.x3),
          decoration: BoxDecoration(
            color: VColors.surface900,
            borderRadius: BorderRadius.circular(VRadius.md),
            border: Border.all(color: VColors.surface700),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.carPlate,
                        style: VType.body.copyWith(
                            color: VColors.contentStrong,
                            fontWeight: FontWeight.w600)),
                    Text(t.guestName ?? 'Guest', style: VType.caption),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: VSpace.x2, vertical: VSpace.x0),
                decoration: BoxDecoration(
                  color: t.status.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(VRadius.full),
                ),
                child: Text(t.status.label,
                    style: VType.caption.copyWith(
                        color: t.status.color, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------- Bulk Key Slot Setup

class _BulkSlotSheet extends ConsumerStatefulWidget {
  const _BulkSlotSheet({required this.location});
  final AdminLocation location;

  static Future<bool?> show(
      BuildContext context, WidgetRef ref, AdminLocation location) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: VColors.surface950,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(VRadius.lg)),
      ),
      builder: (_) => _BulkSlotSheet(location: location),
    );
  }

  @override
  ConsumerState<_BulkSlotSheet> createState() => _BulkSlotSheetState();
}

class _BulkSlotSheetState extends ConsumerState<_BulkSlotSheet> {
  final _prefix = TextEditingController();
  final _count = TextEditingController(text: '10');
  final _start = TextEditingController(text: '1');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _prefix.dispose();
    _count.dispose();
    _start.dispose();
    super.dispose();
  }

  int get _countVal => int.tryParse(_count.text.trim()) ?? 0;
  int get _startVal => int.tryParse(_start.text.trim()) ?? 1;

  Future<void> _submit() async {
    final count = _countVal.clamp(1, 500);
    final start = _startVal < 0 ? 0 : _startVal;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).bulkGenerateSlots(
            widget.location.id,
            prefix: _prefix.text.trim(),
            count: count,
            startFrom: start,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (_) {
      setState(() {
        _busy = false;
        _error = 'Could not generate slots. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefix = _prefix.text.trim();
    final start = _startVal;
    final count = _countVal.clamp(0, 500);
    final last = count > 0 ? start + count - 1 : start;

    return Padding(
      padding: EdgeInsets.only(
        left: VSpace.x4,
        right: VSpace.x4,
        top: VSpace.x4,
        bottom: MediaQuery.of(context).viewInsets.bottom + VSpace.x4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Bulk Key Slot Setup',
                    style: VType.title
                        .copyWith(color: VColors.contentStrong)),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(false),
                icon: Icon(Icons.close_rounded,
                    color: VColors.contentMuted),
              ),
            ],
          ),
          const SizedBox(height: VSpace.x1),
          Text(
              'System will generate unique labels for your key storage. This will NOT affect active transactions.',
              style: VType.caption),
          const SizedBox(height: VSpace.x4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Field(
                  label: 'Label Prefix',
                  controller: _prefix,
                  hint: 'e.g. A, BOX, V',
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: VSpace.x3),
              Expanded(
                child: _Field(
                  label: 'Quantity',
                  controller: _count,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: VSpace.x3),
          _Field(
            label: 'Start Sequence From',
            controller: _start,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: VSpace.x4),
          // Example output
          Container(
            padding: const EdgeInsets.all(VSpace.x3),
            decoration: BoxDecoration(
              color: VColors.surface900,
              borderRadius: BorderRadius.circular(VRadius.md),
              border: Border.all(color: VColors.surface700),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('EXAMPLE OUTPUT',
                    style: VType.caption
                        .copyWith(color: VColors.contentFaint)),
                const SizedBox(height: VSpace.x2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _chip('$prefix$start'),
                    Text('…  $count slots  …', style: VType.caption),
                    _chip('$prefix$last'),
                  ],
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: VSpace.x3),
            Text(_error!,
                style: VType.caption.copyWith(color: VColors.alertDanger)),
          ],
          const SizedBox(height: VSpace.x4),
          VPrimaryButton(
            label: 'Setup Slots Now',
            loading: _busy,
            onPressed: _countVal > 0
                ? () {
                    HapticFeedback.lightImpact();
                    _submit();
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: VSpace.x2, vertical: VSpace.x0),
        decoration: BoxDecoration(
          color: VColors.brand500.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(VRadius.full),
        ),
        child: Text(text,
            style: VType.caption.copyWith(color: VColors.brand300)),
      );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.onChanged,
  });
  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: VType.caption),
        const SizedBox(height: VSpace.x1),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          onChanged: onChanged,
          style: VType.body.copyWith(color: VColors.contentStrong),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: VType.body.copyWith(color: VColors.contentFaint),
            filled: true,
            fillColor: VColors.surface900,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: VSpace.x3, vertical: VSpace.x3),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(VRadius.md),
              borderSide: BorderSide(color: VColors.surface700),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(VRadius.md),
              borderSide: BorderSide(color: VColors.surface700),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(VRadius.md),
              borderSide: BorderSide(color: VColors.brand500),
            ),
          ),
        ),
      ],
    );
  }
}
