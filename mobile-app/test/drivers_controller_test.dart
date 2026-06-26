import 'package:flutter_test/flutter_test.dart';
import 'package:valet_driver_app/api/api_client.dart';
import 'package:valet_driver_app/api/api_exception.dart';
import 'package:valet_driver_app/api/token_store.dart';
import 'package:valet_driver_app/models/driver.dart';
import 'package:valet_driver_app/state/drivers_controller.dart';

/// A fake TokenStore that never touches secure storage (no platform channels in
/// the test VM). Mirrors floor_controller_test's fake.
class _FakeTokenStore implements TokenStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

/// Hand-rolled fake ApiClient overriding only [fetchDrivers]. Can return a list
/// or throw, so we exercise the ready / empty / error branches.
class _FakeApiClient extends ApiClient {
  _FakeApiClient({this.drivers = const [], this.error})
      : super(_FakeTokenStore());

  List<Driver> drivers;
  ApiException? error;
  int fetchCalls = 0;

  @override
  Future<List<Driver>> fetchDrivers() async {
    fetchCalls++;
    if (error != null) throw error!;
    return drivers;
  }
}

Driver _d(String id, String name) =>
    Driver(id: id, name: name, email: '$name@valet.demo');

void main() {
  group('DriversController', () {
    test('load() → ready with the company drivers', () async {
      final client = _FakeApiClient(drivers: [_d('1', 'Ada'), _d('2', 'Cleo')]);
      final controller = DriversController(client: client);
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.state.status, DriversStatus.ready);
      expect(controller.state.drivers.map((d) => d.id), ['1', '2']);
      expect(controller.state.error, isNull);
    });

    test('load() with no drivers → empty state', () async {
      final client = _FakeApiClient(drivers: const []);
      final controller = DriversController(client: client);
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.state.status, DriversStatus.empty);
      expect(controller.state.drivers, isEmpty);
    });

    test('load() surfaces an error message on failure', () async {
      final client = _FakeApiClient(
        error: ApiException(message: 'Your account is not linked to a company.'),
      );
      final controller = DriversController(client: client);
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.state.status, DriversStatus.error);
      expect(controller.state.error, contains('not linked'));
    });

    test('401 is swallowed (global bounce owns it)', () async {
      final client = _FakeApiClient(
        error: ApiException(
            message: 'Session expired', statusCode: 401, isUnauthorized: true),
      );
      final controller = DriversController(client: client);
      addTearDown(controller.dispose);

      await controller.load();

      // Stays in the pre-failure loading state; no error surfaced to the UI.
      expect(controller.state.status, DriversStatus.loading);
      expect(controller.state.error, isNull);
    });
  });
}
