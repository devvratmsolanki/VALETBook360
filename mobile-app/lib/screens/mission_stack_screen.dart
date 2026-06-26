import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/assignment.dart';
import '../models/lifecycle_status.dart';
import '../state/missions_controller.dart';
import '../state/providers.dart';
import '../theme/motion.dart';
import '../theme/v_colors.dart';
import '../theme/v_theme.dart';
import '../theme/v_tokens.dart';
import '../widgets/mission_card.dart';
import '../widgets/success_burst.dart';
import '../widgets/v_states.dart';

/// 7.5 Driver — Mission Stack (home). Active mission full-bleed with the
/// up-next card peeking behind; loading skeleton / empty / error+retry;
/// delivered success micro-interaction.
class MissionStackScreen extends ConsumerStatefulWidget {
  const MissionStackScreen({super.key});

  @override
  ConsumerState<MissionStackScreen> createState() => _MissionStackScreenState();
}

class _MissionStackScreenState extends ConsumerState<MissionStackScreen> {
  bool _showBurst = false;

  Future<void> _advance(Assignment mission, DriverAction action) async {
    final result =
        await ref.read(missionsControllerProvider.notifier).advance(mission, action);

    if (!mounted) return;

    if (result == null) {
      // Failure — error haptic + toast with the userMessage.
      HapticFeedback.vibrate();
      final err = ref.read(missionsControllerProvider).error;
      _toast(err ?? 'Could not update the mission.', VColors.alertDanger);
      ref.read(missionsControllerProvider.notifier).clearError();
      return;
    }

    if (result == LifecycleStatus.delivered) {
      // Success pattern (light-light) + celebration.
      HapticFeedback.lightImpact();
      Future.delayed(const Duration(milliseconds: 80), HapticFeedback.lightImpact);
      if (!Motion.reduced(context)) {
        setState(() => _showBurst = true);
      }
      _toast('Delivered · ${mission.carPlate}', VColors.alertSuccess);
    }
  }

