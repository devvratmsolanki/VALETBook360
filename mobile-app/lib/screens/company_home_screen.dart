import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/admin_location.dart';
import '../models/admin_user.dart';
import '../models/contract.dart';
import '../models/lifecycle_status.dart';
import '../models/transaction.dart';
import '../state/companies_controller.dart';
import '../state/company_detail_controller.dart';
import '../state/providers.dart';
import '../theme/v_breakpoints.dart';
import '../theme/v_colors.dart';
import '../theme/v_theme.dart';
import '../theme/v_tokens.dart';
import '../widgets/app_logo.dart';
import '../widgets/theme_toggle_button.dart';
import '../widgets/v_primary_button.dart';
import '../widgets/v_states.dart';
import '../utils/qr_sheet.dart' as qr_util;
import 'admin_location_create_screen.dart';
import 'admin_staff_create_screen.dart';
import 'location_detail_screen.dart';

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
      final isError = companies.status == CompaniesStatus.error;
      return Scaffold(
        backgroundColor: VColors.surface950,
        body: Center(
          child: isError
              ? Padding(
                  padding: const EdgeInsets.all(32),
                  child: VBanner(
                    message: companies.error ?? 'Could not load company. Please try again.',
                    onRetry: () => ref.read(companiesControllerProvider.notifier).load(),
                  ),
                )
              : CircularProgressIndicator(color: VColors.brand400),
        ),
      );
    }
    return _CompanyShell(companyId: id);
  }
}

class _CompanyShell extends ConsumerStatefulWidget {
  const _CompanyShell({required this.companyId});
  final String companyId;

  @override
  ConsumerState<_CompanyShell> createState() => _CompanyShellState();
}

class _CompanyShellState extends ConsumerState<_CompanyShell> {
  int _index = 0;

  static const _titles = [
    'Dashboard',
    'Transactions',
    'Staff',
    'Locations',
    'More',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatbotBottomOffsetProvider.notifier).state = 168.0;
    });
  }

  @override
  void dispose() {
    ref.read(chatbotBottomOffsetProvider.notifier).state = 88.0;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(companyDetailControllerProvider(widget.companyId));
    final companyName = detail.company?.companyName ?? 'My Company';

    return Scaffold(
      backgroundColor: VColors.surface950,
      appBar: AppBar(
        backgroundColor: VColors.surface950,
        elevation: 0,
        titleSpacing: 0,
        leadingWidth: 116,
        leading: const Padding(
          padding: EdgeInsets.only(left: VSpace.x4),
          child: Align(alignment: Alignment.centerLeft, child: AppLogo()),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(companyName,
                style: VType.title.copyWith(color: VColors.contentStrong)),
            Text(_titles[_index], style: VType.caption),
          ],
        ),
        actions: [
          const ThemeToggleButton(),
          IconButton(
            tooltip: 'Refresh',
            icon: Icon(Icons.refresh_rounded, color: VColors.contentMuted),
            onPressed: () {
              ref.invalidate(companyHistoryProvider);
              ref
                  .read(companyDetailControllerProvider(widget.companyId).notifier)
                  .load();
            },
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: Icon(Icons.logout_rounded, color: VColors.contentMuted),
            onPressed: () =>
                ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: IndexedStack(
          index: _index,
          children: [
            _DashboardTab(companyId: widget.companyId),
            const _TransactionsTab(),
            _StaffPane(companyId: widget.companyId),
            _LocationsTab(companyId: widget.companyId),
            _MorePane(companyId: widget.companyId),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: VColors.surface900,
        indicatorColor: VColors.brand900,
        selectedIndex: _index,
        height: VTarget.navBar,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Transactions',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline_rounded),
            selectedIcon: Icon(Icons.people_rounded),
            label: 'Staff',
          ),
          NavigationDestination(
            icon: Icon(Icons.place_outlined),
            selectedIcon: Icon(Icons.place_rounded),
            label: 'Locations',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz_rounded),
            selectedIcon: Icon(Icons.more_horiz_rounded),
            label: 'More',
          ),
        ],
      ),
    );
  }
}

/// Staff pane — Drivers and Team (operators) with a toggle. Combines the old
/// Drivers + Team top tabs into one bottom-nav destination.
class _StaffPane extends ConsumerStatefulWidget {
  const _StaffPane({required this.companyId});
  final String companyId;

  @override
  ConsumerState<_StaffPane> createState() => _StaffPaneState();
}

class _StaffPaneState extends ConsumerState<_StaffPane> {
  bool _showDrivers = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              VSpace.x4, VSpace.x4, VSpace.x4, 0),
          child: Row(
            children: [
              _SubTab(
                label: 'Drivers',
                selected: _showDrivers,
                onTap: () => setState(() => _showDrivers = true),
              ),
              const SizedBox(width: VSpace.x2),
              _SubTab(
                label: 'Team',
                selected: !_showDrivers,
                onTap: () => setState(() => _showDrivers = false),
              ),
            ],
          ),
        ),
        Expanded(
          child: _PeopleList(
            companyId: widget.companyId,
            isDriver: _showDrivers,
          ),
        ),
      ],
    );
  }
}

