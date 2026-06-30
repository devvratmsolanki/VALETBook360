import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/admin_location.dart';
import '../state/auth_controller.dart';
import '../state/providers.dart';
import '../theme/v_colors.dart';
import '../theme/v_theme.dart';
import '../theme/v_tokens.dart';
import '../widgets/v_states.dart';
import '../widgets/help_chatbot.dart';

/// View-only panel for facility owners: see their locations + basic stats.
/// Created/managed by company or super-admin; this user cannot edit anything.
class FacilityOwnerHomeScreen extends ConsumerWidget {
  const FacilityOwnerHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user!;
    return Scaffold(
      backgroundColor: VColors.surface950,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      VSpace.x5, VSpace.x5, VSpace.x5, VSpace.x2),
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
                            Text(
                              user.displayName,
                              style: VType.label
                                  .copyWith(color: VColors.contentStrong),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text('Facility Owner',
                                style: VType.caption
                                    .copyWith(color: VColors.brand400)),
                          ],
                        ),
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
                const Divider(height: 1),
                Expanded(child: _LocationsPane()),
              ],
            ),
          ),
          const HelpChatbot(),
        ],
      ),
    );
  }
}

class _LocationsPane extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(facilityOwnerLocationsProvider);

    return async.when(
      loading: () => Center(
          child: CircularProgressIndicator(color: VColors.brand400)),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(VSpace.x4),
        child: VBanner(
          message: 'Could not load your locations.',
          onRetry: () => ref.refresh(facilityOwnerLocationsProvider),
        ),
      ),
      data: (locations) {
        if (locations.isEmpty) {
          return const VEmptyState(
            icon: Icons.location_off_outlined,
            headline: 'No locations assigned',
            hint: 'Ask your company manager to assign a location to you.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SummaryRow(locations: locations),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  VSpace.x5, VSpace.x4, VSpace.x5, VSpace.x2),
              child: Text('Your locations',
                  style:
                      VType.label.copyWith(color: VColors.contentStrong)),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                    VSpace.x4, 0, VSpace.x4, VSpace.x8),
                itemCount: locations.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: VSpace.x2),
                itemBuilder: (_, i) => _LocationCard(loc: locations[i]),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.locations});
  final List<AdminLocation> locations;

  @override
  Widget build(BuildContext context) {
    final totalCap =
        locations.fold<int>(0, (sum, l) => sum + l.keyCapacity);
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(VSpace.x4, VSpace.x4, VSpace.x4, 0),
      child: Row(
        children: [
          Expanded(
              child: _KpiTile(
                  label: 'Locations',
                  value: '${locations.length}',
                  icon: Icons.place_rounded)),
          const SizedBox(width: VSpace.x3),
          Expanded(
              child: _KpiTile(
                  label: 'Total key slots',
                  value: '$totalCap',
                  icon: Icons.vpn_key_rounded)),
        ],
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile(
      {required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

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
          Icon(icon, size: 18, color: VColors.brand400),
          const SizedBox(height: VSpace.x2),
          Text(value,
              style: VType.title.copyWith(color: VColors.contentStrong)),
          Text(label, style: VType.caption),
        ],
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.loc});
  final AdminLocation loc;

  @override
  Widget build(BuildContext context) {
    final addr = [loc.address, loc.city, loc.state]
        .where((p) => p != null && p.isNotEmpty)
        .join(', ');
    return Container(
      padding: const EdgeInsets.all(VSpace.x4),
      decoration: BoxDecoration(
        color: VColors.surface900,
        borderRadius: BorderRadius.circular(VRadius.lg),
        border: Border.all(color: VColors.surface700),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: VColors.brand900,
              borderRadius: BorderRadius.circular(VRadius.md),
            ),
            child: Icon(Icons.place_rounded, size: 20, color: VColors.brand300),
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
                if (addr.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(addr,
                      style: VType.caption,
                      overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          const SizedBox(width: VSpace.x3),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(Icons.vpn_key_rounded,
                  size: 13, color: VColors.contentMuted),
              const SizedBox(height: 2),
              Text('${loc.keyCapacity}',
                  style: VType.caption.copyWith(
                      color: VColors.contentMuted,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}