  void _toast(String message, Color color) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: VColors.surface700,
        margin: const EdgeInsets.all(VSpace.x4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VRadius.md),
          side: BorderSide(color: color, width: 1),
        ),
        content: Row(
          children: [
            Container(width: 3, height: 22, color: color),
            const SizedBox(width: VSpace.x3),
            Expanded(
              child: Text(message,
                  style: VType.body.copyWith(color: VColors.contentStrong)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final missions = ref.watch(missionsControllerProvider);
    final user = ref.watch(authControllerProvider).user;

    return Scaffold(
      backgroundColor: VColors.surface950,
      appBar: AppBar(
        backgroundColor: VColors.surface950,
        titleSpacing: VSpace.x4,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Your run',
                style: VType.title.copyWith(color: VColors.contentStrong)),
            Text(
              user?.displayName ?? 'Driver',
              style: VType.caption,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            constraints: const BoxConstraints(
              minWidth: VTarget.minTouch,
              minHeight: VTarget.minTouch,
            ),
            icon: const Icon(Icons.refresh_rounded, color: VColors.contentMuted),
            onPressed: () =>
                ref.read(missionsControllerProvider.notifier).load(),
          ),
          IconButton(
            tooltip: 'Sign out',
            constraints: const BoxConstraints(
              minWidth: VTarget.minTouch,
              minHeight: VTarget.minTouch,
            ),
            icon: const Icon(Icons.logout_rounded, color: VColors.contentMuted),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
          const SizedBox(width: VSpace.x2),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            _body(missions),
            if (_showBurst)
              Positioned.fill(
                child: SuccessBurst(
                  onComplete: () => setState(() => _showBurst = false),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _body(MissionsState missions) {
    switch (missions.status) {
      case MissionsStatus.loading:
        return const _MissionSkeleton();

      case MissionsStatus.error:
        return Padding(
          padding: const EdgeInsets.all(VSpace.x4),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                VBanner(
                  message: missions.error ?? 'Something went wrong.',
                  onRetry: () =>
                      ref.read(missionsControllerProvider.notifier).load(),
                ),
              ],
            ),
          ),
        );

      case MissionsStatus.empty:
        return RefreshIndicator(
          color: VColors.brand400,
          backgroundColor: VColors.surface800,
          onRefresh: () =>
              ref.read(missionsControllerProvider.notifier).load(silent: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 120),
              VEmptyState(
                icon: Icons.task_alt_rounded,
                headline: "No tasks — you're all caught up",
                hint: 'Pull down to refresh',
              ),
            ],
          ),
        );

      case MissionsStatus.ready:
        return _stack(missions);
    }
  }

  Widget _stack(MissionsState missions) {
    final active = missions.active!;
    final upNext = missions.upNext;
    final busy = missions.advancingId == active.id;

    return RefreshIndicator(
      color: VColors.brand400,
      backgroundColor: VColors.surface800,
      onRefresh: () =>
          ref.read(missionsControllerProvider.notifier).load(silent: true),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  VSpace.x4,
                  VSpace.x2,
                  VSpace.x4,
                  VSpace.x4,
                ),
                child: Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    // Up-next peek (scale 0.94, dimmed) behind the active card.
                    if (upNext != null)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Transform.scale(
                          scale: 0.94,
                          alignment: Alignment.topCenter,
                          child: Opacity(
                            opacity: 0.5,
                            child: IgnorePointer(
                              child: _UpNextPeek(mission: upNext),
                            ),
                          ),
                        ),
                      ),
                    // Active mission.
                    Padding(
                      padding: EdgeInsets.only(
                        top: upNext != null ? 14 : 0,
                      ),
                      child: AnimatedSwitcher(
                        duration: Motion.duration(context, VMotion.cardEnter),
                        switchInCurve: VMotion.emphasizedDecelerate,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween(
                              begin: const Offset(0, -0.06),
                              end: Offset.zero,
                            ).animate(anim),
                            child: child,
                          ),
                        ),
                        child: ConstrainedBox(
                          key: ValueKey('${active.id}:${active.status.wire}'),
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight -
                                (upNext != null ? 40 : 24),
                          ),
                          child: MissionCard(
                            mission: active,
                            busy: busy,
                            onAdvance: (action) => _advance(active, action),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Compact representation of the up-next mission shown peeking behind.
class _UpNextPeek extends StatelessWidget {
  const _UpNextPeek({required this.mission});
  final Assignment mission;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 88,
      padding: const EdgeInsets.symmetric(horizontal: VSpace.x5),
      decoration: BoxDecoration(
        color: VColors.surface800,
        borderRadius: BorderRadius.circular(VRadius.xl),
        border: Border.all(color: VColors.surface700, width: 1),
      ),
      alignment: Alignment.topCenter,
      child: Row(
        children: [
          Text('UP NEXT',
              style: VType.caption.copyWith(
                color: VColors.contentFaint,
                letterSpacing: 1.5,
              )),
          const Spacer(),
          Text(mission.carPlate,
              style: VType.mono.copyWith(color: VColors.contentDefault)),
        ],
      ),
    );
  }
}

/// Skeleton mission card (doc §7.5 loading state).
class _MissionSkeleton extends StatelessWidget {
  const _MissionSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(VSpace.x4),
      child: VShimmer(
        child: Container(
          decoration: BoxDecoration(
            color: VColors.surface800,
            borderRadius: BorderRadius.circular(VRadius.xl),
            border: Border.all(color: VColors.surface700, width: 1),
          ),
          padding: const EdgeInsets.all(VSpace.x5),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: VSkeletonBox(width: 96, height: 24, radius: VRadius.full),
              ),
              Spacer(flex: 2),
              VSkeletonBox(width: 220, height: 48),
              SizedBox(height: VSpace.x3),
              VSkeletonBox(width: 140, height: 16),
              Spacer(flex: 2),
              VSkeletonBox(width: 240, height: 32, radius: VRadius.sm),
              SizedBox(height: VSpace.x6),
              VSkeletonBox(
                  width: double.infinity, height: 14, radius: VRadius.full),
              SizedBox(height: VSpace.x6),
              VSkeletonBox(
                  width: double.infinity, height: 64, radius: VRadius.full),
            ],
          ),
        ),
      ),
    );
  }
}
