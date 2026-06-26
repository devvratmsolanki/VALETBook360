import 'package:flutter_test/flutter_test.dart';
import 'package:valet_driver_app/api/api_client.dart';
import 'package:valet_driver_app/api/realtime_client.dart';
import 'package:valet_driver_app/api/token_store.dart';
import 'package:valet_driver_app/models/lifecycle_status.dart';
import 'package:valet_driver_app/models/transaction.dart';
import 'package:valet_driver_app/state/floor_controller.dart';

/// A fake TokenStore that never touches secure storage (no platform channels in
/// the test VM). The fake ApiClient below never reads tokens, but ApiClient's
/// constructor requires one.
class _FakeTokenStore implements TokenStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

/// Hand-rolled fake ApiClient — overrides only the operator surface the floor
/// controller calls. Mirrors the test/ convention of feeding controllers a
/// stubbed client rather than hitting a real backend.
class _FakeApiClient extends ApiClient {
  _FakeApiClient({
    required this.transactions,
    this.onAction,
  }) : super(_FakeTokenStore());

  List<Transaction> transactions;
  final void Function(String id, OperatorAction action, String? driverId)?
      onAction;

  int fetchCalls = 0;

  @override
  Future<List<Transaction>> fetchTransactions() async {
    fetchCalls++;
    return transactions;
  }

  @override
  Future<Transaction> createTransaction(CreateTransactionInput input) async {
    return Transaction(
      id: 'new',
      carPlate: input.carPlate,
      status: LifecycleStatus.waitingForDriver,
    );
  }

  @override
  Future<void> operatorAction(
    String txId,
    OperatorAction action, {
    String? driverId,
  }) async {
    onAction?.call(txId, action, driverId);
  }
}

Transaction _tx(String id, LifecycleStatus status, {String plate = 'ABC1234'}) {
  return Transaction(id: id, carPlate: plate, status: status);
}

void main() {
  group('FloorController', () {
    test('loads active transactions and drops terminal ones', () async {
      final client = _FakeApiClient(transactions: [
        _tx('a', LifecycleStatus.waitingForDriver),
        _tx('b', LifecycleStatus.parked),
        _tx('c', LifecycleStatus.delivered), // terminal — filtered out.
        _tx('d', LifecycleStatus.cancelled), // terminal — filtered out.
      ]);
      final realtime = RealtimeClient(baseUrl: 'http://localhost:0');
      final controller =
          FloorController(client: client, realtime: realtime);
      addTearDown(controller.dispose);
      addTearDown(realtime.dispose);

      // load() is async in the constructor — let it settle.
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.status, FloorStatus.ready);
      expect(controller.state.transactions.map((t) => t.id), ['a', 'b']);
    });

    test('park action optimistically advances and calls the endpoint',
        () async {
      OperatorAction? called;
      final client = _FakeApiClient(
        transactions: [_tx('a', LifecycleStatus.waitingForDriver)],
        onAction: (_, action, __) => called = action,
      );
      final realtime = RealtimeClient(baseUrl: 'http://localhost:0');
      final controller =
          FloorController(client: client, realtime: realtime);
      addTearDown(controller.dispose);
      addTearDown(realtime.dispose);
      await Future<void>.delayed(Duration.zero);

      final tx = controller.state.transactions.first;
      final ok = await controller.act(tx, OperatorAction.park);

      expect(ok, isTrue);
      expect(called, OperatorAction.park);
      expect(controller.state.transactions.first.status,
          LifecycleStatus.parked);
      expect(controller.state.busyId, isNull);
    });

    test('cancel action removes the card from the floor', () async {
      final client = _FakeApiClient(
        transactions: [
          _tx('a', LifecycleStatus.parked),
          _tx('b', LifecycleStatus.parked),
        ],
      );
      final realtime = RealtimeClient(baseUrl: 'http://localhost:0');
      final controller =
          FloorController(client: client, realtime: realtime);
      addTearDown(controller.dispose);
      addTearDown(realtime.dispose);
      await Future<void>.delayed(Duration.zero);

      final tx = controller.state.transactions.first;
      await controller.act(tx, OperatorAction.cancel);

      expect(controller.state.transactions.map((t) => t.id), ['b']);
    });

    test('tx:status realtime delta mutates a known card in place', () async {
      final client = _FakeApiClient(
        transactions: [_tx('a', LifecycleStatus.parked)],
      );
      // Inject a no-op socket so connect() does not open a real connection;
      // we drive deltas by pushing onto the broadcast events stream directly.
      final realtime = RealtimeClient(baseUrl: 'http://localhost:0');
      final controller =
          FloorController(client: client, realtime: realtime);
      addTearDown(controller.dispose);
      addTearDown(realtime.dispose);
      await Future<void>.delayed(Duration.zero);

      // Simulate a gateway tx:status delta for the known card 'a'.
      realtime.debugEmit('tx:status', {'id': 'a', 'status': 'key_in'});
      // Let the controller's broadcast listener run.
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.transactions.first.status,
          LifecycleStatus.keyIn);
    });

    test('tx:status for an unknown id triggers a reconciling refetch',
        () async {
      final client = _FakeApiClient(
        transactions: [_tx('a', LifecycleStatus.parked)],
      );
      final realtime = RealtimeClient(baseUrl: 'http://localhost:0');
      final controller =
          FloorController(client: client, realtime: realtime);
      addTearDown(controller.dispose);
      addTearDown(realtime.dispose);
      await Future<void>.delayed(Duration.zero);
      final before = client.fetchCalls;

      // 'z' is unknown → controller should refetch the source of truth.
      client.transactions = [
        _tx('a', LifecycleStatus.parked),
        _tx('z', LifecycleStatus.requested),
      ];
      realtime.debugEmit('tx:status', {'id': 'z', 'status': 'requested'});
      await Future<void>.delayed(Duration.zero);

      expect(client.fetchCalls, greaterThan(before));
      expect(controller.state.transactions.map((t) => t.id),
          containsAll(['a', 'z']));
    });
  });
}
