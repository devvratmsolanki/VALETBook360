import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/company.dart';
import '../state/providers.dart';
import '../theme/v_breakpoints.dart';
import '../theme/v_colors.dart';
import '../theme/v_theme.dart';
import '../theme/v_tokens.dart';
import '../widgets/app_logo.dart';
import '../widgets/theme_toggle_button.dart';
import 'admin_company_detail_screen.dart';
import 'admin_companies_pane.dart';
import 'admin_locations_pane.dart';
import 'admin_users_pane.dart';

/// Admin / company hierarchy shell — re-platforms the super-admin drilldown
/// from `src/pages/admin/*` + CLAUDE.md "Admin hierarchical drilldown".
///
/// A super admin gets a three-section bottom nav (Companies / Locations /
/// Users). A manager (DB `manager`, UI "company") is scoped to one company by
/// the backend, so we land them straight on their own company detail — no
/// cross-company navigation is offered.
class AdminHomeScreen extends ConsumerWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;

    // Manager → straight to their (single) company's detail.
    if (user != null && user.isManager) {
      return _ManagerHome(companyId: user.companyId);
    }
    return const _AdminShell();
  }
}

/// Manager landing: resolve their one company from GET /api/companies (the
/// backend returns only theirs) and render its detail. If the JWT carries a
/// companyId we could use it directly, but resolving via the list keeps a
/// single source of truth and a clean sign-out affordance in the app bar.
class _ManagerHome extends ConsumerWidget {
  const _ManagerHome({required this.companyId});
  final String? companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companies = ref.watch(companiesControllerProvider);

    // Prefer the JWT companyId; otherwise the first (only) company returned.
    final id = (companyId != null && companyId!.isNotEmpty)
        ? companyId
        : (companies.companies.isNotEmpty
            ? companies.companies.first.id
            : null);

    if (id == null) {
      // Still loading the company list, or no company is linked.
      return Scaffold(
        backgroundColor: VColors.surface950,
        appBar: _SignOutAppBar(title: 'My Company', ref: ref),
        body: Center(
          child: CircularProgressIndicator(color: VColors.brand400),
        ),
      );
    }

    return Stack(
      children: [
        AdminCompanyDetailScreen(companyId: id),
        // Floating sign-out for the manager (the detail screen has no logout).
        Positioned(
          top: MediaQuery.of(context).padding.top + 4,
          right: VSpace.x2,
          child: _LogoutButton(ref: ref),
        ),
      ],
    );
  }
}

/// Super-admin shell with a four-tab bottom nav (Dashboard + three management panes).
class _AdminShell extends ConsumerStatefulWidget {
  const _AdminShell();