/// More pane — Analytics and Contracts with a toggle.
class _MorePane extends ConsumerStatefulWidget {
  const _MorePane({required this.companyId});
  final String companyId;

  @override
  ConsumerState<_MorePane> createState() => _MorePaneState();
}

class _MorePaneState extends ConsumerState<_MorePane> {
  int _tab = 0; // 0=Analytics 1=Contracts 2=Facility Owners

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              VSpace.x4, VSpace.x4, VSpace.x4, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _SubTab(
                  label: 'Analytics',
                  selected: _tab == 0,
                  onTap: () => setState(() => _tab = 0),
                ),
                const SizedBox(width: VSpace.x2),
                _SubTab(
                  label: 'Contracts',
                  selected: _tab == 1,
                  onTap: () => setState(() => _tab = 1),
                ),
                const SizedBox(width: VSpace.x2),
                _SubTab(
                  label: 'Facility Owners',
                  selected: _tab == 2,
                  onTap: () => setState(() => _tab = 2),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _tab == 0
              ? _AnalyticsTab(companyId: widget.companyId)
              : _tab == 1
                  ? _ContractsTab(companyId: widget.companyId)
                  : _FacilityOwnersList(companyId: widget.companyId),
        ),
      ],
    );
  }
}

// ===========================================================================
// Shared helpers
// ===========================================================================

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

