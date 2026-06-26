import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/admin_location.dart';
import '../state/company_detail_controller.dart';
import '../state/providers.dart';
import '../theme/v_colors.dart';
import '../theme/v_theme.dart';
import '../theme/v_tokens.dart';
import '../widgets/v_states.dart';
import 'admin_location_create_screen.dart';
import 'admin_staff_create_screen.dart';

/// Company drill-down — re-platforms `CompanyDetail.jsx`: tabbed Overview /
/// Locations / Operators / Drivers. Reached by tapping a company card (admin) or
/// landed directly for a manager (their own company). Each people/location tab
/// has its own add action; locations are editable.
class AdminCompanyDetailScreen extends ConsumerWidget {
  const AdminCompanyDetailScreen({super.key, required this.companyId});

  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(companyDetailControllerProvider(companyId));
    final notifier =
        ref.read(companyDetailControllerProvider(companyId).notifier);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: VColors.surface950,
        appBar: AppBar(
          backgroundColor: VColors.surface950,
          titleSpacing: 0,
          title: Text(
            state.company?.displayName ?? 'Company',
            style: VType.title.copyWith(color: VColors.contentStrong),
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded,
                  color: VColors.contentMuted),
              onPressed: notifier.load,
            ),
            const SizedBox(width: VSpace.x2),
          ],
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: VColors.brand400,
            labelColor: VColors.contentStrong,
            unselectedLabelColor: VColors.contentMuted,
            labelStyle: VType.label,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Locations'),
              Tab(text: 'Operators'),
              Tab(text: 'Drivers'),
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          child: _body(context, ref, state, notifier),
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    CompanyDetailState state,
    CompanyDetailController notifier,
  ) {
    switch (state.status) {
      case DetailStatus.loading:
        return const Center(
          child: CircularProgressIndicator(color: VColors.brand400),
        );
      case DetailStatus.error:
        return Padding(
          padding: const EdgeInsets.all(VSpace.x4),
          child: Center(
            child: VBanner(
              message: state.error ?? 'Something went wrong.',
              onRetry: notifier.load,
            ),
          ),
        );
      case DetailStatus.ready:
        return TabBarView(
          children: [
            _OverviewTab(state: state),
            _LocationsTab(companyId: companyId, state: state),
            _PeopleTab(
              companyId: companyId,
              state: state,
              role: 'valet',
            ),
            _PeopleTab(
              companyId: companyId,
              state: state,
              role: 'driver',
            ),
          ],
        );
    }
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.state});
  final CompanyDetailState state;

  @override
  Widget build(BuildContext context) {
    final c = state.company;
    return ListView(
      padding: const EdgeInsets.all(VSpace.x4),
      children: [
        _StatRow(
          stats: [
            _Stat('Locations', state.locations.length),
            _Stat('Operators', state.operators.length),
            _Stat('Drivers', state.drivers.length),
          ],
        ),
        const SizedBox(height: VSpace.x4),
        _InfoCard(
          rows: [
            _InfoRow('Owner', c?.ownerName ?? '—'),
            _InfoRow('Email', c?.email ?? '—'),
            _InfoRow('Phone', c?.phone ?? '—'),
          ],
        ),
      ],
    );
  }
}

class _LocationsTab extends ConsumerWidget {
  const _LocationsTab({required this.companyId, required this.state});
  final String companyId;
  final CompanyDetailState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier =
        ref.read(companyDetailControllerProvider(companyId).notifier);

    Future<void> add() => AdminLocationSheet.show(
          context,
          onSubmit: notifier.addLocation,
          errorReader: () => notifier.createError,
        );

    Future<void> edit(AdminLocation loc) => AdminLocationSheet.show(
          context,
          existing: loc,
          onSubmit: (input) => notifier.editLocation(loc.id, input),
          errorReader: () => notifier.createError,
        );

    if (state.locations.isEmpty) {
      return _EmptyTab(
        icon: Icons.location_off_outlined,
        headline: 'No locations yet',
        hint: 'Add a garage or lot to start checking cars in.',
        actionLabel: 'Add location',
        onAction: add,
      );
    }

    return Stack(
      children: [
        ListView.separated(
          padding: const EdgeInsets.fromLTRB(
              VSpace.x4, VSpace.x4, VSpace.x4, 96),
          itemCount: state.locations.length,
          separatorBuilder: (_, __) => const SizedBox(height: VSpace.x3),
          itemBuilder: (_, i) {
            final loc = state.locations[i];
            return _Tile(
              leading: Icons.place_rounded,
              title: loc.name,
              subtitle: loc.locationLine.isNotEmpty
                  ? loc.locationLine
                  : '${loc.keyCapacity} key slots',
              trailing: IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined,
                    size: 20, color: VColors.contentMuted),
                onPressed: () => edit(loc),
              ),
              badge: '${loc.keyCapacity} keys',
            );
          },
        ),
        _AddFab(label: 'Add location', onPressed: add),
      ],
    );
  }
}

