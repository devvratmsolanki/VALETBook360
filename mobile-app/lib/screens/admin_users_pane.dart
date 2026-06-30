import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/admin_user.dart';
import '../state/admin_users_controller.dart';
import '../state/providers.dart';
import '../theme/v_breakpoints.dart';
import '../theme/v_colors.dart';
import '../theme/v_theme.dart';
import '../theme/v_tokens.dart';
import '../widgets/v_adaptive.dart';
import '../widgets/v_states.dart';

/// Hierarchical users pane (ADMIN) — super-admins section + one collapsible
/// card per company bucketing Owners / Operators / Drivers.
class AdminUsersPane extends ConsumerWidget {
  const AdminUsersPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(adminUsersControllerProvider);
    final notifier = ref.read(adminUsersControllerProvider.notifier);

    switch (state.status) {
      case AdminUsersStatus.loading:
        return Center(
          child: CircularProgressIndicator(color: VColors.brand400),
        );
      case AdminUsersStatus.error:
        return Padding(
          padding: const EdgeInsets.all(VSpace.x4),
          child: Center(
            child: VBanner(
              message: state.error ?? 'Something went wrong.',
              onRetry: notifier.load,
            ),
          ),
        );
      case AdminUsersStatus.empty:
        return RefreshIndicator(
          color: VColors.brand400,
          backgroundColor: VColors.surface800,
          onRefresh: notifier.load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(height: context.responsive(compact: 80, expanded: 160)),
              const VEmptyState(
                icon: Icons.people_outline_rounded,
                headline: 'No users yet',
                hint: 'Users appear here as companies onboard staff.',
              ),
            ],
          ),
        );
      case AdminUsersStatus.ready:
        return _hierarchy(context, ref, state, notifier);
    }
  }

  Widget _hierarchy(
    BuildContext context,
    WidgetRef ref,
    AdminUsersState state,
    AdminUsersController notifier,
  ) {
    final superAdmins = state.superAdmins;
    final byCompany = state.byCompany;
    final companyNames = byCompany.keys.toList()..sort();

    return RefreshIndicator(
      color: VColors.brand400,
      backgroundColor: VColors.surface800,
      onRefresh: notifier.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            VSpace.x4, VSpace.x4, VSpace.x4, VSpace.x6),
        children: [
          VBoundedContent(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (superAdmins.isNotEmpty) ...[
                  _SectionLabel(label: 'Super Admins', count: superAdmins.length),
                  Column(
                    children: superAdmins
                        .map((u) => Padding(
                              padding:
                                  const EdgeInsets.only(bottom: VSpace.x2),
                              child: _SuperAdminCard(user: u),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: VSpace.x5),
                ],
                if (companyNames.isNotEmpty) ...[
                  _SectionLabel(
                      label: 'Companies', count: byCompany.length),
                  const SizedBox(height: VSpace.x1),
                ],
                VResponsiveGrid(
                  spacing: VSpace.x3,
                  runSpacing: VSpace.x3,
                  children: [
                    for (final name in companyNames)
                      _CompanyCard(
                        name: name,
                        users: byCompany[name]!,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: VSpace.x3),
      child: Row(
        children: [
          Text(label.toUpperCase(),
              style: VType.caption.copyWith(
                color: VColors.contentMuted,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w600,
              )),
          const SizedBox(width: VSpace.x2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: VColors.surface700,
              borderRadius: BorderRadius.circular(VRadius.full),
            ),
            child: Text('$count',
                style: VType.caption.copyWith(
                    color: VColors.contentMuted, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Super-admin standalone card
// ---------------------------------------------------------------------------

class _SuperAdminCard extends StatelessWidget {
  const _SuperAdminCard({required this.user});
  final AdminUser user;

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
    return Container(
      padding: const EdgeInsets.all(VSpace.x4),
      decoration: BoxDecoration(
        color: VColors.surface900,
        borderRadius: BorderRadius.circular(VRadius.lg),
        border: Border.all(color: VColors.surface700, width: 1),
      ),
      child: Row(
        children: [
          // Avatar with gradient-like accent background
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: VColors.brand700,
              borderRadius: BorderRadius.circular(VRadius.md),
            ),
            alignment: Alignment.center,
            child: Text(_initials,
                style: VType.label.copyWith(
                    color: VColors.contentOnAccent, fontSize: 14)),
          ),
          const SizedBox(width: VSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.displayName,
                    style: VType.label.copyWith(color: VColors.contentStrong),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(user.email,
                    style: VType.caption, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          // Shield badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: VColors.brand900,
              borderRadius: BorderRadius.circular(VRadius.full),
              border: Border.all(
                  color: VColors.brand400.withValues(alpha: 0.4), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_rounded, size: 11, color: VColors.brand300),
                const SizedBox(width: 4),
                Text('Admin',
                    style: VType.caption.copyWith(
                        color: VColors.brand300, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Company group — collapsible with buckets
// ---------------------------------------------------------------------------

class _CompanyCard extends StatefulWidget {
  const _CompanyCard({required this.name, required this.users});
  final String name;
  final List<AdminUser> users;

  @override
  State<_CompanyCard> createState() => _CompanyCardState();
}

class _CompanyCardState extends State<_CompanyCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final owners = widget.users.where((u) => u.isManager).toList();
    final operators = widget.users.where((u) => u.isOperator).toList();
    final drivers = widget.users.where((u) => u.isDriver).toList();
    final facilityOwners = widget.users.where((u) => u.isFacilityOwner).toList();
    final active = widget.users.where((u) => u.active).length;

    return Container(
      decoration: BoxDecoration(
        color: VColors.surface900,
        borderRadius: BorderRadius.circular(VRadius.lg),
        border: Border.all(color: VColors.surface700, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---- Header ----
          InkWell(
            borderRadius: BorderRadius.vertical(
                top: Radius.circular(VRadius.lg),
                bottom: _expanded ? Radius.zero : Radius.circular(VRadius.lg)),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(VSpace.x4),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: VColors.brand900,
                      borderRadius: BorderRadius.circular(VRadius.md),
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.business_rounded,
                        size: 18, color: VColors.brand300),
                  ),
                  const SizedBox(width: VSpace.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.name,
                            style: VType.label
                                .copyWith(color: VColors.contentStrong),
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.users.length} members · $active active',
                          style: VType.caption,
                        ),
                      ],
                    ),
                  ),
                  // Mini count chips
                  if (!_expanded) ...[
                    _CountChip(
                        icon: Icons.person_pin_circle_rounded,
                        count: drivers.length,
                        color: VColors.brand300),
                    const SizedBox(width: VSpace.x1),
                    _CountChip(
                        icon: Icons.badge_rounded,
                        count: operators.length,
                        color: VColors.contentMuted),
                    const SizedBox(width: VSpace.x2),
                  ],
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: VColors.contentMuted,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(color: VColors.surface700, height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  VSpace.x4, VSpace.x3, VSpace.x4, VSpace.x4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _bucket('Owner', Icons.manage_accounts_rounded, owners),
                  _bucket('Operators', Icons.badge_rounded, operators),
                  _bucket('Drivers', Icons.person_pin_circle_rounded, drivers),
                  _bucket('Facility Owners', Icons.domain_rounded, facilityOwners),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bucket(String label, IconData icon, List<AdminUser> users) {
    if (users.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: VSpace.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: VSpace.x2, top: VSpace.x1),
            child: Row(
              children: [
                Icon(icon, size: 13, color: VColors.contentFaint),
                const SizedBox(width: 5),
                Text(label.toUpperCase(),
                    style: VType.caption.copyWith(
                      color: VColors.contentFaint,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
          ),
          ...users.map((u) => Padding(
                padding: const EdgeInsets.only(bottom: VSpace.x2),
                child: _UserRow(user: u),
              )),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip(
      {required this.icon, required this.count, required this.color});
  final IconData icon;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: VColors.surface700,
        borderRadius: BorderRadius.circular(VRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text('$count',
              style:
                  VType.caption.copyWith(color: color, fontSize: 11)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// User row inside company bucket
// ---------------------------------------------------------------------------

class _UserRow extends StatelessWidget {
  const _UserRow({required this.user});
  final AdminUser user;

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

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: VSpace.x3, vertical: VSpace.x2 + 2),
      decoration: BoxDecoration(
        color: VColors.surface800,
        borderRadius: BorderRadius.circular(VRadius.md),
        border: Border.all(
          color: isActive
              ? VColors.alertSuccess.withValues(alpha: 0.2)
              : VColors.surface600,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Initials avatar
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: VColors.brand900,
              borderRadius: BorderRadius.circular(VRadius.sm),
            ),
            alignment: Alignment.center,
            child: Text(_initials,
                style:
                    VType.caption.copyWith(color: VColors.brand300, fontSize: 12)),
          ),
          const SizedBox(width: VSpace.x2 + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.displayName,
                    style: VType.body.copyWith(color: VColors.contentStrong),
                    overflow: TextOverflow.ellipsis),
                Text(user.email,
                    style: VType.caption, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          // Active/inactive dot + label
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: activeColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            isActive ? 'Active' : 'Inactive',
            style: VType.caption.copyWith(
                color: activeColor, fontWeight: FontWeight.w600, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
