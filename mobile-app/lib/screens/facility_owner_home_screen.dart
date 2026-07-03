import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/admin_location.dart';
import '../models/lifecycle_status.dart';
import '../models/transaction.dart';
import '../state/providers.dart';
import '../theme/v_colors.dart';
import '../theme/v_theme.dart';
import '../theme/v_tokens.dart';
import '../utils/qr_sheet.dart' as qr_util;
import '../widgets/v_states.dart';

class FacilityOwnerHomeScreen extends ConsumerStatefulWidget {
  const FacilityOwnerHomeScreen({super.key});

  @override
  ConsumerState<FacilityOwnerHomeScreen> createState() =>
      _FacilityOwnerHomeScreenState();
}

class _FacilityOwnerHomeScreenState
    extends ConsumerState<FacilityOwnerHomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    if (user == null) return Scaffold(backgroundColor: VColors.surface950, body: const SizedBox.shrink());
    final locAsync = ref.watch(facilityOwnerLocationsProvider);
    final txAsync = ref.watch(facilityOwnerTransactionsProvider);
    final histAsync = ref.watch(facilityOwnerHistoryProvider);

    final locations = locAsync.valueOrNull ?? [];
    final locationMap = {for (final l in locations) l.id: l.name};
    final locationName = locations.length == 1
        ? locations.first.name
        : locations.isEmpty
            ? 'Facility Owner'
            : '${locations.length} locations';

    return Scaffold(
      backgroundColor: VColors.surface950,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  VSpace.x5, VSpace.x5, VSpace.x5, VSpace.x3),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: VColors.brand900,
                      borderRadius: BorderRadius.circular(VRadius.md),
                    ),
                    child: Icon(Icons.domain_rounded,
                        size: 20, color: VColors.brand300),
                  ),
                  const SizedBox(width: VSpace.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.displayName,
                            style: VType.label
                                .copyWith(color: VColors.contentStrong),
                            overflow: TextOverflow.ellipsis),
                        Text(locationName,
                            style:
                                VType.caption.copyWith(color: VColors.brand400),
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Guest QR',
                    icon: Icon(Icons.qr_code_rounded,
                        color: VColors.contentMuted, size: 20),
                    onPressed: () => _showQr(context, locations),
                  ),
                  IconButton(
                    onPressed: () =>
                        ref.read(authControllerProvider.notifier).logout(),
                    icon: Icon(Icons.logout_rounded,
                        color: VColors.contentMuted, size: 20),
                    tooltip: 'Sign out',
                  ),
                ],
              ),
            ),

            // KPI strip
            txAsync.when(
              loading: () => const SizedBox(height: 80),
              error: (_, __) => const SizedBox.shrink(),
              data: (txs) => _KpiStrip(transactions: txs, locationCount: locations.length),
            ),

            const SizedBox(height: VSpace.x3),
            const Divider(height: 1),

            // Tab bar
            TabBar(
              controller: _tabs,
              indicatorColor: VColors.brand400,
              labelColor: VColors.brand300,
              unselectedLabelColor: VColors.contentMuted,
              labelStyle: VType.label,
              unselectedLabelStyle: VType.label,
              tabs: const [
                Tab(text: 'Live'),
                Tab(text: 'History'),
              ],
            ),

            const Divider(height: 1),

            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  // Live tab
                  txAsync.when(
                    loading: () => Center(
                        child: CircularProgressIndicator(
                            color: VColors.brand400)),
                    error: (e, _) => Padding(
                      padding: const EdgeInsets.all(VSpace.x4),
                      child: VBanner(
                        message: 'Could not load live transactions.',
                        onRetry: () =>
                            ref.refresh(facilityOwnerTransactionsProvider),
                      ),
                    ),
                    data: (txs) => txs.isEmpty
                        ? const VEmptyState(
                            icon: Icons.directions_car_outlined,
                            headline: 'No active cars',
                            hint: 'New check-ins will appear here.',
                          )
                        : _TxList(
                            transactions: txs,
                            locationMap: locationMap,
                            onRefresh: () =>
                                ref.refresh(facilityOwnerTransactionsProvider.future)),
                  ),
                  // History tab
                  histAsync.when(
                    loading: () => Center(
                        child: CircularProgressIndicator(
                            color: VColors.brand400)),
                    error: (e, _) => Padding(
                      padding: const EdgeInsets.all(VSpace.x4),
                      child: VBanner(
                        message: 'Could not load history.',
                        onRetry: () =>
                            ref.refresh(facilityOwnerHistoryProvider),
                      ),
                    ),
                    data: (txs) => txs.isEmpty
                        ? const VEmptyState(
                            icon: Icons.history_rounded,
                            headline: 'No history yet',
                            hint: 'Completed transactions will show here.',
                          )
                        : _TxList(
                            transactions: txs,
                            locationMap: locationMap,
                            onRefresh: () =>
                                ref.refresh(facilityOwnerHistoryProvider.future)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showQr(BuildContext context, List<AdminLocation> locations) {
    if (locations.isEmpty) {
      qr_util.showQrSheet(context, 'Facility Owner');
      return;
    }
    if (locations.length == 1) {
      qr_util.showQrSheet(context, locations.first.name);
      return;
    }
    // Multiple locations — let them pick which label to use.
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: VColors.surface900,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(VRadius.xl)),
          border: Border(top: BorderSide(color: VColors.surface700)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(VSpace.x5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: VSpace.x4),
                    decoration: BoxDecoration(
                      color: VColors.surface600,
                      borderRadius: BorderRadius.circular(VRadius.full),
                    ),
                  ),
                ),
                Text('Select location',
                    style: VType.title.copyWith(color: VColors.contentStrong)),
                const SizedBox(height: VSpace.x4),
                ...locations.map((loc) => ListTile(
                      leading: Icon(Icons.place_rounded,
                          color: VColors.brand300, size: 20),
                      title: Text(loc.name,
                          style: VType.label
                              .copyWith(color: VColors.contentStrong)),
                      onTap: () {
                        Navigator.of(context).pop();
                        qr_util.showQrSheet(context, loc.name);
                      },
                    )),
                const SizedBox(height: VSpace.x2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// KPI strip — 4 stat tiles
// ---------------------------------------------------------------------------

class _KpiStrip extends StatelessWidget {
  const _KpiStrip({required this.transactions, required this.locationCount});
  final List<Transaction> transactions;
  final int locationCount;

  @override
  Widget build(BuildContext context) {
    final parked = transactions
        .where((t) =>
            t.status == LifecycleStatus.parked ||
            t.status == LifecycleStatus.keyIn)
        .length;
    final pending = transactions
        .where((t) => t.status == LifecycleStatus.requested)
        .length;
    final onWay = transactions
        .where((t) =>
            t.status == LifecycleStatus.driverAssigned ||
            t.status == LifecycleStatus.enRoute ||
            t.status == LifecycleStatus.arrived)
        .length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(VSpace.x4, VSpace.x1, VSpace.x4, 0),
      child: Row(
        children: [
          Expanded(
              child: _KpiTile(
                  label: 'Locations',
                  value: '$locationCount',
                  color: VColors.brand400,
                  icon: Icons.place_rounded)),
          const SizedBox(width: VSpace.x2),
          Expanded(
              child: _KpiTile(
                  label: 'Parked',
                  value: '$parked',
                  color: VColors.statusSettled,
                  icon: Icons.local_parking_rounded)),
          const SizedBox(width: VSpace.x2),
          Expanded(
              child: _KpiTile(
                  label: 'Pending',
                  value: '$pending',
                  color: VColors.statusActive,
                  icon: Icons.notifications_active_rounded)),
          const SizedBox(width: VSpace.x2),
          Expanded(
              child: _KpiTile(
                  label: 'On way',
                  value: '$onWay',
                  color: VColors.statusMoving,
                  icon: Icons.directions_rounded)),
        ],
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile(
      {required this.label,
      required this.value,
      required this.color,
      required this.icon});
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: VSpace.x2, vertical: VSpace.x3),
      decoration: BoxDecoration(
        color: VColors.surface900,
        borderRadius: BorderRadius.circular(VRadius.md),
        border: Border.all(color: VColors.surface700),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 4),
          Text(value,
              style: VType.title
                  .copyWith(color: VColors.contentStrong, fontSize: 20)),
          Text(label,
              style: VType.caption.copyWith(fontSize: 10),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Transaction list (shared by Live and History tabs)
// ---------------------------------------------------------------------------

class _TxList extends StatelessWidget {
  const _TxList(
      {required this.transactions,
      required this.locationMap,
      required this.onRefresh});
  final List<Transaction> transactions;
  final Map<String, String> locationMap;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: VColors.brand400,
      backgroundColor: VColors.surface800,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
            VSpace.x4, VSpace.x3, VSpace.x4, VSpace.x8),
        itemCount: transactions.length,
        separatorBuilder: (_, __) => const SizedBox(height: VSpace.x2),
        itemBuilder: (_, i) => _TxCard(
            tx: transactions[i], locationMap: locationMap),
      ),
    );
  }
}

class _TxCard extends StatelessWidget {
  const _TxCard({required this.tx, required this.locationMap});
  final Transaction tx;
  final Map<String, String> locationMap;

  @override
  Widget build(BuildContext context) {
    final status = tx.status;
    final color = status.color;
    final vehicle = [tx.carColor, tx.carMake, tx.carModel]
        .where((p) => p != null && p.isNotEmpty)
        .map((p) => p!)
        .join(' ');

    return Container(
      padding: const EdgeInsets.all(VSpace.x4),
      decoration: BoxDecoration(
        color: VColors.surface900,
        borderRadius: BorderRadius.circular(VRadius.lg),
        border: Border.all(color: VColors.surface700),
      ),
      child: Row(
        children: [
          // Status accent bar
          Container(
            width: 3,
            height: 42,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: VSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(tx.carPlate,
                        style: VType.label
                            .copyWith(color: VColors.contentStrong)),
                    const SizedBox(width: VSpace.x2),
                    if (tx.keyCode != null)
                      Text('· Slot ${tx.keyCode}',
                          style: VType.caption
                              .copyWith(color: VColors.contentMuted)),
                  ],
                ),
                if (vehicle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(vehicle,
                      style: VType.caption,
                      overflow: TextOverflow.ellipsis),
                ],
                if (tx.locationId != null &&
                    locationMap.containsKey(tx.locationId) &&
                    locationMap.length > 1) ...[
                  const SizedBox(height: 3),
                  Row(children: [
                    Icon(Icons.place_rounded,
                        size: 11, color: VColors.brand400),
                    const SizedBox(width: 3),
                    Text(locationMap[tx.locationId] ?? '',
                        style: VType.caption
                            .copyWith(color: VColors.brand400, fontSize: 11),
                        overflow: TextOverflow.ellipsis),
                  ]),
                ],
                if (tx.guestName != null && tx.guestName!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(tx.guestName!,
                      style: VType.caption
                          .copyWith(color: VColors.contentMuted),
                      overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          const SizedBox(width: VSpace.x3),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: VSpace.x2, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(VRadius.sm),
                ),
                child: Text(status.label,
                    style: VType.caption.copyWith(
                        color: color, fontWeight: FontWeight.w600)),
              ),
              if (tx.createdAt != null) ...[
                const SizedBox(height: 4),
                Text(_elapsed(tx.createdAt!),
                    style:
                        VType.caption.copyWith(color: VColors.contentMuted)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _elapsed(DateTime createdAt) {
    final diff = DateTime.now().difference(createdAt.toLocal());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
