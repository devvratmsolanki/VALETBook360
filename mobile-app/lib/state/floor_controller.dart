import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../api/realtime_client.dart';
import '../models/lifecycle_status.dart';
import '../models/transaction.dart';

enum FloorStatus { loading, ready, empty, error }

@immutable
class FloorState {
  const FloorState({
    this.status = FloorStatus.loading,
    this.transactions = const [],
    this.error,
    this.busyId,
    this.live = false,
  });

  final FloorStatus status;

  /// The active floor feed (newest first; delivered/cancelled fall off).
  final List<Transaction> transactions;
  final String? error;

  /// Id of the card mid-action (locks its buttons, shows a spinner).
  final String? busyId;

  /// True while the realtime socket is connected (drives the live indicator and
  /// turns off the REST poll fallback).
  final bool live;

  FloorState copyWith({
    FloorStatus? status,
    List<Transaction>? transactions,
    String? error,
    bool clearError = false,
    String? busyId,
    bool clearBusy = false,
    bool? live,
  }) {
    return FloorState(
      status: status ?? this.status,
      transactions: transactions ?? this.transactions,
      error: clearError ? null : (error ?? this.error),
      busyId: clearBusy ? null : (busyId ?? this.busyId),
      live: live ?? this.live,
    );
  }
}

/// Operator floor controller. Mirrors [MissionsController]: loads the active
/// feed from `GET /api/operator/transactions`, exposes optimistic action methods
/// (create / park / keyIn / request / assign / cancel), and layers a Socket.IO
/// realtime subscription on top — applying `tx:created` / `tx:status` deltas in
/// place. When the socket is down it falls back to a 12s REST poll.
class FloorController extends StateNotifier<FloorState> {
  FloorController({required ApiClient client, required RealtimeClient realtime})
      : _client = client,
        _realtime = realtime,
        super(const FloorState()) {
    _wireRealtime();
    load();
  }

  final ApiClient _client;
  final RealtimeClient _realtime;

  StreamSubscription<RealtimeEvent>? _eventSub;
  StreamSubscription<RealtimeStatus>? _statusSub;
  Timer? _pollTimer;

  static const _pollInterval = Duration(seconds: 12);

  static const _terminal = {
    LifecycleStatus.delivered,
    LifecycleStatus.cancelled,
  };

  void _wireRealtime() {
    _statusSub = _realtime.statusStream.listen((s) {
      final live = s == RealtimeStatus.connected;
      if (live != state.live) state = state.copyWith(live: live);
      if (live) {
        _stopPoll();
        // Reconcile any deltas missed while disconnected.
        load(silent: true);
      } else {
        _startPoll();
      }
    });
    _eventSub = _realtime.events.listen(_onRealtime);
    // If the socket never connects, the poll keeps the floor fresh.
    if (!_realtime.isConnected) _startPoll();
  }

  void _startPoll() {
    _pollTimer ??= Timer.periodic(_pollInterval, (_) {
      if (!_realtime.isConnected) load(silent: true);
    });
  }

