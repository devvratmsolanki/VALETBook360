import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../models/assignment.dart';
import '../models/lifecycle_status.dart';
import '../models/transaction.dart';
import '../state/missions_controller.dart';
import '../state/providers.dart';
import '../theme/motion.dart';
import '../theme/v_breakpoints.dart';
import '../theme/v_colors.dart';
import '../theme/v_theme.dart';
import '../theme/v_tokens.dart';
import '../utils/qr_sheet.dart' as qr_util;
import '../widgets/app_logo.dart';
import '../widgets/mission_card.dart';
import '../widgets/success_burst.dart';
import '../widgets/theme_toggle_button.dart';
import '../widgets/v_chips.dart';
import '../widgets/v_states.dart';

/// 7.5 Driver — Mission Stack (home). Active mission full-bleed with the
/// up-next card peeking behind; loading skeleton / empty / error+retry;
/// delivered success micro-interaction.
class MissionStackScreen extends ConsumerStatefulWidget {
  const MissionStackScreen({super.key});

  @override
  ConsumerState<MissionStackScreen> createState() => _MissionStackScreenState();
}

class _MissionStackScreenState extends ConsumerState<MissionStackScreen>
    with SingleTickerProviderStateMixin {
  bool _showBurst = false;
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

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
            tooltip: 'Guest QR',
            constraints: const BoxConstraints(
              minWidth: VTarget.minTouch,
              minHeight: VTarget.minTouch,
            ),
            icon: Icon(Icons.qr_code_rounded, color: VColors.contentMuted),
            onPressed: () => qr_util.showQrSheet(
                context, user?.displayName ?? 'Guest Portal'),
          ),
          const ThemeToggleButton(),
          IconButton(
            tooltip: 'Refresh',
            constraints: const BoxConstraints(
              minWidth: VTarget.minTouch,
              minHeight: VTarget.minTouch,
            ),
            icon: Icon(Icons.refresh_rounded, color: VColors.contentMuted),
            onPressed: () =>
                ref.read(missionsControllerProvider.notifier).load(),
          ),
          IconButton(
            tooltip: 'Sign out',
            constraints: const BoxConstraints(
              minWidth: VTarget.minTouch,
              minHeight: VTarget.minTouch,
            ),
            icon: Icon(Icons.logout_rounded, color: VColors.contentMuted),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
          const SizedBox(width: VSpace.x2),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: VColors.brand400,
          labelColor: VColors.contentStrong,
          unselectedLabelColor: VColors.contentMuted,
          labelStyle: VType.label,
          tabs: const [
            Tab(text: 'Active'),
            Tab(text: 'Delivered'),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: TabBarView(
          controller: _tab,
          children: [
            Stack(
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
            _DriverDeliveredTab(client: ref.read(apiClientProvider)),
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
            children: [
              SizedBox(
                  height: context.responsive(compact: 80, expanded: 160)),
              const VEmptyState(
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
                // The driver mission flow fills height (the active card's
                // Expanded children need a bounded height from the min-height
                // chain below), so we cap WIDTH on the card itself rather than
                // wrap the Stack in a centering Align — an Align here would strip
                // the min-height constraint and the flex children would overflow.
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
                          // The mission card's Column distributes content with
                          // flex Spacers, so it needs a BOUNDED height. Inside the
                          // scroll view the incoming maxHeight is infinite, so pin
                          // the card to the viewport height (minus the peek
                          // offset) with a TIGHT height — a min-height-only box
                          // leaves maxHeight unbounded and the Spacers assert.
                          // maxWidth caps it on wide screens; the Stack's
                          // topCenter centers it.
                          constraints: BoxConstraints.tightFor(
                            height: constraints.maxHeight -
                                (upNext != null ? 40 : 24),
                          ).copyWith(maxWidth: 640),
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

/// Driver's delivered-car history tab.
/// Fetches from GET /api/driver/history (delivered cars only, newest first).
class _DriverDeliveredTab extends StatefulWidget {
  const _DriverDeliveredTab({required this.client});
  final ApiClient client;

  @override
  State<_DriverDeliveredTab> createState() => _DriverDeliveredTabState();
}

class _DriverDeliveredTabState extends State<_DriverDeliveredTab>
    with AutomaticKeepAliveClientMixin {
  static const _kSize = 50;

  final List<Transaction> _items = [];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    if (reset) {
      _items.clear();
      _page = 0;
      _hasMore = true;
      _error = null;
    }
    setState(() => _loading = true);
    try {
      final page = await widget.client.fetchDriverHistory(page: _page, size: _kSize);
      if (!mounted) return;
      setState(() {
        _items.addAll(page);
        _hasMore = page.length == _kSize;
        _page++;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : 'Could not load history.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: VBanner(message: _error!, onRetry: () => _load(reset: true)),
      );
    }
    if (_items.isEmpty) {
      return const VEmptyState(
        icon: Icons.check_circle_outline_rounded,
        headline: 'No deliveries yet',
        hint: 'Cars you deliver will appear here',
      );
    }
    return RefreshIndicator(
      color: VColors.brand400,
      backgroundColor: VColors.surface800,
      onRefresh: () => _load(reset: true),
      child: ListView.separated(
        padding: const EdgeInsets.all(VSpace.x4),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: VSpace.x3),
        itemBuilder: (_, i) {
          if (i == _items.length) {
            return Center(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(VSpace.x4),
                      child: CircularProgressIndicator(),
                    )
                  : TextButton(
                      onPressed: _load,
                      child: const Text('Load more'),
                    ),
            );
          }
          return _DriverDeliveredCard(tx: _items[i]);
        },
      ),
    );
  }
}

class _DriverDeliveredCard extends StatelessWidget {
  const _DriverDeliveredCard({required this.tx});
  final Transaction tx;

  @override
  Widget build(BuildContext context) {
    final dt = tx.deliveredAt?.toLocal();
    final timeLabel = dt == null
        ? '—'
        : '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}  ·  '
            '${_month(dt.month)} ${dt.day}';
    return Container(
      padding: const EdgeInsets.all(VSpace.x4),
      decoration: BoxDecoration(
        color: VColors.surface800,
        borderRadius: BorderRadius.circular(VRadius.xl),
        border: Border.all(color: VColors.surface700, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tx.carPlate,
                    style: VType.monoLg.copyWith(
                        color: VColors.contentStrong)),
                if (tx.vehicleSubline.isNotEmpty) ...[
                  const SizedBox(height: VSpace.x1),
                  Text(tx.vehicleSubline,
                      style: VType.caption,
                      overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: VSpace.x2),
                Wrap(
                  spacing: VSpace.x2,
                  runSpacing: VSpace.x2,
                  children: [
                    if (tx.keyCode != null) VKeySlotChip(code: tx.keyCode!),
                    if (tx.guestName != null)
                      VMetaChip(
                          icon: Icons.person_outline_rounded,
                          label: tx.guestName!),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: VSpace.x3),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(Icons.check_circle_rounded,
                  color: VColors.statusDone, size: 20),
              const SizedBox(height: VSpace.x2),
              Text(timeLabel,
                  style: VType.caption,
                  textAlign: TextAlign.right),
            ],
          ),
        ],
      ),
    );
  }

  static String _month(int m) => const [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m];
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
