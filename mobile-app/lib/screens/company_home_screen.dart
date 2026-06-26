import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/admin_location.dart';
import '../models/admin_user.dart';
import '../models/lifecycle_status.dart';
import '../models/transaction.dart';
import '../state/company_detail_controller.dart';
import '../state/providers.dart';
import '../theme/v_colors.dart';
import '../theme/v_theme.dart';
import '../theme/v_tokens.dart';
import '../widgets/v_states.dart';
import 'admin_location_create_screen.dart';
import 'admin_staff_create_screen.dart';

/// The company-owner panel — re-platforms the legacy `src/pages/company/*`
/// surface (Dashboard, Transactions, Drivers, Locations, Team, Analytics,
/// Contracts) onto the live Spring backend, scoped to the manager's own
/// company server-side. A super-admin can also reach it (their JWT carries a
/// companyId only if they own one; otherwise they use the admin panel).
class CompanyHomeScreen extends ConsumerWidget {
  const CompanyHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final companies = ref.watch(companiesControllerProvider);

    // Prefer the JWT companyId; otherwise the first (only) company returned.
    final id = (user?.companyId != null && user!.companyId!.isNotEmpty)
        ? user.companyId
        : (companies.companies.isNotEmpty
            ? companies.companies.first.id
            : null);

    if (id == null) {
      return const Scaffold(
        backgroundColor: VColors.surface950,
        body: Center(
          child: CircularProgressIndicator(color: VColors.brand400),
        ),
      );
    }
    return _CompanyShell(companyId: id);
  }
}

class _CompanyShell extends ConsumerWidget {
  const _CompanyShell({required this.companyId});
  final String companyId;

  static const _tabs = [
    Tab(text: 'Dashboard'),
    Tab(text: 'Transactions'),
    Tab(text: 'Drivers'),
    Tab(text: 'Locations'),
    Tab(text: 'Team'),
    Tab(text: 'Analytics'),
    Tab(text: 'Contracts'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(companyDetailControllerProvider(companyId));
    final companyName = detail.company?.companyName ?? 'My Company';

    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        backgroundColor: VColors.surface950,
        appBar: AppBar(
          backgroundColor: VColors.surface950,
          elevation: 0,
          titleSpacing: VSpace.x4,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(companyName,
                  style: VType.title.copyWith(color: VColors.contentStrong)),
              const Text('Company panel', style: VType.caption),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded,
                  color: VColors.contentMuted),
              onPressed: () {
                ref.invalidate(companyHistoryProvider);
                ref
                    .read(companyDetailControllerProvider(companyId).notifier)
                    .load();
              },
            ),
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout_rounded,
                  color: VColors.contentMuted),
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).logout(),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: VColors.brand400,
            labelColor: VColors.contentStrong,
            unselectedLabelColor: VColors.contentMuted,
            labelStyle: VType.label,
            tabAlignment: TabAlignment.start,
            tabs: _tabs,
          ),
        ),
        body: TabBarView(
          children: [
            const _DashboardTab(),
            const _TransactionsTab(),
            _DriversTab(companyId: companyId),
            _LocationsTab(companyId: companyId),
            _TeamTab(companyId: companyId),
            _AnalyticsTab(companyId: companyId),
            const _ContractsTab(),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Shared helpers
// ===========================================================================

const _terminal = {LifecycleStatus.delivered, LifecycleStatus.cancelled};

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _fmtDateTime(DateTime? dt) {
  if (dt == null) return '—';
  final l = dt.toLocal();
  final h = l.hour.toString().padLeft(2, '0');
  final m = l.minute.toString().padLeft(2, '0');
  return '${_months[l.month - 1]} ${l.day}, $h:$m';
}

bool _isToday(DateTime? dt) {
  if (dt == null) return false;
  final l = dt.toLocal();
  final now = DateTime.now();
  return l.year == now.year && l.month == now.month && l.day == now.day;
}

Widget _loading() => const Center(
    child: CircularProgressIndicator(color: VColors.brand400));

Widget _error(String message, VoidCallback onRetry) => Padding(
      padding: const EdgeInsets.all(VSpace.x4),
      child: VBanner(message: message, onRetry: onRetry),
    );

/// A status chip using the lifecycle hue + label.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final LifecycleStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: VSpace.x2, vertical: VSpace.x0),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(VRadius.full),
        border: Border.all(color: status.color.withValues(alpha: 0.4)),
      ),
      child: Text(status.label,
          style: VType.caption.copyWith(
              color: status.color, fontWeight: FontWeight.w600)),
    );
  }
}

