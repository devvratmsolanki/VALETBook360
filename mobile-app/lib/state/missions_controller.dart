import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../api/realtime_client.dart';
import '../models/assignment.dart';
import '../models/lifecycle_status.dart';

enum MissionsStatus { loading, ready, empty, error }

@immutable
class MissionsState {
  const MissionsState({
    this.status = MissionsStatus.loading,
    this.missions = const [],
    this.error,
    this.advancingId,
  });

  final MissionsStatus status;

  /// Active missions only (delivered/cancelled fall off the stack).
  final List<Assignment> missions;
  final String? error;

  /// Id currently being advanced (locks its slide track, shows spinner).
  final String? advancingId;

  Assignment? get active => missions.isNotEmpty ? missions.first : null;
  Assignment? get upNext => missions.length > 1 ? missions[1] : null;

  MissionsState copyWith({
    MissionsStatus? status,
    List<Assignment>? missions,
    String? error,
    bool clearError = false,
    String? advancingId,
    bool clearAdvancing = false,
  }) {
    return MissionsState(
      status: status ?? this.status,
      missions: missions ?? this.missions,
      error: clearError ? null : (error ?? this.error),
      advancingId: clearAdvancing ? null : (advancingId ?? this.advancingId),
    );
  }
}

class MissionsController extends StateNotifier<MissionsState> {
  MissionsController({required ApiClient client, RealtimeClient? realtime})
      : _client = client,
        _realtime = realtime,
        super(const MissionsState()) {
    _wireRealtime();
    load();
  }

  /// The statuses that keep a car on a driver's stack: the intake PARK mission
  /// ({@code waitingForDriver}) plus the retrieval tail. Once a car leaves this
  /// set (parked, delivered, cancelled) the driver's job on it is done and the
  /// card drops off. Mirrors the backend's park + retrieval active sets.
  static const Set<LifecycleStatus> _driverActiveStatuses = {
    LifecycleStatus.waitingForDriver,
    LifecycleStatus.driverAssigned,
    LifecycleStatus.enRoute,
    LifecycleStatus.arrived,
  };

  final ApiClient _client;
  final RealtimeClient? _realtime;

  StreamSubscription<RealtimeEvent>? _eventSub;
  StreamSubscription<RealtimeStatus>? _statusSub;
  Timer? _pollTimer;

  /// Fallback poll cadence while the socket is down (graceful degradation —
  /// realtime is layered on top of the existing poll, never replaces it).
  static const _pollInterval = Duration(seconds: 12);

  bool get isAdvancing => state.advancingId != null;

  void _wireRealtime() {
    final rt = _realtime;
    if (rt == null) {
      // No realtime wired (e.g. tests) — keep the original poll behaviour.
      _startPoll();
      return;
    }
    _statusSub = rt.statusStream.listen((s) {
      if (s == RealtimeStatus.connected) {
        _stopPoll();
        load(silent: true); // reconcile anything missed offline.
      } else {
        _startPoll();
      }
    });
    // `tx:assigned` (new mission in driver:{id}) and `tx:status` both warrant a
    // refresh; the assignments feed is the source of truth for the stack.
    _eventSub = rt.events.listen((ev) {
      if (ev.event == 'tx:assigned' || ev.event == 'tx:status') {
        load(silent: true);
      }
    });
    if (!rt.isConnected) _startPoll();
  }

  void _startPoll() {
    _pollTimer ??= Timer.periodic(_pollInterval, (_) {
      final connected = _realtime?.isConnected ?? false;
      if (!connected) load(silent: true);
    });
  }

  void _stopPoll() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> load({bool silent = false}) async {
    debugPrint('[MissionsController] load() start — silent=$silent controller=${identityHashCode(this)}');
    if (!silent) {
      state = state.copyWith(status: MissionsStatus.loading, clearError: true);
    }
    try {
      final all = await _client.fetchAssignments();
      final active = all
          .where((a) =>
              a.status != LifecycleStatus.delivered &&
              a.status != LifecycleStatus.cancelled)
          .toList();
      debugPrint('[MissionsController] load() SUCCESS — ${active.length} active missions → ${active.isEmpty ? "empty" : "ready"}');
      state = MissionsState(
        status: active.isEmpty ? MissionsStatus.empty : MissionsStatus.ready,
        missions: active,
      );
    } on ApiException catch (e) {
      // A 401 is handled by the global bounce; don't paint an error over it.
      debugPrint('[MissionsController] load() ApiException — statusCode=${e.statusCode} isUnauthorized=${e.isUnauthorized} msg=${e.message}');
      if (e.isUnauthorized) return;
      state = state.copyWith(
        status: MissionsStatus.error,
        error: e.message,
      );
    } catch (e, st) {
      debugPrint('[MissionsController] load() UNEXPECTED ERROR — $e\n$st');
      state = state.copyWith(
        status: MissionsStatus.error,
        error: 'Could not load your missions. Pull to retry.',
      );
    }
  }

  @override
  void dispose() {
    debugPrint('[MissionsController] dispose() — controller=${identityHashCode(this)}');
    _eventSub?.cancel();
    _statusSub?.cancel();
    _stopPoll();
    super.dispose();
  }

  /// Advance the active mission. Returns the resulting status on success, or
  /// null on failure (the caller surfaces an error toast + error haptic).
  ///
  /// Optimistic: the rail moves immediately; on failure we roll back (mirrors
  /// the web operator-dashboard rollback instinct).
  Future<LifecycleStatus?> advance(Assignment mission, DriverAction action) async {
    if (state.advancingId != null) return null;
    final original = mission.status;

    // Optimistic in-place mutation.
    state = state.copyWith(
      advancingId: mission.id,
      missions: _replace(mission.id, action.to),
      clearError: true,
    );

    try {
      final result = await _client.advance(mission.id, action);
      if (!_driverActiveStatuses.contains(result)) {
        // The mission left the driver's active set — a delivered retrieval, or
        // a just-parked car (the intake/park mission is done once it's parked).
        // Drop it from the stack.
        final remaining =
            state.missions.where((m) => m.id != mission.id).toList();
        state = MissionsState(
          status:
              remaining.isEmpty ? MissionsStatus.empty : MissionsStatus.ready,
          missions: remaining,
        );
      } else {
        state = state.copyWith(
          missions: _replace(mission.id, result),
          clearAdvancing: true,
        );
      }
      return result;
    } on ApiException catch (e) {
      // Roll back the optimistic move.
      state = state.copyWith(
        missions: _replace(mission.id, original),
        clearAdvancing: true,
        error: e.message,
      );
      return null;
    } catch (_) {
      state = state.copyWith(
        missions: _replace(mission.id, original),
        clearAdvancing: true,
        error: 'Could not update the mission. Please try again.',
      );
      return null;
    }
  }

  List<Assignment> _replace(String id, LifecycleStatus status) {
    return state.missions
        .map((m) => m.id == id ? m.copyWith(status: status) : m)
        .toList();
  }

  void clearError() {
    if (state.error != null) state = state.copyWith(clearError: true);
  }
}