  @override
  ConsumerState<_AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<_AdminShell> {
  int _index = 0;

  static const _titles = ['Dashboard', 'Companies', 'All Locations', 'All Users'];

  @override
  void initState() {
    super.initState();
    // navBar(80) + FAB margin(16) + extended FAB height(56) + gap(16) = 168
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
    const panes = [
      _AdminDashboardPane(),
      AdminCompaniesPane(),
      AdminLocationsPane(),
      AdminUsersPane(),
    ];

    return Scaffold(
      backgroundColor: VColors.surface950,
      appBar: AppBar(
        backgroundColor: VColors.surface950,
        titleSpacing: 0,
        leadingWidth: 116,
        leading: const Padding(
          padding: EdgeInsets.only(left: VSpace.x4),
          child: Align(alignment: Alignment.centerLeft, child: AppLogo()),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_titles[_index],
                style: VType.title.copyWith(color: VColors.contentStrong)),
            Text(ref.watch(authControllerProvider).user?.displayName ?? 'Admin',
                style: VType.caption),
          ],
        ),
        actions: [
          const ThemeToggleButton(),
          _LogoutButton(ref: ref),
          const SizedBox(width: VSpace.x2),
        ],
      ),
      body: SafeArea(
        top: false,
        child: IndexedStack(index: _index, children: panes),
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
            icon: Icon(Icons.business_outlined),
            selectedIcon: Icon(Icons.business_rounded),
            label: 'Companies',
          ),
          NavigationDestination(
            icon: Icon(Icons.place_outlined),
            selectedIcon: Icon(Icons.place_rounded),
            label: 'Locations',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline_rounded),
            selectedIcon: Icon(Icons.people_rounded),
            label: 'Users',
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Admin Dashboard pane
// ===========================================================================

class _AdminDashboardPane extends ConsumerWidget {
  const _AdminDashboardPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companies = ref.watch(companiesControllerProvider);
    final locations = ref.watch(adminLocationsControllerProvider);
    final users = ref.watch(adminUsersControllerProvider);
    final rollupsAsync = ref.watch(companyRollupsProvider);

    final totalCompanies = companies.companies.length;
    final totalLocations = locations.locations.length;
    final totalOperators =
        users.users.where((u) => u.role == 'valet').length;
    final totalDrivers =
        users.users.where((u) => u.role == 'driver').length;

    // Sort companies by combined workforce size (operators + drivers), busiest first.
    final rollupsMap = rollupsAsync.valueOrNull ?? {};
    final sorted = [...companies.companies]
      ..sort((a, b) {
        final ra = rollupsMap[a.id];
        final rb = rollupsMap[b.id];
        final sa = (ra?.operators ?? 0) + (ra?.drivers ?? 0) + (ra?.locations ?? 0);
        final sb = (rb?.operators ?? 0) + (rb?.drivers ?? 0) + (rb?.locations ?? 0);
        return sb.compareTo(sa);
      });

    // Analytics data.
    final activeUsers = users.users.where((u) => u.active).length;
    final inactiveUsers = users.users.length - activeUsers;
    final totalStaff = activeUsers + inactiveUsers;
    final avgLoc = totalCompanies > 0
        ? (totalLocations / totalCompanies)
        : 0.0;
    final avgOp = totalCompanies > 0
        ? (totalOperators / totalCompanies)
        : 0.0;
    final avgDrv = totalCompanies > 0
        ? (totalDrivers / totalCompanies)
        : 0.0;

    final kpis = [
      _KpiData('Companies', totalCompanies, Icons.business_rounded, VColors.brand400),
      _KpiData('Locations', totalLocations, Icons.place_rounded, VColors.alertSuccess),
      _KpiData('Operators', totalOperators, Icons.badge_rounded, VColors.statusReady),
      _KpiData('Drivers', totalDrivers, Icons.drive_eta_rounded, VColors.brand300),
    ];

    return RefreshIndicator(
      color: VColors.brand400,
      onRefresh: () async {
        ref.invalidate(companiesControllerProvider);
        ref.invalidate(adminLocationsControllerProvider);
        ref.invalidate(adminUsersControllerProvider);
        ref.invalidate(companyRollupsProvider);
      },
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: context.dashboardMaxWidth),
          child: ListView(
            padding: const EdgeInsets.all(VSpace.x4),
            children: [
              // System overview header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: VColors.brand500.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(VRadius.md),
                    ),
                    child: Icon(Icons.monitor_heart_rounded,
                        color: VColors.brand400, size: 20),
                  ),
                  const SizedBox(width: VSpace.x3),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('System Overview',
                          style: VType.label
                              .copyWith(color: VColors.contentStrong)),
                      Text('Live snapshot across all companies',
                          style: VType.caption),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: VSpace.x4),

              // KPI grid — 2 cols on phone, 4 on desktop
              GridView.count(
                crossAxisCount:
                    context.responsive(compact: 2, expanded: 4),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: VSpace.x3,
                crossAxisSpacing: VSpace.x3,
                childAspectRatio:
                    context.responsive(compact: 1.6, expanded: 2.0),
                children: [for (final k in kpis) _KpiCard(data: k)],
              ),
              const SizedBox(height: VSpace.x6),

              // Role breakdown bar
              if (totalOperators + totalDrivers > 0) ...[
                Text('Workforce breakdown',
                    style: VType.label
                        .copyWith(color: VColors.contentStrong)),
                const SizedBox(height: VSpace.x3),
                _RoleBreakdownBar(
                    operators: totalOperators, drivers: totalDrivers),
                const SizedBox(height: VSpace.x6),
              ],

              // Top companies ranked by size
              if (sorted.isNotEmpty) ...[
                Text('Companies by size',
                    style: VType.label
                        .copyWith(color: VColors.contentStrong)),
                const SizedBox(height: VSpace.x3),
                for (final c in sorted)
                  _CompanyRankRow(
                    company: c,
                    rollup: rollupsMap[c.id],
                    rank: sorted.indexOf(c) + 1,
                  ),
              ],

              // Analytics
              if (totalStaff > 0) ...[
                const SizedBox(height: VSpace.x6),
                Text('Analytics',
                    style: VType.label
                        .copyWith(color: VColors.contentStrong)),
                const SizedBox(height: VSpace.x3),
                _AdminAnalyticsCard(
                  activeUsers: activeUsers,
                  inactiveUsers: inactiveUsers,
                  totalStaff: totalStaff,
                  avgLoc: avgLoc,
                  avgOp: avgOp,
                  avgDrv: avgDrv,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _KpiData {
  _KpiData(this.label, this.value, this.icon, this.color);
  final String label;
  final int value;
  final IconData icon;
  final Color color;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.data});
  final _KpiData data;

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
          Text('${data.value}',
              style: VType.titleLg.copyWith(color: VColors.contentStrong)),
        ],
      ),
    );
  }
}