// ===========================================================================
// 1) Dashboard
// ===========================================================================

class _DashboardTab extends ConsumerWidget {
  const _DashboardTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(companyHistoryProvider);
    return history.when(
      loading: _loading,
      error: (e, _) =>
          _error('Could not load the dashboard.', () => ref.invalidate(companyHistoryProvider)),
      data: (all) {
        final active =
            all.where((t) => !_terminal.contains(t.status)).toList();
        final requested = all
            .where((t) => t.status == LifecycleStatus.requested)
            .length;
        final today = all.where((t) => _isToday(t.createdAt)).length;

        final stats = [
          _StatCardData('Active Cars', active.length.toString(),
              Icons.directions_car_filled_rounded, VColors.brand400),
          _StatCardData("Today's Check-ins", today.toString(),
              Icons.trending_up_rounded, VColors.alertSuccess),
          _StatCardData('Requested', requested.toString(),
              Icons.schedule_rounded, VColors.statusReady),
          _StatCardData('Total Transactions', all.length.toString(),
              Icons.bar_chart_rounded, VColors.brand300),
        ];

        return RefreshIndicator(
          color: VColors.brand400,
          onRefresh: () async => ref.invalidate(companyHistoryProvider),
          child: ListView(
            padding: const EdgeInsets.all(VSpace.x4),
            children: [
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: VSpace.x3,
                crossAxisSpacing: VSpace.x3,
                childAspectRatio: 1.7,
                children: [for (final s in stats) _StatCard(data: s)],
              ),
              const SizedBox(height: VSpace.x6),
              Text('Active Vehicles',
                  style:
                      VType.label.copyWith(color: VColors.contentStrong)),
              const SizedBox(height: VSpace.x2),
              if (active.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: VSpace.x6),
                  child: VEmptyState(
                    icon: Icons.local_parking_rounded,
                    headline: 'No active vehicles',
                    hint: 'Cars on the floor will show up here.',
                  ),
                )
              else
                for (final tx in active) _ActiveRow(tx: tx),
            ],
          ),
        );
      },
    );
  }
}

class _StatCardData {
  _StatCardData(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.data});
  final _StatCardData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(VSpace.x4),
      decoration: BoxDecoration(
        color: VColors.surface900,
        borderRadius: BorderRadius.circular(VRadius.lg),
        border: Border.all(color: VColors.surface700),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(data.icon, color: data.color, size: 22),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(data.value,
                  style: VType.titleLg
                      .copyWith(color: VColors.contentStrong)),
              Text(data.label, style: VType.caption),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActiveRow extends StatelessWidget {
  const _ActiveRow({required this.tx});
  final Transaction tx;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: VSpace.x2),
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
                Text(tx.carPlate,
                    style: VType.body.copyWith(
                        color: VColors.contentStrong,
                        fontWeight: FontWeight.w600)),
                Text(tx.guestName ?? 'Guest', style: VType.caption),
              ],
            ),
          ),
          _StatusChip(status: tx.status),
        ],
      ),
    );
  }
}

// ===========================================================================
// 2) Transactions (full history)
// ===========================================================================

class _TransactionsTab extends ConsumerWidget {
  const _TransactionsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(companyHistoryProvider);
    return history.when(
      loading: _loading,
      error: (e, _) => _error('Could not load transactions.',
          () => ref.invalidate(companyHistoryProvider)),
      data: (all) {
        if (all.isEmpty) {
          return const VEmptyState(
            icon: Icons.receipt_long_rounded,
            headline: 'No transactions yet',
            hint: 'Completed and active cars will appear here.',
          );
        }
        return RefreshIndicator(
          color: VColors.brand400,
          onRefresh: () async => ref.invalidate(companyHistoryProvider),
          child: ListView.separated(
            padding: const EdgeInsets.all(VSpace.x4),
            itemCount: all.length,
            separatorBuilder: (_, __) => const SizedBox(height: VSpace.x2),
            itemBuilder: (_, i) => _TxRow(tx: all[i]),
          ),
        );
      },
    );
  }
}

