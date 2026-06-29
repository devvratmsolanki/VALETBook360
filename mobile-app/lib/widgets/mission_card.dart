import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/assignment.dart';
import '../models/lifecycle_status.dart';
import '../state/clock.dart';
import '../theme/v_colors.dart';
import '../theme/v_theme.dart';
import '../theme/v_tokens.dart';
import 'slide_to_advance.dart';
import 'v_chips.dart';
import 'v_status_rail.dart';

/// `VMissionCard` (doc §6.9 / §7.5) — full-bleed driver mission.
/// Plate in display mono centered top third; context block mid; thumb-zone
/// slide-to-advance bottom third. The card is the whole screen surface.
class MissionCard extends ConsumerWidget {
  const MissionCard({
    super.key,
    required this.mission,
    required this.busy,
    required this.onAdvance,
  });

  final Assignment mission;
  final bool busy;
  final Future<void> Function(DriverAction action) onAdvance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = mission.status.nextAction;
    final now = ref.watch(clockProvider).valueOrNull ?? DateTime.now();
    final elapsed = elapsedSince(mission.requestedAtLocal, now);

    return Container(
      decoration: BoxDecoration(
        color: VColors.surface950,
        borderRadius: BorderRadius.circular(VRadius.xl),
        border: Border.all(color: VColors.surface700, width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(
        VSpace.x5,
        VSpace.x6,
        VSpace.x5,
        VSpace.x5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Mission-type ribbon + live timer.
          Row(
            children: [
              _ribbon(),
              const Spacer(),
              Icon(Icons.schedule_rounded,
                  size: 15, color: VColors.contentFaint),
              const SizedBox(width: VSpace.x1),
              Text(elapsed, style: VType.mono),
            ],
          ),

          const Spacer(flex: 2),

          // Plate hero (display mono, centered top third).
          Semantics(
            label: 'License plate ${mission.carPlate}',
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(mission.carPlate, style: VType.plateHero),
              ),
            ),
          ),
          if (mission.vehicleLine.isNotEmpty) ...[
            const SizedBox(height: VSpace.x3),
            Center(
              child: Text(
                [mission.carColor, mission.vehicleLine]
                    .where((p) => p != null && p.isNotEmpty)
                    .join(' · '),
                style: VType.body.copyWith(color: VColors.contentMuted),
              ),
            ),
          ],

          const Spacer(flex: 2),

          // Context chips.
          Wrap(
            spacing: VSpace.x2,
            runSpacing: VSpace.x2,
            alignment: WrapAlignment.center,
            children: [
              if (mission.keyCode != null) VKeySlotChip(code: mission.keyCode!),
              if (mission.guestName != null)
                VMetaChip(
                  icon: Icons.person_outline_rounded,
                  label: mission.guestName!,
                  semanticLabel: 'Guest ${mission.guestName}',
                ),
            ],
          ),

          const SizedBox(height: VSpace.x6),

          // Status spine.
          VStatusRail(status: mission.status, labeled: true),

          const SizedBox(height: VSpace.x6),

          // Thumb-zone action.
          if (action != null)
            SlideToAdvance(
              label: action.verb,
              fillColor: action.to.color,
              busy: busy,
              onCommit: () => onAdvance(action),
            )
          else
            _terminal(),
        ],
      ),
    );
  }

  Widget _ribbon() {
    // Park (assigned/en-route to a parked car) vs Retrieve (requested handoff).
    final isRetrieve = mission.status.railIndex >=
        LifecycleStatus.requested.railIndex;
    final label = isRetrieve ? 'RETRIEVE' : 'PARK';
    final icon = isRetrieve
        ? Icons.directions_car_filled_rounded
        : Icons.local_parking_rounded;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: VSpace.x3,
        vertical: VSpace.x1,
      ),
      decoration: BoxDecoration(
        color: mission.status.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(VRadius.full),
        border: Border.all(
          color: mission.status.color.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: mission.status.color),
          const SizedBox(width: VSpace.x1),
          Text(
            label,
            style: VType.caption.copyWith(
              color: mission.status.color,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _terminal() {
    return Container(
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: VColors.surface800,
        borderRadius: BorderRadius.circular(VRadius.full),
        border: Border.all(color: VColors.surface600, width: 1),
      ),
      child: Text(
        'No action for this mission',
        style: VType.caption,
      ),
    );
  }
}
