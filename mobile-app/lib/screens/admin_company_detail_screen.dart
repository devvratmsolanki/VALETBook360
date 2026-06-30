import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/admin_location.dart';
import '../models/admin_user.dart';
import '../state/company_detail_controller.dart';
import '../state/providers.dart';
import '../theme/v_breakpoints.dart';
import '../theme/v_colors.dart';
import '../theme/v_theme.dart';
import '../theme/v_tokens.dart';
import '../widgets/app_logo.dart';
import '../widgets/v_adaptive.dart';
import '../widgets/v_states.dart';
import 'admin_location_create_screen.dart';
import 'admin_staff_create_screen.dart';

/// Company drill-down — tabbed Overview / Locations / Operators / Drivers.
class AdminCompanyDetailScreen extends ConsumerWidget {
  const AdminCompanyDetailScreen({super.key, required this.companyId});

  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(companyDetailControllerProvider(companyId));
    final notifier =
        ref.read(companyDetailControllerProvider(companyId).notifier);

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: VColors.surface950,
        appBar: AppBar(
          backgroundColor: VColors.surface950,
          elevation: 0,
          titleSpacing: 0,
          title: Row(
            children: [
              const AppLogo(height: 22),
              const SizedBox(width: VSpace.x3),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      state.company?.displayName ?? 'Company',
                      style: VType.title.copyWith(color: VColors.contentStrong),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (state.company?.email != null)
                      Text(state.company!.email!,
                          style: VType.caption,
                          overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: Icon(Icons.refresh_rounded, color: VColors.contentMuted),
              onPressed: notifier.load,
            ),
            const SizedBox(width: VSpace.x2),
          ],
          bottom: TabBar(
            isScrollable: true,
            indicatorColor: VColors.brand400,
            indicatorWeight: 2.5,
            labelColor: VColors.contentStrong,
            unselectedLabelColor: VColors.contentMuted,
            labelStyle: VType.label,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Locations'),
              Tab(text: 'Operators'),
              Tab(text: 'Drivers'),
              Tab(text: 'Facility Owners'),
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
        return Center(child: CircularProgressIndicator(color: VColors.brand400));
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
            _PeopleTab(companyId: companyId, state: state, role: 'valet'),
            _PeopleTab(companyId: companyId, state: state, role: 'driver'),
            _PeopleTab(
                companyId: companyId, state: state, role: 'facility_owner'),
          ],
        );
    }
  }
}

// ===========================================================================
// Overview
// ===========================================================================

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.state});
  final CompanyDetailState state;

  @override
  Widget build(BuildContext context) {
    final c = state.company;
    return VBoundedContent(
      padding: EdgeInsets.zero,
      child: ListView(
        padding: const EdgeInsets.all(VSpace.x4),
        children: [
          _StatRow(stats: [
            _Stat('Locations', state.locations.length),
            _Stat('Operators', state.operators.length),
            _Stat('Drivers', state.drivers.length),
            _Stat('Facility Owners', state.facilityOwners.length),
          ]),
          const SizedBox(height: VSpace.x5),
          _SectionLabel('Company Info'),
          const SizedBox(height: VSpace.x2),
          _InfoCard(rows: [
            _InfoRow('Owner', c?.ownerName ?? '—'),
            _InfoRow('Email', c?.email ?? '—'),
            _InfoRow('Phone', c?.phone ?? '—'),
          ]),
        ],
      ),
    );
  }
}

// ===========================================================================
// Locations
// ===========================================================================

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
          facilityOwners: state.facilityOwners,
        );

    Future<void> edit(AdminLocation loc) => AdminLocationSheet.show(
          context,
          existing: loc,
          onSubmit: (input) => notifier.editLocation(loc.id, input),
          errorReader: () => notifier.createError,
          facilityOwners: state.facilityOwners,
        );

    Future<void> delete(AdminLocation loc) async {
      final ok = await _confirmDelete(context, loc.name,
          message: 'This deletes the location and its key slots, and unassigns '
              'any staff pinned to it. Existing transactions keep their record. '
              'This cannot be undone.');
      if (ok != true || !context.mounted) return;
      final done = await notifier.deleteLocation(loc.id);
      if (!context.mounted) return;
      _snack(context, done ? 'Location deleted' : (notifier.createError ?? 'Could not delete the location'));
    }

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
        VBoundedContent(
          padding: EdgeInsets.zero,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(VSpace.x4, VSpace.x4, VSpace.x4, 96),
            itemCount: state.locations.length,
            separatorBuilder: (_, __) => const SizedBox(height: VSpace.x3),
            itemBuilder: (_, i) {
              final loc = state.locations[i];
              final ownerName = loc.facilityOwnerId == null
                  ? null
                  : state.facilityOwners
                      .where((u) => u.id == loc.facilityOwnerId)
                      .map((u) => u.displayName)
                      .firstOrNull;
              return _Tile(
                leading: Icons.place_rounded,
                title: loc.name,
                subtitle: loc.locationLine.isNotEmpty
                    ? loc.locationLine
                    : '${loc.keyCapacity} key slots',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Edit',
                      icon: Icon(Icons.edit_outlined,
                          size: 20, color: VColors.contentMuted),
                      onPressed: () => edit(loc),
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      icon: Icon(Icons.delete_outline_rounded,
                          size: 20, color: VColors.alertDanger),
                      onPressed: () => delete(loc),
                    ),
                  ],
                ),
                badgeWidget: _LocationBadges(
                    keyCount: loc.keyCapacity, ownerName: ownerName),
              );
            },
          ),
        ),
        _AddFab(label: 'Add location', onPressed: add),
      ],
    );
  }
}