class _TxRow extends StatelessWidget {
  const _TxRow({required this.tx});
  final Transaction tx;

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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(tx.carPlate,
                        style: VType.body.copyWith(
                            color: VColors.contentStrong,
                            fontWeight: FontWeight.w600)),
                    if (tx.keyCode != null) ...[
                      const SizedBox(width: VSpace.x2),
                      Text('· ${tx.keyCode}', style: VType.caption),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    tx.guestName ?? 'Guest',
                    if (tx.guestPhone != null) tx.guestPhone!,
                  ].join('  ·  '),
                  style: VType.caption,
                ),
                Text(_fmtDateTime(tx.createdAt),
                    style: VType.caption
                        .copyWith(color: VColors.contentFaint)),
              ],
            ),
          ),
          _StatusChip(status: tx.status),
        ],
      ),
    );
  }
}

// ===========================================================================
// 3) Drivers / 5) Team — both reuse the company-detail people slice
// ===========================================================================

class _DriversTab extends ConsumerWidget {
  const _DriversTab({required this.companyId});
  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _PeopleList(companyId: companyId, isDriver: true);
}

class _TeamTab extends ConsumerWidget {
  const _TeamTab({required this.companyId});
  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _PeopleList(companyId: companyId, isDriver: false);
}

class _PeopleList extends ConsumerWidget {
  const _PeopleList({required this.companyId, required this.isDriver});
  final String companyId;
  final bool isDriver;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(companyDetailControllerProvider(companyId));
    final notifier =
        ref.read(companyDetailControllerProvider(companyId).notifier);
    final noun = isDriver ? 'driver' : 'team member';

    Future<void> add() => AdminStaffSheet.show(
          context,
          role: isDriver ? 'driver' : 'valet',
          locations: state.locations,
          onSubmit: notifier.addStaff,
          errorReader: () => notifier.createError,
        );

    if (state.status == DetailStatus.loading) return _loading();
    if (state.status == DetailStatus.error) {
      return _error('Could not load $noun list.', notifier.load);
    }

    final people = isDriver ? state.drivers : state.operators;
    if (people.isEmpty) {
      return _AddScaffold(
        label: 'Add $noun',
        onAdd: add,
        child: VEmptyState(
          icon: isDriver ? Icons.person_off_outlined : Icons.badge_outlined,
          headline: 'No ${noun}s yet',
          hint: 'Add a $noun login to get going.',
          actionLabel: 'Add $noun',
          onAction: add,
        ),
      );
    }

    return _AddScaffold(
      label: 'Add $noun',
      onAdd: add,
      child: ListView.separated(
        padding: const EdgeInsets.all(VSpace.x4),
        itemCount: people.length,
        separatorBuilder: (_, __) => const SizedBox(height: VSpace.x2),
        itemBuilder: (_, i) => _PersonRow(user: people[i]),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.user});
  final AdminUser user;

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
          CircleAvatar(
            radius: 18,
            backgroundColor: VColors.brand900,
            child: Text(
              (user.name ?? user.email).characters.first.toUpperCase(),
              style: VType.label.copyWith(color: VColors.brand300),
            ),
          ),
          const SizedBox(width: VSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.name ?? user.email,
                    style: VType.body
                        .copyWith(color: VColors.contentStrong)),
                Text(user.email, style: VType.caption),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: VSpace.x2, vertical: VSpace.x0),
            decoration: BoxDecoration(
              color: (user.active ? VColors.alertSuccess : VColors.contentFaint)
                  .withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(VRadius.full),
            ),
            child: Text(user.role,
                style: VType.caption.copyWith(
                    color: user.active
                        ? VColors.alertSuccess
                        : VColors.contentFaint)),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// 4) Locations
// ===========================================================================

