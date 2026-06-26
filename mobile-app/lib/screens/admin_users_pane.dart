import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/admin_user.dart';
import '../state/admin_users_controller.dart';
import '../state/providers.dart';
import '../theme/v_colors.dart';
import '../theme/v_theme.dart';
import '../theme/v_tokens.dart';
import '../widgets/v_states.dart';

/// Hierarchical users pane (ADMIN) — re-platforms `Users.jsx`: a Super Admins
/// section at the top, then one collapsible card per company bucketing
/// Company Owners (manager) / Operators (valet) / Drivers (driver).
class AdminUsersPane extends ConsumerWidget {
  const AdminUsersPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(adminUsersControllerProvider);
    final notifier = ref.read(adminUsersControllerProvider.notifier);

    switch (state.status) {
      case AdminUsersStatus.loading:
        return const Center(
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
            children: const [
              SizedBox(height: 120),
              VEmptyState(
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
        padding:
            const EdgeInsets.fromLTRB(VSpace.x4, VSpace.x4, VSpace.x4, VSpace.x6),
        children: [
          if (superAdmins.isNotEmpty) ...[
            _SectionLabel(label: 'Super Admins', count: superAdmins.length),
            Container(
              padding: const EdgeInsets.all(VSpace.x2),
              decoration: BoxDecoration(
                color: VColors.surface900,
                borderRadius: BorderRadius.circular(VRadius.lg),
                border: Border.all(color: VColors.surface700, width: 1),
              ),
              child: Column(
                children: [
                  for (final u in superAdmins) _UserRow(user: u),
                ],
              ),
            ),
            const SizedBox(height: VSpace.x5),
          ],
          for (final name in companyNames)
            Padding(
              padding: const EdgeInsets.only(bottom: VSpace.x3),
              child: _CompanyCard(
                name: name,
                users: byCompany[name]!,
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
          Text('$count',
              style: VType.caption.copyWith(color: VColors.contentFaint)),
        ],
      ),
    );
  }
}

/// Collapsible company card bucketing owners / operators / drivers.
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

    return Container(
      decoration: BoxDecoration(
        color: VColors.surface900,
        borderRadius: BorderRadius.circular(VRadius.lg),
        border: Border.all(color: VColors.surface700, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(VRadius.lg),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(VSpace.x4),
              child: Row(
                children: [
                  const Icon(Icons.business_rounded,
                      size: 20, color: VColors.brand300),
                  const SizedBox(width: VSpace.x3),
                  Expanded(
                    child: Text(widget.name,
                        style: VType.bodyLg
                            .copyWith(color: VColors.contentStrong),
                        overflow: TextOverflow.ellipsis),
                  ),
                  Text('${widget.users.length}',
                      style: VType.caption
                          .copyWith(color: VColors.contentMuted)),
                  const SizedBox(width: VSpace.x2),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: VColors.contentMuted,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(color: VColors.surface700, height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  VSpace.x4, VSpace.x3, VSpace.x4, VSpace.x4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _bucket('Company Owners', owners),
                  _bucket('Operators', operators),
                  _bucket('Drivers', drivers),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bucket(String label, List<AdminUser> users) {
    if (users.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: VSpace.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: VSpace.x2, top: VSpace.x1),
            child: Text(label.toUpperCase(),
                style: VType.caption.copyWith(
                  color: VColors.contentFaint,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                )),
          ),
          for (final u in users) _UserRow(user: u),
        ],
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({required this.user});
  final AdminUser user;

  @override
  Widget build(BuildContext context) {
    final icon = switch (user.role) {
      'admin' => Icons.shield_rounded,
      'manager' => Icons.account_circle_rounded,
      'valet' => Icons.badge_rounded,
      'driver' => Icons.person_pin_circle_rounded,
      _ => Icons.person_rounded,
    };
    return Container(
      constraints: const BoxConstraints(minHeight: VTarget.minTouch),
      padding: const EdgeInsets.symmetric(vertical: VSpace.x2),
      child: Row(
        children: [
          Icon(icon, size: 18, color: VColors.contentMuted),
          const SizedBox(width: VSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.displayName,
                    style:
                        VType.body.copyWith(color: VColors.contentStrong),
                    overflow: TextOverflow.ellipsis),
                Text(user.email,
                    style: VType.caption, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (!user.active)
            Text('Inactive',
                style: VType.caption.copyWith(color: VColors.contentFaint)),
        ],
      ),
    );
  }
}