Widget _loading() => Center(
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
  const _DashboardTab({required this.companyId});
  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(companyHistoryProvider);
    final detail = ref.watch(companyDetailControllerProvider(companyId));
    final locNames = {
      for (final l in detail.locations) l.id: l.name,
    };
    final driverNames = {
      for (final d in detail.drivers) d.id: (d.name ?? d.email),
    };
    return history.when(
      loading: _loading,
      error: (e, _) =>
          _error('Could not load the dashboard.', () => ref.invalidate(companyHistoryProvider)),
      data: (all) {
        // ponytail: single O(n) pass replaces 8 separate passes + intermediate
        // list allocations. All accumulators are filled in one loop.
        final active = <Transaction>[];
        final delivered = <Transaction>[];
        int requestedCount = 0, todayCount = 0, cancelledCount = 0;
        int timedSecs = 0, timedCount = 0;
        final byLoc = <String, int>{};    // active-only, for location chips
        final locTotals = <String, int>{}; // all statuses, for analytics bar
        final drvDelivered = <String, int>{};
        final weekVolume = List.filled(7, 0);
        final hourCounts = <int, int>{};
        final now = DateTime.now();

        for (final t in all) {
          final status = t.status;
          final isDelivered = status == LifecycleStatus.delivered;
          final isCancelled = status == LifecycleStatus.cancelled;
          final isTerminal = isDelivered || isCancelled;
          final locName = locNames[t.locationId] ?? 'Unassigned';

          locTotals[locName] = (locTotals[locName] ?? 0) + 1;

          if (!isTerminal) {
            active.add(t);
            byLoc[locName] = (byLoc[locName] ?? 0) + 1;
          }
          if (isDelivered) {
            delivered.add(t);
            final drvId = t.retrievedByDriverId ?? t.parkedByDriverId;
            if (drvId != null) {
              drvDelivered[drvId] = (drvDelivered[drvId] ?? 0) + 1;
            }
            if (t.requestedAt != null && t.deliveredAt != null) {
              timedSecs += t.deliveredAt!.difference(t.requestedAt!).inSeconds.abs();
              timedCount++;
            }
          }
          if (isCancelled) cancelledCount++;
          if (status == LifecycleStatus.requested) requestedCount++;
          if (_isToday(t.createdAt)) todayCount++;

          if (t.createdAt != null) {
            final local = t.createdAt!.toLocal();
            final diff = now.difference(local).inDays;
            if (diff >= 0 && diff < 7) weekVolume[diff]++;
            hourCounts[local.hour] = (hourCounts[local.hour] ?? 0) + 1;
          }
        }

        // Post-loop derived values (O(k) where k is small).
        final completionPct = all.isEmpty
            ? 0
            : ((delivered.length / all.length) * 100).round();
        String avgRetrieval = '—';
        if (timedCount > 0) {
          final avgSecs = timedSecs / timedCount;
          avgRetrieval = avgSecs < 60 ? '< 1 min' : '${(avgSecs / 60).round()} min';
        }
        final byLocSorted = byLoc.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final top5 = (drvDelivered.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .take(5)
            .toList();
        final locsByVolume = locTotals.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final maxLocVol = locsByVolume.isEmpty ? 1 : locsByVolume.first.value;
        final peakHours = (hourCounts.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .take(5)
            .toList();
        final maxPeak = peakHours.isEmpty ? 1 : peakHours.first.value;

        // Alias to match widget references below.
        final requested = requestedCount;
        final today = todayCount;
        final cancelled = cancelledCount;

        final stats = [
          _StatCardData('Active Cars', active.length.toString(),
              Icons.directions_car_filled_rounded, VColors.brand400),
          _StatCardData("Today's Check-ins", today.toString(),
              Icons.trending_up_rounded, VColors.alertSuccess),
          _StatCardData('Requested', requested.toString(),
              Icons.schedule_rounded, VColors.statusReady),
          _StatCardData('Completion', '$completionPct%',
              Icons.check_circle_outline_rounded, VColors.brand300),
        ];

        return RefreshIndicator(
          color: VColors.brand400,
          onRefresh: () async => ref.invalidate(companyHistoryProvider),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: context.dashboardMaxWidth),
              child: ListView(
                padding: const EdgeInsets.all(VSpace.x4),
                children: [
                  // KPI grid
                  GridView.count(
                    crossAxisCount:
                        context.responsive(compact: 2, expanded: 3, large: 4),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: VSpace.x3,
                    crossAxisSpacing: VSpace.x3,
                    childAspectRatio:
                        context.responsive(compact: 1.7, expanded: 2.0, large: 2.2),
                    children: [for (final s in stats) _StatCard(data: s)],
                  ),
                  // Avg retrieval time inline
                  if (timedCount > 0) ...[
                    const SizedBox(height: VSpace.x3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: VSpace.x4, vertical: VSpace.x3),
                      decoration: BoxDecoration(
                        color: VColors.surface900,
                        borderRadius: BorderRadius.circular(VRadius.md),
                        border: Border.all(color: VColors.surface700),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.timer_outlined,
                              size: 16, color: VColors.contentMuted),
                          const SizedBox(width: VSpace.x2),
                          Text('Avg retrieval time',
                              style: VType.caption
                                  .copyWith(color: VColors.contentMuted)),
                          const Spacer(),
                          Text(avgRetrieval,
                              style: VType.label
                                  .copyWith(color: VColors.contentStrong)),
                        ],
                      ),
                    ),
                  ],

                  // 7-day bar chart
                  const SizedBox(height: VSpace.x6),
                  Text('7-day check-in volume',
                      style: VType.label
                          .copyWith(color: VColors.contentStrong)),
                  const SizedBox(height: VSpace.x3),
                  _WeekBarChart(dailyCounts: weekVolume),

                  // Analytics
                  const SizedBox(height: VSpace.x6),
                  Text('Analytics',
                      style: VType.label
                          .copyWith(color: VColors.contentStrong)),
                  const SizedBox(height: VSpace.x3),
                  _AnalyticsCard(
                    title: 'Status breakdown',
                    children: all.isEmpty
                        ? [Text('No data yet', style: VType.caption)]
                        : [
                            _HBarRow(label: 'Active', value: active.length, maxVal: all.length, color: VColors.brand400),
                            _HBarRow(label: 'Delivered', value: delivered.length, maxVal: all.length, color: VColors.alertSuccess),
                            _HBarRow(label: 'Requested', value: requested, maxVal: all.length, color: VColors.statusReady),
                            _HBarRow(label: 'Cancelled', value: cancelled, maxVal: all.length, color: VColors.alertDanger),
                          ],
                  ),
                  if (locsByVolume.isNotEmpty) ...[
                    const SizedBox(height: VSpace.x3),
                    _AnalyticsCard(
                      title: 'Volume by location',
                      children: [
                        for (final e in locsByVolume)
                          _HBarRow(label: e.key, value: e.value, maxVal: maxLocVol, color: VColors.brand400),
                      ],
                    ),
                  ],
                  if (peakHours.isNotEmpty) ...[
                    const SizedBox(height: VSpace.x3),
                    _AnalyticsCard(
                      title: 'Peak check-in hours',
                      children: [
                        for (final e in peakHours)
                          _HBarRow(
                            label: '${e.key}:00 – ${(e.key + 1) % 24}:00',
                            value: e.value,
                            maxVal: maxPeak,
                            color: VColors.statusReady,
                          ),
                      ],
                    ),
                  ],

                  // Active by Location
                  if (byLocSorted.isNotEmpty) ...[
                    const SizedBox(height: VSpace.x6),
                    Text('Active by Location',
                        style: VType.label
                            .copyWith(color: VColors.contentStrong)),
                    const SizedBox(height: VSpace.x2),
                    Wrap(
                      spacing: VSpace.x2,
                      runSpacing: VSpace.x2,
                      children: [
                        for (final e in byLocSorted)
                          _LocationActiveChip(name: e.key, count: e.value),
                      ],
                    ),
                  ],

                  // Driver leaderboard
                  if (top5.isNotEmpty) ...[
                    const SizedBox(height: VSpace.x6),
                    Text('Top drivers',
                        style: VType.label
                            .copyWith(color: VColors.contentStrong)),
                    const SizedBox(height: VSpace.x2),
                    for (var i = 0; i < top5.length; i++)
                      _LeaderboardRow(
                        rank: i + 1,
                        name: driverNames[top5[i].key] ?? 'Driver',
                        delivered: top5[i].value,
                      ),
                  ],

                  // Active vehicles list
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
            ),
          ),
        );
      },
    );
  }
}