class _LocationsTab extends ConsumerWidget {
  const _LocationsTab({required this.companyId});
  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(companyDetailControllerProvider(companyId));
    final notifier =
        ref.read(companyDetailControllerProvider(companyId).notifier);

    Future<void> add() => AdminLocationSheet.show(
          context,
          onSubmit: notifier.addLocation,
          errorReader: () => notifier.createError,
        );
    Future<void> edit(AdminLocation loc) => AdminLocationSheet.show(
          context,
          onSubmit: (input) => notifier.editLocation(loc.id, input),
          errorReader: () => notifier.createError,
          existing: loc,
        );

    if (state.status == DetailStatus.loading) return _loading();
    if (state.status == DetailStatus.error) {
      return _error('Could not load locations.', notifier.load);
    }

    if (state.locations.isEmpty) {
      return _AddScaffold(
        label: 'Add location',
        onAdd: add,
        child: VEmptyState(
          icon: Icons.location_off_outlined,
          headline: 'No locations yet',
          hint: 'Add your first valet location.',
          actionLabel: 'Add location',
          onAction: add,
        ),
      );
    }

    return _AddScaffold(
      label: 'Add location',
      onAdd: add,
      child: ListView.separated(
        padding: const EdgeInsets.all(VSpace.x4),
        itemCount: state.locations.length,
        separatorBuilder: (_, __) => const SizedBox(height: VSpace.x2),
        itemBuilder: (_, i) {
          final loc = state.locations[i];
          return _LocationRow(loc: loc, onEdit: () => edit(loc));
        },
      ),
    );
  }
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({required this.loc, required this.onEdit});
  final AdminLocation loc;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final addr = [loc.address, loc.city, loc.state]
        .where((p) => p != null && p.isNotEmpty)
        .join(', ');
    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(VRadius.md),
      child: Container(
        padding: const EdgeInsets.all(VSpace.x3),
        decoration: BoxDecoration(
          color: VColors.surface900,
          borderRadius: BorderRadius.circular(VRadius.md),
          border: Border.all(color: VColors.surface700),
        ),
        child: Row(
          children: [
            const Icon(Icons.location_on_rounded,
                color: VColors.brand400, size: 20),
            const SizedBox(width: VSpace.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(loc.name,
                      style: VType.body
                          .copyWith(color: VColors.contentStrong)),
                  if (addr.isNotEmpty)
                    Text(addr, style: VType.caption),
                  Text('${loc.keyCapacity} key slots',
                      style: VType.caption
                          .copyWith(color: VColors.contentFaint)),
                ],
              ),
            ),
            const Icon(Icons.edit_outlined,
                color: VColors.contentMuted, size: 18),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// 6) Analytics — driver + location performance, computed from history
// ===========================================================================

class _AnalyticsTab extends ConsumerStatefulWidget {
  const _AnalyticsTab({required this.companyId});
  final String companyId;

  @override
  ConsumerState<_AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends ConsumerState<_AnalyticsTab> {
  int _sub = 0; // 0 = drivers, 1 = locations

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(companyHistoryProvider);
    final detail =
        ref.watch(companyDetailControllerProvider(widget.companyId));

    return history.when(
      loading: _loading,
      error: (e, _) => _error('Could not load analytics.',
          () => ref.invalidate(companyHistoryProvider)),
      data: (all) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(VSpace.x4),
              child: Row(
                children: [
                  _SubTab(
                      label: 'Drivers',
                      selected: _sub == 0,
                      onTap: () => setState(() => _sub = 0)),
                  const SizedBox(width: VSpace.x2),
                  _SubTab(
                      label: 'Locations',
                      selected: _sub == 1,
                      onTap: () => setState(() => _sub = 1)),
                ],
              ),
            ),
            Expanded(
              child: _sub == 0
                  ? _DriverPerformance(all: all, drivers: detail.drivers)
                  : _LocationPerformance(
                      all: all, locations: detail.locations),
            ),
          ],
        );
      },
    );
  }
}