class _RoleBreakdownBar extends StatelessWidget {
  const _RoleBreakdownBar(
      {required this.operators, required this.drivers});
  final int operators;
  final int drivers;

  @override
  Widget build(BuildContext context) {
    final total = operators + drivers;
    if (total == 0) return const SizedBox.shrink();
    final opFrac = operators / total;

    return Container(
      padding: const EdgeInsets.all(VSpace.x4),
      decoration: BoxDecoration(
        color: VColors.surface900,
        borderRadius: BorderRadius.circular(VRadius.lg),
        border: Border.all(color: VColors.surface700),
      ),
      child: Column(
        children: [
          // Stacked bar
          ClipRRect(
            borderRadius: BorderRadius.circular(VRadius.full),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  Flexible(
                    flex: (opFrac * 1000).round(),
                    child: Container(color: VColors.statusReady),
                  ),
                  Flexible(
                    flex: ((1 - opFrac) * 1000).round(),
                    child: Container(color: VColors.brand300),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: VSpace.x3),
          Row(
            children: [
              _BreakdownLegend(
                  color: VColors.statusReady,
                  label: 'Operators',
                  count: operators),
              const Spacer(),
              _BreakdownLegend(
                  color: VColors.brand300,
                  label: 'Drivers',
                  count: drivers),
            ],
          ),
        ],
      ),
    );
  }
}

class _BreakdownLegend extends StatelessWidget {
  const _BreakdownLegend(
      {required this.color, required this.label, required this.count});
  final Color color;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: VSpace.x2),
        Text('$label  ',
            style: VType.caption.copyWith(color: VColors.contentMuted)),
        Text('$count',
            style:
                VType.label.copyWith(color: VColors.contentStrong)),
      ],
    );
  }
}

class _CompanyRankRow extends StatelessWidget {
  const _CompanyRankRow(
      {required this.company, required this.rollup, required this.rank});
  final Company company;
  final ({int locations, int operators, int drivers})? rollup;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final r = rollup;
    return Container(
      margin: const EdgeInsets.only(bottom: VSpace.x2),
      padding: const EdgeInsets.symmetric(
          horizontal: VSpace.x4, vertical: VSpace.x3),
      decoration: BoxDecoration(
        color: VColors.surface900,
        borderRadius: BorderRadius.circular(VRadius.lg),
        border: Border.all(color: VColors.surface700),
      ),
      child: Row(
        children: [
          // Rank badge
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: rank == 1
                  ? VColors.brand500.withValues(alpha: 0.15)
                  : VColors.surface700,
              borderRadius: BorderRadius.circular(VRadius.sm),
            ),
            child: Text(
              '$rank',
              style: VType.caption.copyWith(
                color: rank == 1 ? VColors.brand300 : VColors.contentMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: VSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(company.companyName,
                    style: VType.label
                        .copyWith(color: VColors.contentStrong),
                    overflow: TextOverflow.ellipsis),
                if (company.email != null)
                  Text(company.email!,
                      style: VType.caption,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (r != null) ...[
            _MiniStat(Icons.place_rounded, r.locations),
            const SizedBox(width: VSpace.x3),
            _MiniStat(Icons.badge_rounded, r.operators),
            const SizedBox(width: VSpace.x3),
            _MiniStat(Icons.drive_eta_rounded, r.drivers),
          ],
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.icon, this.count);
  final IconData icon;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: VColors.contentMuted),
        const SizedBox(width: 3),
        Text('$count',
            style:
                VType.caption.copyWith(color: VColors.contentDefault)),
      ],
    );
  }
}