/// Mini 7-bar chart using pure CustomPaint — no extra deps.
class _WeekBarChart extends StatelessWidget {
  const _WeekBarChart({required this.dailyCounts});
  // dailyCounts[0] = today, [6] = 6 days ago.
  final List<int> dailyCounts;

  @override
  Widget build(BuildContext context) {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final now = DateTime.now();
    // Labels: oldest left → today right.
    final labels = List.generate(
        7, (i) => days[(now.subtract(Duration(days: 6 - i)).weekday - 1) % 7]);
    final counts = List.generate(7, (i) => dailyCounts[6 - i]);
    final maxVal = counts.fold(0, (m, v) => v > m ? v : m);

    return Container(
      height: 128,
      padding: const EdgeInsets.fromLTRB(VSpace.x4, VSpace.x4, VSpace.x4, VSpace.x3),
      decoration: BoxDecoration(
        color: VColors.surface900,
        borderRadius: BorderRadius.circular(VRadius.lg),
        border: Border.all(color: VColors.surface700),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(7, (i) {
          final isToday = i == 6;
          final frac = maxVal > 0 ? counts[i] / maxVal : 0.0;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (counts[i] > 0)
                    Text('${counts[i]}',
                        style: VType.caption.copyWith(
                            fontSize: 10,
                            color: isToday
                                ? VColors.brand300
                                : VColors.contentFaint)),
                  const SizedBox(height: 2),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOut,
                    height: 52 * frac + (frac > 0 ? 4 : 0),
                    decoration: BoxDecoration(
                      color: isToday
                          ? VColors.brand400
                          : VColors.brand400.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(VRadius.sm),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(labels[i],
                      style: VType.caption.copyWith(
                          fontSize: 10,
                          color: isToday
                              ? VColors.brand300
                              : VColors.contentFaint,
                          fontWeight: isToday
                              ? FontWeight.w700
                              : FontWeight.w400)),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow(
      {required this.rank, required this.name, required this.delivered});
  final int rank;
  final String name;
  final int delivered;

  @override
  Widget build(BuildContext context) {
    final isTop = rank == 1;
    return Container(
      margin: const EdgeInsets.only(bottom: VSpace.x2),
      padding: const EdgeInsets.symmetric(
          horizontal: VSpace.x4, vertical: VSpace.x3),
      decoration: BoxDecoration(
        color: VColors.surface900,
        borderRadius: BorderRadius.circular(VRadius.md),
        border: Border.all(
          color: isTop
              ? VColors.brand400.withValues(alpha: 0.4)
              : VColors.surface700,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isTop
                  ? VColors.brand500.withValues(alpha: 0.15)
                  : VColors.surface700,
              borderRadius: BorderRadius.circular(VRadius.sm),
            ),
            child: Text(
              '$rank',
              style: VType.caption.copyWith(
                color: isTop ? VColors.brand300 : VColors.contentMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: VSpace.x3),
          Expanded(
            child: Text(name,
                style:
                    VType.body.copyWith(color: VColors.contentStrong),
                overflow: TextOverflow.ellipsis),
          ),
          Text('$delivered delivered',
              style: VType.label.copyWith(color: VColors.brand300)),
        ],
      ),
    );
  }
}

/// Card wrapper for an analytics section with a title + list of bars.
class _AnalyticsCard extends StatelessWidget {
  const _AnalyticsCard({required this.title, required this.children});
  final String title;
  final List<Widget> children;

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
        children: [
          Text(title,
              style: VType.label.copyWith(color: VColors.contentStrong)),
          const SizedBox(height: VSpace.x4),
          ...children,
        ],
      ),
    );
  }
}

/// Labeled horizontal progress bar row — label + animated fill + count.
class _HBarRow extends StatelessWidget {
  const _HBarRow(
      {required this.label,
      required this.value,
      required this.maxVal,
      required this.color});
  final String label;
  final int value;
  final int maxVal;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final frac = maxVal > 0 ? (value / maxVal).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: VSpace.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: VType.caption
                        .copyWith(color: VColors.contentDefault)),
              ),
              Text('$value',
                  style: VType.caption.copyWith(
                      color: VColors.contentStrong,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(VRadius.full),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 7,
              backgroundColor: VColors.surface700,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Text(data.label,
                    style: VType.caption.copyWith(
                        color: VColors.contentMuted,
                        fontWeight: FontWeight.w500)),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: data.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(VRadius.sm),
                ),
                child: Icon(data.icon, color: data.color, size: 16),
              ),
            ],
          ),
          const SizedBox(height: VSpace.x2),
          Text(data.value,
              style: VType.titleLg.copyWith(color: VColors.contentStrong)),
        ],
      ),
    );
  }
}

