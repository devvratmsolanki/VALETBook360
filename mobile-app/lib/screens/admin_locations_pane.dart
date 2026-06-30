import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/admin_location.dart';
import '../state/admin_locations_controller.dart';
import '../state/providers.dart';
import '../theme/v_breakpoints.dart';
import '../theme/v_colors.dart';
import '../theme/v_theme.dart';
import '../theme/v_tokens.dart';
import '../widgets/v_adaptive.dart';
import '../widgets/v_states.dart';
import 'admin_location_create_screen.dart';

/// All-locations pane (ADMIN) — every location across every company,
/// grouped by company. Each card is editable; the header carries an inline add.
class AdminLocationsPane extends ConsumerWidget {
  const AdminLocationsPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(adminLocationsControllerProvider);
    final notifier = ref.read(adminLocationsControllerProvider.notifier);

    switch (state.status) {
      case AdminLocationsStatus.loading:
        return Center(
          child: CircularProgressIndicator(color: VColors.brand400),
        );
      case AdminLocationsStatus.error:
        return Padding(
          padding: const EdgeInsets.all(VSpace.x4),
          child: Center(
            child: VBanner(
              message: state.error ?? 'Something went wrong.',
              onRetry: notifier.load,
            ),
          ),
        );
      case AdminLocationsStatus.empty:
        return RefreshIndicator(
          color: VColors.brand400,
          backgroundColor: VColors.surface800,
          onRefresh: notifier.load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(height: context.responsive(compact: 80, expanded: 160)),
              const VEmptyState(
                icon: Icons.location_off_outlined,
                headline: 'No locations yet',
                hint: 'Locations appear here as companies add them.',
              ),
            ],
          ),
        );
      case AdminLocationsStatus.ready:
        return _grouped(context, ref, state, notifier);
    }
  }

  Widget _grouped(
    BuildContext context,
    WidgetRef ref,
    AdminLocationsState state,
    AdminLocationsController notifier,
  ) {
    final groups = state.byCompany;
    final companyNames = groups.keys.toList()..sort();

    Future<void> edit(AdminLocation loc) => AdminLocationSheet.show(
          context,
          existing: loc,
          onSubmit: (input) => notifier.editLocation(loc.id, input),
          errorReader: () => notifier.createError,
        );

    Future<void> add(String companyId) => AdminLocationSheet.show(
          context,
          onSubmit: (input) => notifier.addLocation(companyId, input),
          errorReader: () => notifier.createError,
        );

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
                for (final name in companyNames) ...[
                  _CompanyGroupHeader(
                    name: name,
                    count: groups[name]!.length,
                    onAdd: () => add(groups[name]!.first.companyId),
                  ),
                  VResponsiveGrid(
                    spacing: VSpace.x3,
                    runSpacing: VSpace.x3,
                    children: [
                      for (final loc in groups[name]!)
                        _LocationCard(
                            location: loc, onEdit: () => edit(loc)),
                    ],
                  ),
                  const SizedBox(height: VSpace.x5),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompanyGroupHeader extends StatelessWidget {
  const _CompanyGroupHeader({
    required this.name,
    required this.count,
    required this.onAdd,
  });

  final String name;
  final int count;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: VSpace.x2, bottom: VSpace.x3),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: VColors.brand900,
              borderRadius: BorderRadius.circular(VRadius.sm),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.business_rounded, size: 15, color: VColors.brand300),
          ),
          const SizedBox(width: VSpace.x2),
          Expanded(
            child: Text(name,
                style: VType.label.copyWith(color: VColors.contentStrong),
                overflow: TextOverflow.ellipsis),
          ),
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
          const SizedBox(width: VSpace.x1),
          IconButton(
            tooltip: 'Add location',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.add_circle_outline_rounded,
                size: 20, color: VColors.brand300),
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.location, required this.onEdit});
  final AdminLocation location;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final subtitle = location.locationLine.isNotEmpty
        ? location.locationLine
        : 'No address set';

    return Container(
      decoration: BoxDecoration(
        color: VColors.surface900,
        borderRadius: BorderRadius.circular(VRadius.lg),
        border: Border.all(color: VColors.surface700, width: 1),
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
                      Text(location.name,
                          style: VType.label
                              .copyWith(color: VColors.contentStrong),
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: VType.caption,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Edit',
                  icon: Icon(Icons.edit_outlined,
                      size: 18, color: VColors.contentMuted),
                  onPressed: onEdit,
                ),
              ],
            ),
          ),
          // ---- Divider ----
          Divider(height: 1, color: VColors.surface700),
          // ---- Bottom: key capacity chip ----
          Padding(
            padding: const EdgeInsets.fromLTRB(
                VSpace.x4, VSpace.x2, VSpace.x4, VSpace.x2),
            child: Row(
              children: [
                Icon(Icons.vpn_key_rounded,
                    size: 14, color: VColors.contentMuted),
                const SizedBox(width: 5),
                Text('${location.keyCapacity} key slots',
                    style: VType.caption.copyWith(
                        color: VColors.contentMuted,
                        fontWeight: FontWeight.w500)),
                const Spacer(),
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
                  child: Text('${location.keyCapacity} keys',
                      style: VType.caption.copyWith(
                          color: VColors.brand300,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