  void _stopPoll() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Apply a `tx:created` / `tx:status` delta. Unknown ids → cheap refetch.
  void _onRealtime(RealtimeEvent ev) {
    // `tx:assigned` is driver-room scoped; operator only cares about
    // created/status, but driver_assigned also arrives as a status delta.
    if (ev.event == 'tx:assigned') return;

    final id = ev.id;
    if (id == null) return;

    final known = state.transactions.any((t) => t.id == id);
    if (!known) {
      // New card or one that scrolled off — reconcile from the source of truth.
      load(silent: true);
      return;
    }

    final statusStr = ev.status;
    if (statusStr == null) {
      load(silent: true);
      return;
    }
    final next = LifecycleStatus.fromWire(statusStr);
    _applyStatus(id, next);
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      state = state.copyWith(status: FloorStatus.loading, clearError: true);
    }
    try {
      final all = await _client.fetchTransactions();
      final active =
          all.where((t) => !_terminal.contains(t.status)).toList();
      state = state.copyWith(
        status: active.isEmpty ? FloorStatus.empty : FloorStatus.ready,
        transactions: active,
        clearError: true,
      );
    } on ApiException catch (e) {
      if (e.isUnauthorized) return; // global 401 bounce handles it.
      // A silent (poll/reconcile) failure shouldn't blow away a good list.
      if (silent && state.transactions.isNotEmpty) return;
      state = state.copyWith(status: FloorStatus.error, error: e.message);
    } catch (_) {
      if (silent && state.transactions.isNotEmpty) return;
      state = state.copyWith(
        status: FloorStatus.error,
        error: 'Could not load the floor. Pull to retry.',
      );
    }
  }

  /// Create a new car (status `waiting_for_driver`). Returns the created
  /// transaction on success, or null on failure (caller toasts the error).
  Future<Transaction?> create(CreateTransactionInput input) async {
    try {
      final tx = await _client.createTransaction(input);
      // Optimistically prepend (newest first); the realtime tx:created may also
      // arrive — _onRealtime is idempotent for a known id.
      if (!state.transactions.any((t) => t.id == tx.id)) {
        state = state.copyWith(
          status: FloorStatus.ready,
          transactions: [tx, ...state.transactions],
          clearError: true,
        );
      }
      return tx;
    } on ApiException catch (e) {
      state = state.copyWith(error: e.message);
      return null;
    } catch (_) {
      state = state.copyWith(error: 'Could not add the car. Please try again.');
      return null;
    }
  }

  /// Run an operator transition with an optimistic in-place status flip and
  /// rollback on failure. Returns true on success.
  Future<bool> act(
    Transaction tx,
    OperatorAction action, {
    String? driverId,
  }) async {
    if (state.busyId != null) return false;
    final original = tx.status;

    state = state.copyWith(
      busyId: tx.id,
      transactions: _withStatus(tx.id, action.to),
      clearError: true,
    );

    try {
      await _client.operatorAction(tx.id, action, driverId: driverId);
      // Cancelled cars leave the floor.
      if (action == OperatorAction.cancel) {
        final remaining =
            state.transactions.where((t) => t.id != tx.id).toList();
        state = state.copyWith(
          status: remaining.isEmpty ? FloorStatus.empty : FloorStatus.ready,
          transactions: remaining,
          clearBusy: true,
        );
      } else if (action == OperatorAction.assignPark) {
        // Park assignment doesn't advance status — stamp the chosen driver so
        // the card flips from "Assign to park" to "Awaiting park" instantly.
        state = state.copyWith(
          transactions: state.transactions
              .map((t) =>
                  t.id == tx.id ? t.copyWith(parkedByDriverId: driverId) : t)
              .toList(),
          clearBusy: true,
        );
      } else {
        state = state.copyWith(
          transactions: _withStatus(tx.id, action.to),
          clearBusy: true,
        );
      }
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(
        transactions: _withStatus(tx.id, original),
        clearBusy: true,
        error: e.message,
      );
      return false;
    } catch (_) {
      state = state.copyWith(
        transactions: _withStatus(tx.id, original),
        clearBusy: true,
        error: 'Could not update the car. Please try again.',
      );
      return false;
    }
  }

  /// Apply a realtime-driven status change in place (drops the card if it went
  /// terminal). Does not touch [busyId] — local actions own that.
  void _applyStatus(String id, LifecycleStatus status) {
    if (_terminal.contains(status)) {
      final remaining = state.transactions.where((t) => t.id != id).toList();
      state = state.copyWith(
        status: remaining.isEmpty ? FloorStatus.empty : FloorStatus.ready,
        transactions: remaining,
      );
      return;
    }
    state = state.copyWith(
      status: FloorStatus.ready,
      transactions: _withStatus(id, status),
    );
  }

  List<Transaction> _withStatus(String id, LifecycleStatus status) {
    return state.transactions
        .map((t) => t.id == id ? t.copyWith(status: status) : t)
        .toList();
  }

  void clearError() {
    if (state.error != null) state = state.copyWith(clearError: true);
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _statusSub?.cancel();
    _stopPoll();
    super.dispose();
  }
}