/// A live active-cars-by-location pill. The pulsing dot mirrors the web
/// dashboard's "live" affordance.
class _LocationActiveChip extends StatelessWidget {
  const _LocationActiveChip({required this.name, required this.count});
  final String name;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: VSpace.x3, vertical: VSpace.x2),
      decoration: BoxDecoration(
        color: VColors.surface900,
        borderRadius: BorderRadius.circular(VRadius.full),
        border: Border.all(color: VColors.surface700),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration:
                BoxDecoration(color: VColors.brand400, shape: BoxShape.circle),
          ),
          const SizedBox(width: VSpace.x2),
          Text(name,
              style: VType.caption.copyWith(color: VColors.contentStrong)),
          const SizedBox(width: VSpace.x2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: VColors.brand900,
              borderRadius: BorderRadius.circular(VRadius.full),
            ),
            child: Text('$count',
                style: VType.caption.copyWith(
                    color: VColors.brand300, fontWeight: FontWeight.w700)),
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
      decoration: BoxDecoration(
        color: VColors.surface900,
        borderRadius: BorderRadius.circular(VRadius.md),
        border: Border.all(color: VColors.surface700),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status-colored left accent bar
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: tx.status.color,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(VRadius.md),
                  bottomLeft: Radius.circular(VRadius.md),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: VSpace.x3, vertical: VSpace.x3),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tx.carPlate,
                              style: VType.body.copyWith(
                                  color: VColors.contentStrong,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5)),
                          const SizedBox(height: 2),
                          Text(tx.guestName ?? 'Guest',
                              style: VType.caption),
                        ],
                      ),
                    ),
                    _StatusChip(status: tx.status),
                  ],
                ),
              ),
            ),
          ],
        ),
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
          child: Center(
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(maxWidth: context.dashboardMaxWidth),
              child: ListView.separated(
                padding: const EdgeInsets.all(VSpace.x4),
                itemCount: all.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: VSpace.x2),
                itemBuilder: (_, i) => _TxRow(tx: all[i]),
              ),
            ),
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
      decoration: BoxDecoration(
        color: VColors.surface900,
        borderRadius: BorderRadius.circular(VRadius.lg),
        border: Border.all(color: VColors.surface700),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status-colored left accent bar
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: tx.status.color,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(VRadius.lg),
                  bottomLeft: Radius.circular(VRadius.lg),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(VSpace.x3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(tx.carPlate,
                            style: VType.body.copyWith(
                                color: VColors.contentStrong,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5)),
                        if (tx.keyCode != null) ...[
                          const SizedBox(width: VSpace.x2),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: VColors.surface700,
                              borderRadius:
                                  BorderRadius.circular(VRadius.full),
                            ),
                            child: Text('Key ${tx.keyCode}',
                                style: VType.caption.copyWith(
                                    color: VColors.contentMuted,
                                    fontSize: 11)),
                          ),
                        ],
                        const Spacer(),
                        _StatusChip(status: tx.status),
                      ],
                    ),
                    const SizedBox(height: VSpace.x1),
                    Text(
                      [
                        tx.guestName ?? 'Guest',
                        if (tx.guestPhone != null) tx.guestPhone!,
                      ].join('  ·  '),
                      style: VType.caption,
                    ),
                    const SizedBox(height: 2),
                    Text(_fmtDateTime(tx.createdAt),
                        style: VType.caption
                            .copyWith(color: VColors.contentFaint)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// 3) Drivers / 5) Team — both reuse the company-detail people slice
// ===========================================================================

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

    Future<void> edit(AdminUser u) => AdminStaffSheet.show(
          context,
          role: u.role,
          locations: state.locations,
          existing: u,
          onSubmit: notifier.addStaff,
          onUpdate: (input) => notifier.updateStaff(u.id, input),
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

    final role = isDriver ? 'driver' : 'valet';
    Future<void> toggle(AdminUser u) async {
      final ok = await notifier.setUserActive(u.id, !u.active, role: role);
      if (!ok && context.mounted) {
        _snack(context, notifier.createError ?? 'Could not update the account.');
      }
    }

    Future<void> remove(AdminUser u) async {
      final confirmed = await _confirm(context,
          'Delete ${u.name ?? u.email}?', 'This removes their login. This cannot be undone.');
      if (confirmed != true) return;
      final ok = await notifier.deleteUser(u.id, role: role);
      if (!ok && context.mounted) {
        _snack(context, notifier.createError ?? 'Could not delete the account.');
      }
    }

    return _AddScaffold(
      label: 'Add $noun',
      onAdd: add,
      child: ListView.separated(
        padding: const EdgeInsets.all(VSpace.x4),
        itemCount: people.length,
        separatorBuilder: (_, __) => const SizedBox(height: VSpace.x2),
        itemBuilder: (_, i) => _PersonRow(
          user: people[i],
          onEdit: () => edit(people[i]),
          onToggle: () => toggle(people[i]),
          onDelete: () => remove(people[i]),
        ),
      ),
    );
  }
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: VColors.surface700,
      behavior: SnackBarBehavior.floating,
    ));
}

