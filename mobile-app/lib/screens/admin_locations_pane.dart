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

/// All-locations pane (ADMIN) — re-platforms `AdminLocations.jsx`: every
/// location across every company, grouped by company. Each row is editable in
/// place; the company group header carries an inline add.
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
              SizedBox(
                  height: context.responsive(compact: 80, expanded: 160)),
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
        padding:
            const EdgeInsets.fromLTRB(VSpace.x4, VSpace.x4, VSpace.x4, VSpace.x6),
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
                        _LocationRow(
                            location: loc, onEdit: () => edit(loc)),
                    ],
                  ),
                  const SizedBox(height: VSpace.x4),
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
          Expanded(
            child: Text(name.toUpperCase(),
                style: VType.caption.copyWith(
                  color: VColors.contentMuted,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: VSpace.x2),
          Text('$count',
              style: VType.caption.copyWith(color: VColors.contentFaint)),
          const SizedBox(width: VSpace.x2),
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

class _LocationRow extends StatelessWidget {
  const _LocationRow({required this.location, required this.onEdit});
  final AdminLocation location;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: VSpace.x4, vertical: VSpace.x3),
      decoration: BoxDecoration(
        color: VColors.surface900,
        borderRadius: BorderRadius.circular(VRadius.md),
        border: Border.all(color: VColors.surface700, width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.place_rounded, size: 20, color: VColors.brand300),
          const SizedBox(width: VSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(location.name,
                    style:
                        VType.label.copyWith(color: VColors.contentStrong),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: VSpace.x1),
                Text(
                  location.locationLine.isNotEmpty
                      ? location.locationLine
                      : '${location.keyCapacity} key slots',
                  style: VType.caption,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: VSpace.x2),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: VSpace.x2, vertical: 2),
            decoration: BoxDecoration(
              color: VColors.brand900,
              borderRadius: BorderRadius.circular(VRadius.full),
            ),
            child: Text('${location.keyCapacity} keys',
                style: VType.caption.copyWith(color: VColors.brand300)),
          ),
          IconButton(
            tooltip: 'Edit',
            icon: Icon(Icons.edit_outlined,
                size: 20, color: VColors.contentMuted),
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}