// ===========================================================================
// People tab — shared by Operators + Drivers
// ===========================================================================

class _PeopleTab extends ConsumerStatefulWidget {
  const _PeopleTab({
    required this.companyId,
    required this.state,
    required this.role,
  });

  final String companyId;
  final CompanyDetailState state;
  final String role; // 'valet' | 'driver' | 'facility_owner'

  @override
  ConsumerState<_PeopleTab> createState() => _PeopleTabState();
}

class _PeopleTabState extends ConsumerState<_PeopleTab> {
  final Set<String> _toggling = {};

  CompanyDetailController get _notifier =>
      ref.read(companyDetailControllerProvider(widget.companyId).notifier);

  Future<void> _toggle(AdminUser u) async {
    if (_toggling.contains(u.id)) return;
    setState(() => _toggling.add(u.id));
    final ok = await _notifier.setUserActive(u.id, !u.active, role: widget.role);
    if (mounted) {
      setState(() => _toggling.remove(u.id));
      if (!ok && _notifier.createError != null) {
        _snack(context, _notifier.createError!);
      }
    }
  }

  Future<void> _delete(AdminUser u) async {
    final confirmed = await _confirmDelete(context, u.displayName);
    if (confirmed != true || !mounted) return;
    final ok = await _notifier.deleteUser(u.id, role: widget.role);
    if (!ok && mounted && _notifier.createError != null) {
      _snack(context, _notifier.createError!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = widget.role == 'driver'
        ? widget.state.drivers
        : widget.role == 'facility_owner'
            ? widget.state.facilityOwners
            : widget.state.operators;
    final noun = widget.role == 'driver'
        ? 'driver'
        : widget.role == 'facility_owner'
            ? 'facility owner'
            : 'operator';

    Future<void> add() => AdminStaffSheet.show(
          context,
          role: widget.role,
          locations: widget.state.locations,
          onSubmit: _notifier.addStaff,
          errorReader: () => _notifier.createError,
        );

    Future<void> edit(AdminUser u) => AdminStaffSheet.show(
          context,
          role: u.role,
          locations: widget.state.locations,
          existing: u,
          onSubmit: _notifier.addStaff,
          onUpdate: (input) => _notifier.updateStaff(u.id, input),
          errorReader: () => _notifier.createError,
        );

    if (people.isEmpty) {
      return _EmptyTab(
        icon: widget.role == 'driver'
            ? Icons.person_off_outlined
            : widget.role == 'facility_owner'
                ? Icons.domain_disabled_outlined
                : Icons.badge_outlined,
        headline: 'No ${noun}s yet',
        hint: 'Add a $noun login to get this company moving.',
        actionLabel: 'Add $noun',
        onAction: add,
      );
    }

    return Stack(
      children: [
        VBoundedContent(
          padding: EdgeInsets.zero,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(VSpace.x4, VSpace.x4, VSpace.x4, 96),
            itemCount: people.length,
            itemBuilder: (_, i) {
              final u = people[i];
              return Padding(
                padding: i < people.length - 1
                    ? const EdgeInsets.only(bottom: VSpace.x3)
                    : EdgeInsets.zero,
                child: _MemberCard(
                  user: u,
                  isToggling: _toggling.contains(u.id),
                  onToggle: () => _toggle(u),
                  onEdit: () => edit(u),
                  onDelete: () => _delete(u),
                ),
              );
            },
          ),
        ),
        _AddFab(label: 'Add $noun', onPressed: add),
      ],
    );
  }
}

// ===========================================================================
// _MemberCard — rich card for each operator / driver
// ===========================================================================

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.user,
    required this.isToggling,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final AdminUser user;
  final bool isToggling;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
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
    final roleName = user.role == 'driver'
        ? 'Driver'
        : user.role == 'facility_owner'
            ? 'Facility Owner'
            : 'Operator';

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
          // ---- Top: avatar, name/email, role chip, actions ----
          Padding(
            padding: const EdgeInsets.fromLTRB(VSpace.x4, VSpace.x4, VSpace.x2, VSpace.x3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar with initials
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
                        style: VType.label.copyWith(color: VColors.contentStrong),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(user.email, style: VType.caption,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                // Role chip
                Container(
                  margin: const EdgeInsets.only(left: VSpace.x2, top: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: VColors.brand900,
                    borderRadius: BorderRadius.circular(VRadius.full),
                    border: Border.all(
                        color: VColors.brand400.withValues(alpha: 0.4), width: 1),
                  ),
                  child: Text(roleName,
                      style: VType.caption.copyWith(
                          color: VColors.brand300, fontWeight: FontWeight.w600)),
                ),
                // ⋮ popup menu
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
                            style: TextStyle(color: VColors.alertDanger)),
                      ]),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ---- Divider ----
          Divider(height: 1, color: VColors.surface700),