Future<bool?> _confirm(BuildContext context, String title, String body) {
  return showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: VColors.surface900,
      title: Text(title,
          style: VType.body.copyWith(color: VColors.contentStrong)),
      content: Text(body, style: VType.caption),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel',
                style: TextStyle(color: VColors.contentMuted))),
        TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete',
                style: TextStyle(color: VColors.alertDanger))),
      ],
    ),
  );
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.user,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });
  final AdminUser user;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  String get _initials {
    final name = user.displayName.trim();
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final isActive = user.active;
    final activeColor = isActive ? VColors.alertSuccess : VColors.contentFaint;
    final roleName = user.role == 'driver' ? 'Driver' : 'Operator';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: VColors.surface900,
        borderRadius: BorderRadius.circular(VRadius.lg),
        border: Border.all(
          color: isActive
              ? VColors.alertSuccess.withValues(alpha: 0.3)
              : VColors.surface700,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // ---- Top: avatar, name/email, role chip, ⋮ ----
          Padding(
            padding: const EdgeInsets.fromLTRB(
                VSpace.x4, VSpace.x4, VSpace.x2, VSpace.x3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: VColors.brand900,
                    borderRadius: BorderRadius.circular(VRadius.md),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _initials,
                    style: VType.label.copyWith(
                        color: VColors.brand300, fontSize: 15),
                  ),
                ),
                const SizedBox(width: VSpace.x3),
                // Name + email
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName,
                        style:
                            VType.label.copyWith(color: VColors.contentStrong),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(user.email,
                          style: VType.caption,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                // Role chip
                Container(
                  margin: const EdgeInsets.only(left: VSpace.x2, top: 2),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: VColors.brand900,
                    borderRadius: BorderRadius.circular(VRadius.full),
                    border: Border.all(
                        color: VColors.brand400.withValues(alpha: 0.4),
                        width: 1),
                  ),
                  child: Text(roleName,
                      style: VType.caption.copyWith(
                          color: VColors.brand300,
                          fontWeight: FontWeight.w600)),
                ),
                // ⋮ actions menu — Edit and Delete only (toggle is inline)
                PopupMenuButton<String>(
                  color: VColors.surface800,
                  icon: Icon(Icons.more_vert_rounded,
                      color: VColors.contentMuted, size: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(VRadius.md),
                    side: BorderSide(color: VColors.surface600, width: 1),
                  ),
                  onSelected: (v) {
                    if (v == 'edit') onEdit();
                    if (v == 'delete') onDelete();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(children: [
                        Icon(Icons.edit_outlined,
                            size: 16, color: VColors.contentMuted),
                        const SizedBox(width: VSpace.x2),
                        Text('Edit',
                            style: VType.body
                                .copyWith(color: VColors.contentStrong)),
                      ]),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        Icon(Icons.delete_outline_rounded,
                            size: 16, color: VColors.alertDanger),
                        const SizedBox(width: VSpace.x2),
                        Text('Delete',
                            style:
                                TextStyle(color: VColors.alertDanger)),
                      ]),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ---- Divider ----
          Divider(height: 1, color: VColors.surface700),

          // ---- Bottom: status dot + label + inline switch ----
          Padding(
            padding: const EdgeInsets.fromLTRB(
                VSpace.x4, VSpace.x2, VSpace.x3, VSpace.x2),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: activeColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: VSpace.x2),
                Text(
                  isActive ? 'Active' : 'Inactive',
                  style: VType.caption.copyWith(
                      color: activeColor, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Transform.scale(
                  scale: 0.8,
                  alignment: Alignment.centerRight,
                  child: Switch(
                    value: isActive,
                    onChanged: (_) => onToggle(),
                    activeThumbColor: VColors.alertSuccess,
                  ),
                ),
              ],
            ),
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
          facilityOwners: state.facilityOwners,
        );
    Future<void> edit(AdminLocation loc) => AdminLocationSheet.show(
          context,
          onSubmit: (input) => notifier.editLocation(loc.id, input),
          errorReader: () => notifier.createError,
          facilityOwners: state.facilityOwners,
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
          final ownerName = loc.facilityOwnerId == null
              ? null
              : state.facilityOwners
                  .where((u) => u.id == loc.facilityOwnerId)
                  .map((u) => u.displayName)
                  .firstOrNull;
          return _LocationRow(
            loc: loc,
            facilityOwnerName: ownerName,
            onEdit: () => edit(loc),
            onOpen: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => LocationDetailScreen(location: loc)),
            ),
          );
        },
      ),
    );
  }
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({
    required this.loc,
    required this.onEdit,
    required this.onOpen,
    this.facilityOwnerName,
  });
  final AdminLocation loc;
  final VoidCallback onEdit;
  final VoidCallback onOpen;
  final String? facilityOwnerName;

  @override
  Widget build(BuildContext context) {
    final addr = [loc.address, loc.city, loc.state]
        .where((p) => p != null && p.isNotEmpty)
        .join(', ');
    return Material(
      color: VColors.surface900,
      borderRadius: BorderRadius.circular(VRadius.lg),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(VRadius.lg),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(VRadius.lg),
            border: Border.all(color: VColors.surface700),
          ),
          child: Column(
            children: [
              // ---- Top: icon + name + edit ----
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    VSpace.x4, VSpace.x4, VSpace.x2, VSpace.x3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: VColors.brand900,
                        borderRadius: BorderRadius.circular(VRadius.md),
                      ),
                      alignment: Alignment.center,
                      child: Icon(Icons.place_rounded,
                          size: 20, color: VColors.brand300),
                    ),
                    const SizedBox(width: VSpace.x3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(loc.name,
                              style:
                                  VType.label.copyWith(color: VColors.contentStrong),
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text(
                            addr.isNotEmpty ? addr : 'No address',
                            style: VType.caption,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Edit location',
                      onPressed: onEdit,
                      icon: Icon(Icons.edit_outlined,
                          color: VColors.contentMuted, size: 18),
                    ),
                  ],
                ),
              ),
              // ---- Divider ----
              Divider(height: 1, color: VColors.surface700),
              // ---- Footer: key capacity + manage link ----
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    VSpace.x4, VSpace.x2, VSpace.x4, VSpace.x2),
                child: Row(
                  children: [
                    Icon(Icons.vpn_key_rounded,
                        size: 13, color: VColors.contentMuted),
                    const SizedBox(width: 5),
                    Text('${loc.keyCapacity} key slots',
                        style: VType.caption.copyWith(
                            color: VColors.contentMuted,
                            fontWeight: FontWeight.w500)),
                    if (facilityOwnerName != null) ...[
                      const SizedBox(width: VSpace.x2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: VColors.surface700,
                          borderRadius: BorderRadius.circular(VRadius.full),
                          border: Border.all(
                              color: VColors.surface600, width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.domain_rounded,
                                size: 10, color: VColors.contentFaint),
                            const SizedBox(width: 3),
                            Text(facilityOwnerName!,
                                style: VType.caption.copyWith(
                                    color: VColors.contentMuted,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ],
                    const Spacer(),
                    IconButton(
                      tooltip: 'Guest QR',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => qr_util.showQrSheet(context, loc.name),
                      icon: Icon(Icons.qr_code_rounded,
                          size: 18, color: VColors.contentMuted),
                    ),
                    const SizedBox(width: VSpace.x1),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: VColors.brand900,
                        borderRadius: BorderRadius.circular(VRadius.full),
                        border: Border.all(
                            color: VColors.brand400.withValues(alpha: 0.4),
                            width: 1),
                      ),
                      child: Text('Manage →',
                          style: VType.caption.copyWith(
                              color: VColors.brand300,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ],
          ),
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

// ===========================================================================
// Facility Owners list (More pane → Facility Owners sub-tab)
// ===========================================================================

class _FacilityOwnersList extends ConsumerWidget {
  const _FacilityOwnersList({required this.companyId});
  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(companyDetailControllerProvider(companyId));
    final notifier =
        ref.read(companyDetailControllerProvider(companyId).notifier);

    Future<void> add() => AdminStaffSheet.show(
          context,
          role: 'facility_owner',
          locations: state.locations,
          onSubmit: notifier.addStaff,
          errorReader: () => notifier.createError,
        );

    Future<void> edit(AdminUser u) => AdminStaffSheet.show(
          context,
          role: u.role,
          locations: state.locations,
          existing: u,
          onSubmit: notifier.addStaff,
          onUpdate: (input) => notifier.updateStaff(u.id, input),
          errorReader: () => notifier.createError,
        );

    if (state.status == DetailStatus.loading) return _loading();
    if (state.status == DetailStatus.error) {
      return _error('Could not load facility owners.', notifier.load);
    }

    final people = state.facilityOwners;
    if (people.isEmpty) {
      return _AddScaffold(
        label: 'Add facility owner',
        onAdd: add,
        child: VEmptyState(
          icon: Icons.domain_outlined,
          headline: 'No facility owners yet',
          hint: 'Create a facility owner login to give view access to specific locations.',
          actionLabel: 'Add facility owner',
          onAction: add,
        ),
      );
    }

    Future<void> remove(AdminUser u) async {
      final confirmed = await _confirm(context, 'Delete ${u.name ?? u.email}?',
          'This removes their login. This cannot be undone.');
      if (confirmed != true) return;
      final ok = await notifier.deleteUser(u.id, role: 'facility_owner');
      if (!ok && context.mounted) {
        _snack(context,
            notifier.createError ?? 'Could not delete the account.');
      }
    }

    return _AddScaffold(
      label: 'Add facility owner',
      onAdd: add,
      child: ListView.separated(
        padding: const EdgeInsets.all(VSpace.x4),
        itemCount: people.length,
        separatorBuilder: (_, __) => const SizedBox(height: VSpace.x2),
        itemBuilder: (_, i) => _PersonRow(
          user: people[i],
          onEdit: () => edit(people[i]),
          onToggle: () async {
            final ok = await notifier.setUserActive(
                people[i].id, !people[i].active,
                role: 'facility_owner');
            if (!ok && context.mounted) {
              _snack(context,
                  notifier.createError ?? 'Could not update the account.');
            }
          },
          onDelete: () => remove(people[i]),
        ),
      ),
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
// 7) Contracts — venue/client agreements (cards), with create
// ===========================================================================

class _ContractsTab extends ConsumerWidget {
  const _ContractsTab({required this.companyId});
  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contracts = ref.watch(companyContractsProvider(companyId));

    Future<void> add() async {
      final created = await _AddContractSheet.show(context, ref, companyId);
      if (created == true) {
        ref.invalidate(companyContractsProvider(companyId));
      }
    }

    return contracts.when(
      loading: _loading,
      error: (e, _) => _error('Could not load contracts.',
          () => ref.invalidate(companyContractsProvider(companyId))),
      data: (list) {
        final body = list.isEmpty
            ? VEmptyState(
                icon: Icons.description_outlined,
                headline: 'No contracts yet',
                hint: 'Add your first venue or client agreement.',
                actionLabel: 'Add contract',
                onAction: add,
              )
            : ListView.separated(
                padding: const EdgeInsets.all(VSpace.x4),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: VSpace.x2),
                itemBuilder: (_, i) => _ContractCard(contract: list[i]),
              );
        return _AddScaffold(label: 'Add contract', onAdd: add, child: body);
      },
    );
  }
}

class _ContractCard extends StatelessWidget {
  const _ContractCard({required this.contract});
  final Contract contract;

  @override
  Widget build(BuildContext context) {
    final c = contract;
    final loc = [c.locationCity, c.locationState]
        .whereType<String>()
        .where((p) => p.isNotEmpty)
        .join(', ');
    final activeColor = c.active ? VColors.alertSuccess : VColors.alertDanger;
    return Container(
      padding: const EdgeInsets.all(VSpace.x3),
      decoration: BoxDecoration(
        color: VColors.surface900,
        borderRadius: BorderRadius.circular(VRadius.md),
        border: Border.all(color: VColors.surface700),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.description_rounded,
                  color: VColors.brand400, size: 18),
              const SizedBox(width: VSpace.x2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name,
                        style: VType.body
                            .copyWith(color: VColors.contentStrong)),
                    Text(
                        [c.locationName ?? 'No location', if (loc.isNotEmpty) loc]
                            .join(' · '),
                        style: VType.caption),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: VSpace.x2, vertical: VSpace.x0),
                decoration: BoxDecoration(
                  color: activeColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(VRadius.full),
                ),
                child: Text(c.active ? 'Active' : 'Inactive',
                    style: VType.caption.copyWith(
                        color: activeColor, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          if (c.managerName != null ||
              c.managerPhone != null ||
              c.managerEmail != null) ...[
            Divider(color: VColors.surface700, height: VSpace.x4),
            if (c.managerName != null)
              _line(Icons.person_outline_rounded, c.managerName!),
            if (c.managerPhone != null)
              _line(Icons.phone_outlined, c.managerPhone!),
            if (c.managerEmail != null)
              _line(Icons.mail_outline_rounded, c.managerEmail!),
          ],
        ],
      ),
    );
  }

  Widget _line(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            Icon(icon, size: 13, color: VColors.contentFaint),
            const SizedBox(width: VSpace.x2),
            Text(text, style: VType.caption),
          ],
        ),
      );
}

/// Minimal create-contract sheet (name + optional manager contact).
class _AddContractSheet extends ConsumerStatefulWidget {
  const _AddContractSheet({required this.companyId});
  final String companyId;

  static Future<bool?> show(
      BuildContext context, WidgetRef ref, String companyId) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: VColors.surface950,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(VRadius.lg)),
      ),
      builder: (_) => _AddContractSheet(companyId: companyId),
    );
  }

  @override
  ConsumerState<_AddContractSheet> createState() => _AddContractSheetState();
}

