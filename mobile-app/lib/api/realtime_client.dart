import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/api_config.dart';

/// A single realtime event off the Socket.IO gateway.
///
/// The gateway emits three named events — `tx:created`, `tx:status`,
/// `tx:assigned` — each carrying a small delta map. Rather than model each as a
/// distinct class, we surface a uniform `{ event, payload }` record: callers
/// switch on [event] and read the fields they need off [payload]. Unknown ids in
/// a payload trigger a cheap full-list reconciliation upstream.
@immutable
class RealtimeEvent {
  const RealtimeEvent(this.event, this.payload);

  /// One of `tx:created` | `tx:status` | `tx:assigned`.
  final String event;

  /// The delta payload (camelCase keys, per the gateway contract).
  final Map<String, dynamic> payload;

  /// The transaction id the delta targets, if present.
  String? get id => payload['id']?.toString();

  /// The wire status string the delta carries, if present.
  String? get status => payload['status']?.toString();

  @override
  String toString() => 'RealtimeEvent($event, $payload)';
}

/// Connection lifecycle of the realtime socket. Drives graceful degradation:
/// while [disconnected], controllers fall back to REST polling.
enum RealtimeStatus { idle, connecting, connected, disconnected }

/// Socket.IO client for the Vālet realtime gateway.
///
/// Connects to [ApiConfig.realtimeUrl] over a websocket transport, authenticating
/// with the access token via `auth: { token }`. On connect the server auto-joins
/// the socket to its `driver:{userId}`, `company:{companyId}` and
/// `location:{locationId}` rooms (derived from the JWT) — the client does not
/// join rooms itself. Reconnection (with exponential backoff) is handled by the
/// underlying socket_io_client; this wrapper just surfaces the connect/disconnect
/// state on [statusStream] and the typed events on [events].
class RealtimeClient {
  RealtimeClient({String? baseUrl, io.Socket? socket})
      : _baseUrl = baseUrl ?? ApiConfig.realtimeUrl,
        _injected = socket;

  final String _baseUrl;
  final io.Socket? _injected;

  io.Socket? _socket;
  String? _token;

  final _events = StreamController<RealtimeEvent>.broadcast();
  final _status = StreamController<RealtimeStatus>.broadcast();
  RealtimeStatus _current = RealtimeStatus.idle;

  /// Typed broadcast stream of `tx:*` deltas.
  Stream<RealtimeEvent> get events => _events.stream;

  /// Broadcast stream of connection state changes (for fallback toggling).
  Stream<RealtimeStatus> get statusStream => _status.stream;

  RealtimeStatus get status => _current;
  bool get isConnected => _current == RealtimeStatus.connected;

  /// The wire event names we forward.
  static const _eventNames = ['tx:created', 'tx:status', 'tx:assigned'];

  /// Connect (idempotent for the same token). Pass the current access token so
  /// the gateway can resolve the rooms from the JWT.
  void connect(String token) {
    if (_socket != null && _token == token) return;
    // Token changed (re-login) — tear the old socket down first.
    if (_socket != null) dispose();
    _token = token;
    _emitStatus(RealtimeStatus.connecting);

    final socket = _injected ??
        io.io(
          _baseUrl,
          io.OptionBuilder()
              .setTransports(['websocket'])
              .setAuth({'token': token})
              .enableReconnection()
              .setReconnectionDelay(1000)
              .setReconnectionDelayMax(8000)
              .disableAutoConnect()
              .build(),
        );
    _socket = socket;

    socket.onConnect((_) => _emitStatus(RealtimeStatus.connected));
    socket.onConnectError((_) => _emitStatus(RealtimeStatus.disconnected));
    socket.onError((_) => _emitStatus(RealtimeStatus.disconnected));
    socket.onDisconnect((_) => _emitStatus(RealtimeStatus.disconnected));

    for (final name in _eventNames) {
      socket.on(name, (data) => _forward(name, data));
    }

    socket.connect();
  }

  /// Test seam: push a synthetic delta through the events stream without a live
  /// socket. Used by controller tests to simulate gateway emissions.
  @visibleForTesting
  void debugEmit(String event, Map<String, dynamic> payload) =>
      _forward(event, payload);

  /// Test seam: drive the connection-state stream without a live socket.
  @visibleForTesting
  void debugSetStatus(RealtimeStatus status) => _emitStatus(status);

  void _forward(String name, dynamic data) {
    if (_events.isClosed) return;
    final payload = data is Map
        ? data.map((k, v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};
    _events.add(RealtimeEvent(name, payload));
  }

  void _emitStatus(RealtimeStatus s) {
    _current = s;
    if (!_status.isClosed) _status.add(s);
  }

  /// Disconnect and release the socket (keeps the streams open so a later
  /// [connect] can reuse them). Use [dispose] for full teardown.
  void disconnect() {
    _socket?.dispose();
    _socket = null;
    _token = null;
    _emitStatus(RealtimeStatus.disconnected);
  }

  void dispose() {
    _socket?.dispose();
    _socket = null;
    _token = null;
    if (!_events.isClosed) _events.close();
    if (!_status.isClosed) _status.close();
  }
}