          // ---- Bottom: status dot + label + switch ----
          Padding(
            padding: const EdgeInsets.fromLTRB(VSpace.x4, VSpace.x2, VSpace.x3, VSpace.x2),
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
                if (isToggling)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                  )
                else
                  Transform.scale(
                    scale: 0.8,
                    alignment: Alignment.centerRight,
                    child: Switch(
                      value: isActive,
                      onChanged: (_) => onToggle(),
                      activeColor: VColors.alertSuccess,
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
// _LocationBadges — key count + optional facility owner chip
// ===========================================================================

class _LocationBadges extends StatelessWidget {
  const _LocationBadges({required this.keyCount, this.ownerName});
  final int keyCount;
  final String? ownerName;

  Widget _chip(String label, Color fg, Color bg, Color border) => Container(
        padding: const EdgeInsets.symmetric(horizontal: VSpace.x2, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(VRadius.full),
          border: Border.all(color: border, width: 1),
        ),
        child: Text(label,
            style: VType.caption
                .copyWith(color: fg, fontWeight: FontWeight.w600)),
      );

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _chip(
          '$keyCount keys',
          VColors.brand300,
          VColors.brand300.withValues(alpha: 0.14),
          VColors.brand300.withValues(alpha: 0.4),
        ),
        if (ownerName != null) ...[
          const SizedBox(width: VSpace.x1),
          _chip(
            ownerName!,
            VColors.contentMuted,
            VColors.surface700.withValues(alpha: 0.5),
            VColors.surface600,
          ),
        ],
      ],
    );
  }
}

// ===========================================================================
// Helpers
// ===========================================================================

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: VColors.surface700,
      behavior: SnackBarBehavior.floating,
    ));
}

Future<bool?> _confirmDelete(BuildContext context, String name, {String? message}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: VColors.surface900,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VRadius.lg),
        side: BorderSide(color: VColors.surface700),
      ),
      title: Text('Delete $name?',
          style: VType.body.copyWith(color: VColors.contentStrong)),
      content: Text(
          message ?? 'This removes their login permanently and cannot be undone.',
          style: VType.caption),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel', style: TextStyle(color: VColors.contentMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child:
              Text('Delete', style: TextStyle(color: VColors.alertDanger)),
        ),
      ],
    ),
  );
}

// ===========================================================================
// Reusable sub-widgets
// ===========================================================================

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Text(
        label.toUpperCase(),
        style: VType.caption.copyWith(
          color: VColors.contentMuted,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600,
        ),
      );
}

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
                          color: VColors.contentMuted, letterSpacing: 1.2)),
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
            if (i > 0) Divider(color: VColors.surface700, height: VSpace.x6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: context.responsive(compact: 70, expanded: 120),
                  child: Text(rows[i].label, style: VType.caption),
                ),
                Expanded(
                  child: Text(rows[i].value,
                      style:
                          VType.body.copyWith(color: VColors.contentStrong)),
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
    this.badgeWidget,
  });

  final IconData leading;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final Widget? badgeWidget;

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
                    style: VType.label.copyWith(color: VColors.contentStrong),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: VSpace.x1),
                Text(subtitle,
                    style: VType.caption, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (badgeWidget != null) ...[
            const SizedBox(width: VSpace.x2),
            badgeWidget!,
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
        elevation: 4,
        icon: const Icon(Icons.add_rounded),
        label: Text(label,
            style: VType.label.copyWith(color: VColors.contentOnAccent)),
        onPressed: onPressed,
      ),
    );
  }
}