class _AdminAnalyticsCard extends StatelessWidget {
  const _AdminAnalyticsCard({
    required this.activeUsers,
    required this.inactiveUsers,
    required this.totalStaff,
    required this.avgLoc,
    required this.avgOp,
    required this.avgDrv,
  });
  final int activeUsers;
  final int inactiveUsers;
  final int totalStaff;
  final double avgLoc;
  final double avgOp;
  final double avgDrv;

  @override
  Widget build(BuildContext context) {
    String fmt(double v) => v == v.truncateToDouble()
        ? v.toInt().toString()
        : v.toStringAsFixed(1);

    return Column(
      children: [
        // User status
        Container(
          padding: const EdgeInsets.all(VSpace.x4),
          decoration: BoxDecoration(
            color: VColors.surface900,
            borderRadius: BorderRadius.circular(VRadius.lg),
            border: Border.all(color: VColors.surface700),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('User status',
                  style: VType.label
                      .copyWith(color: VColors.contentStrong)),
              const SizedBox(height: VSpace.x4),
              _AdminHBarRow(
                  label: 'Active',
                  value: activeUsers,
                  maxVal: totalStaff,
                  color: VColors.alertSuccess),
              _AdminHBarRow(
                  label: 'Inactive',
                  value: inactiveUsers,
                  maxVal: totalStaff,
                  color: VColors.alertDanger),
            ],
          ),
        ),
        const SizedBox(height: VSpace.x3),
        // Platform averages
        Container(
          padding: const EdgeInsets.all(VSpace.x4),
          decoration: BoxDecoration(
            color: VColors.surface900,
            borderRadius: BorderRadius.circular(VRadius.lg),
            border: Border.all(color: VColors.surface700),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Platform averages per company',
                  style: VType.label
                      .copyWith(color: VColors.contentStrong)),
              const SizedBox(height: VSpace.x4),
              _AvgRow(
                  icon: Icons.place_rounded,
                  label: 'Locations',
                  value: fmt(avgLoc)),
              _AvgRow(
                  icon: Icons.badge_rounded,
                  label: 'Operators',
                  value: fmt(avgOp)),
              _AvgRow(
                  icon: Icons.drive_eta_rounded,
                  label: 'Drivers',
                  value: fmt(avgDrv)),
            ],
          ),
        ),
      ],
    );
  }
}

class _AdminHBarRow extends StatelessWidget {
  const _AdminHBarRow(
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

class _AvgRow extends StatelessWidget {
  const _AvgRow(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: VSpace.x3),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: VColors.brand500.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(VRadius.sm),
            ),
            child: Icon(icon, size: 14, color: VColors.brand400),
          ),
          const SizedBox(width: VSpace.x3),
          Expanded(
            child: Text(label,
                style:
                    VType.caption.copyWith(color: VColors.contentDefault)),
          ),
          Text(value,
              style: VType.label
                  .copyWith(color: VColors.contentStrong)),
        ],
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  const _LogoutButton({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Sign out',
      constraints: const BoxConstraints(
        minWidth: VTarget.minTouch,
        minHeight: VTarget.minTouch,
      ),
      icon: Icon(Icons.logout_rounded, color: VColors.contentMuted),
      onPressed: () => ref.read(authControllerProvider.notifier).logout(),
    );
  }
}

class _SignOutAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _SignOutAppBar({required this.title, required this.ref});
  final String title;
  final WidgetRef ref;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: VColors.surface950,
      titleSpacing: 0,
      leadingWidth: 116,
      leading: const Padding(
        padding: EdgeInsets.only(left: VSpace.x4),
        child: Align(alignment: Alignment.centerLeft, child: AppLogo()),
      ),
      title: Text(title, style: VType.title.copyWith(color: VColors.contentStrong)),
      actions: [
        const ThemeToggleButton(),
        _LogoutButton(ref: ref),
        const SizedBox(width: VSpace.x2),
      ],
    );
  }
}