class _AddContractSheetState extends ConsumerState<_AddContractSheet> {
  final _name = TextEditingController();
  final _manager = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _manager.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).createContract(
            widget.companyId,
            CreateContractInput(
              name: _name.text.trim(),
              managerName: _manager.text,
              managerPhone: _phone.text,
              managerEmail: _email.text,
            ),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = 'Could not create the contract. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
                child: Text('New contract',
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
          const SizedBox(height: VSpace.x3),
          _field('Agreement name', _name),
          const SizedBox(height: VSpace.x2),
          _field('Manager name', _manager),
          const SizedBox(height: VSpace.x2),
          _field('Manager phone', _phone),
          const SizedBox(height: VSpace.x2),
          _field('Manager email', _email),
          if (_error != null) ...[
            const SizedBox(height: VSpace.x2),
            Text(_error!,
                style: VType.caption.copyWith(color: VColors.alertDanger)),
          ],
          const SizedBox(height: VSpace.x4),
          VPrimaryButton(
              label: 'Create contract', loading: _busy, onPressed: _submit),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c) => TextField(
        controller: c,
        style: VType.body.copyWith(color: VColors.contentStrong),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: VType.caption,
          filled: true,
          fillColor: VColors.surface900,
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(VRadius.md),
            borderSide: BorderSide(color: VColors.surface700),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(VRadius.md),
            borderSide: BorderSide(color: VColors.surface700),
          ),
        ),
      );
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
        label: Text(label,
            style: VType.label.copyWith(color: VColors.contentOnAccent)),
      ),
    );
  }
}