class _SubTab extends StatelessWidget {
  const _SubTab(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(VRadius.full),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: VSpace.x4, vertical: VSpace.x2),
        decoration: BoxDecoration(
          color: selected
              ? VColors.brand500.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(VRadius.full),
          border: Border.all(
              color: selected ? VColors.brand500 : VColors.surface700),
        ),
        child: Text(label,
            style: VType.label.copyWith(
                color: selected
                    ? VColors.brand300
                    : VColors.contentMuted)),
      ),
    );
  }
}

class _PerfRow {
  _PerfRow(this.name);
  final String name;
  int total = 0;
  int delivered = 0;
}

class _DriverPerformance extends StatelessWidget {
  const _DriverPerformance({required this.all, required this.drivers});
  final List<Transaction> all;
  final List<AdminUser> drivers;

  @override
  Widget build(BuildContext context) {
    final names = {for (final d in drivers) d.id: (d.name ?? d.email)};
    final rows = <String, _PerfRow>{};
    for (final t in all) {
      final id = t.retrievedByDriverId ?? t.parkedByDriverId;
      if (id == null) continue;
      final r = rows.putIfAbsent(id, () => _PerfRow(names[id] ?? 'Driver'));
      r.total++;
      if (t.status == LifecycleStatus.delivered) r.delivered++;
    }
    final list = rows.values.toList()
      ..sort((a, b) => b.delivered.compareTo(a.delivered));

    if (list.isEmpty) {
      return const VEmptyState(
        icon: Icons.insights_rounded,
        headline: 'No driver activity yet',
        hint: 'Completed retrievals will tally here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(VSpace.x4, 0, VSpace.x4, VSpace.x4),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: VSpace.x2),
      itemBuilder: (_, i) => _PerfTile(
        title: list[i].name,
        primary: '${list[i].delivered} delivered',
        secondary: '${list[i].total} total',
      ),
    );
  }
}

class _LocationPerformance extends StatelessWidget {
  const _LocationPerformance({required this.all, required this.locations});
  final List<Transaction> all;
  final List<AdminLocation> locations;

  @override
  Widget build(BuildContext context) {
    final names = {for (final l in locations) l.id: l.name};
    final rows = <String, _PerfRow>{};
    for (final t in all) {
      final id = t.locationId;
      if (id == null) continue;
      final r = rows.putIfAbsent(id, () => _PerfRow(names[id] ?? 'Location'));
      r.total++;
      if (t.status == LifecycleStatus.delivered) r.delivered++;
    }
    final list = rows.values.toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    if (list.isEmpty) {
      return const VEmptyState(
        icon: Icons.insights_rounded,
        headline: 'No location activity yet',
        hint: 'Transactions per location will tally here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(VSpace.x4, 0, VSpace.x4, VSpace.x4),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: VSpace.x2),
      itemBuilder: (_, i) => _PerfTile(
        title: list[i].name,
        primary: '${list[i].total} transactions',
        secondary: '${list[i].delivered} delivered',
      ),
    );
  }
}

class _PerfTile extends StatelessWidget {
  const _PerfTile(
      {required this.title, required this.primary, required this.secondary});
  final String title;
  final String primary;
  final String secondary;

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
          Expanded(
            child: Text(title,
                style: VType.body.copyWith(color: VColors.contentStrong)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(primary,
                  style: VType.label.copyWith(color: VColors.brand300)),
              Text(secondary, style: VType.caption),
            ],
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// 7) Contracts — list (no contracts backend yet → graceful empty state)
// ===========================================================================

class _ContractsTab extends StatelessWidget {
  const _ContractsTab();

  @override
  Widget build(BuildContext context) {
    return const VEmptyState(
      icon: Icons.description_outlined,
      headline: 'No contracts yet',
      hint:
          'Contract management is coming next. Your client and venue agreements will live here.',
    );
  }
}

// ===========================================================================
// Add-action scaffold (floating action button over a tab body)
// ===========================================================================

class _AddScaffold extends StatelessWidget {
  const _AddScaffold(
      {required this.child, required this.label, required this.onAdd});
  final Widget child;
  final String label;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: child,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: VColors.brand500,
        foregroundColor: VColors.contentOnAccent,
        onPressed: onAdd,
        icon: const Icon(Icons.add_rounded),
        label: Text(label, style: VType.label),
      ),
    );
  }
}