class _PeopleTab extends ConsumerWidget {
  const _PeopleTab({
    required this.companyId,
    required this.state,
    required this.role,
  });

  final String companyId;
  final CompanyDetailState state;

  /// `valet` (operators) | `driver`.
  final String role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier =
        ref.read(companyDetailControllerProvider(companyId).notifier);
    final isDriver = role == 'driver';
    final people = isDriver ? state.drivers : state.operators;
    final noun = isDriver ? 'driver' : 'operator';

    Future<void> add() => AdminStaffSheet.show(
          context,
          role: role,
          locations: state.locations,
          onSubmit: notifier.addStaff,
          errorReader: () => notifier.createError,
        );

    if (people.isEmpty) {
      return _EmptyTab(
        icon: isDriver
            ? Icons.person_off_outlined
            : Icons.badge_outlined,
        headline: 'No ${noun}s yet',
        hint: 'Add a $noun login to get this company moving.',
        actionLabel: 'Add $noun',
        onAction: add,
      );
    }

    return Stack(
      children: [
        ListView.separated(
          padding: const EdgeInsets.fromLTRB(
              VSpace.x4, VSpace.x4, VSpace.x4, 96),
          itemCount: people.length,
          separatorBuilder: (_, __) => const SizedBox(height: VSpace.x3),
          itemBuilder: (_, i) {
            final u = people[i];
            return _Tile(
              leading: isDriver
                  ? Icons.person_pin_circle_rounded
                  : Icons.badge_rounded,
              title: u.displayName,
              subtitle: u.email,
              badge: u.active ? 'Active' : 'Inactive',
              badgeColor:
                  u.active ? VColors.alertSuccess : VColors.contentFaint,
            );
          },
        ),
        _AddFab(label: 'Add $noun', onPressed: add),
      ],
    );
  }
}

// ---- Shared bits ----

class _Stat {
  const _Stat(this.label, this.value);
  final String label;
  final int value;
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.stats});
  final List<_Stat> stats;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < stats.length; i++) ...[
          if (i > 0) const SizedBox(width: VSpace.x3),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(VSpace.x4),
              decoration: BoxDecoration(
                color: VColors.surface900,
                borderRadius: BorderRadius.circular(VRadius.lg),
                border: Border.all(color: VColors.surface700, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${stats[i].value}',
                      style: VType.titleLg
                          .copyWith(color: VColors.contentStrong)),
                  const SizedBox(height: VSpace.x1),
                  Text(stats[i].label.toUpperCase(),
                      style: VType.caption.copyWith(
                        color: VColors.contentMuted,
                        letterSpacing: 1.2,
                      )),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _InfoRow {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.rows});
  final List<_InfoRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(VSpace.x4),
      decoration: BoxDecoration(
        color: VColors.surface900,
        borderRadius: BorderRadius.circular(VRadius.lg),
        border: Border.all(color: VColors.surface700, width: 1),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              const Divider(color: VColors.surface700, height: VSpace.x6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 80,
                  child: Text(rows[i].label, style: VType.caption),
                ),
                Expanded(
                  child: Text(
                    rows[i].value,
                    style:
                        VType.body.copyWith(color: VColors.contentStrong),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.leading,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.badge,
    this.badgeColor = VColors.brand300,
  });

  final IconData leading;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final String? badge;
  final Color badgeColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: VTarget.minTouch),
      padding: const EdgeInsets.symmetric(
          horizontal: VSpace.x4, vertical: VSpace.x3),
      decoration: BoxDecoration(
        color: VColors.surface900,
        borderRadius: BorderRadius.circular(VRadius.md),
        border: Border.all(color: VColors.surface700, width: 1),
      ),
      child: Row(
        children: [
          Icon(leading, size: 20, color: VColors.brand300),
          const SizedBox(width: VSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style:
                        VType.label.copyWith(color: VColors.contentStrong),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: VSpace.x1),
                Text(subtitle,
                    style: VType.caption, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (badge != null) ...[
            const SizedBox(width: VSpace.x2),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: VSpace.x2, vertical: 2),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(VRadius.full),
                border: Border.all(
                    color: badgeColor.withValues(alpha: 0.4), width: 1),
              ),
              child: Text(badge!,
                  style: VType.caption.copyWith(
                      color: badgeColor, fontWeight: FontWeight.w600)),
            ),
          ],
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _EmptyTab extends StatelessWidget {
  const _EmptyTab({
    required this.icon,
    required this.headline,
    required this.hint,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String headline;
  final String hint;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return VEmptyState(
      icon: icon,
      headline: headline,
      hint: hint,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }
}

class _AddFab extends StatelessWidget {
  const _AddFab({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: VSpace.x4,
      bottom: VSpace.x4,
      child: FloatingActionButton.extended(
        heroTag: 'add-$label',
        backgroundColor: VColors.brand500,
        foregroundColor: VColors.contentOnAccent,
        icon: const Icon(Icons.add_rounded),
        label: Text(label,
            style: VType.label.copyWith(color: VColors.contentOnAccent)),
        onPressed: onPressed,
      ),
    );
  }
}
