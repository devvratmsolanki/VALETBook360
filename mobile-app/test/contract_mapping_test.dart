import 'package:flutter_test/flutter_test.dart';
import 'package:valet_driver_app/models/assignment.dart';
import 'package:valet_driver_app/models/auth_user.dart';
import 'package:valet_driver_app/models/lifecycle_status.dart';

void main() {
  group('Assignment.fromJson maps the contract shape exactly', () {
    test('full payload', () {
      final a = Assignment.fromJson(const {
        'id': 'tx_1',
        'carPlate': 'ABC123',
        'carMake': 'Tesla',
        'carModel': 'Model 3',
        'carColor': 'Midnight',
        'keyCode': 'A7',
        'status': 'driver_assigned',
        'guestName': 'Riya Sharma',
        'locationId': 'loc_9',
        'requestedAt': '2026-06-25T10:15:00',
      });

      expect(a.id, 'tx_1');
      expect(a.carPlate, 'ABC123');
      expect(a.vehicleLine, 'Tesla Model 3');
      expect(a.keyCode, 'A7');
      expect(a.status, LifecycleStatus.driverAssigned);
      expect(a.guestName, 'Riya Sharma');
      // No-TZ timestamp is treated as UTC.
      expect(a.requestedAt!.isUtc, isTrue);
      expect(a.requestedAt!.hour, 10);
    });

    test('next action chain follows the lifecycle', () {
      expect(LifecycleStatus.driverAssigned.nextAction, DriverAction.enRoute);
      expect(LifecycleStatus.enRoute.nextAction, DriverAction.arrived);
      expect(LifecycleStatus.arrived.nextAction, DriverAction.deliver);
      expect(LifecycleStatus.delivered.nextAction, isNull);
    });
  });

  group('AuthSession.fromJson', () {
    test('flat shape', () {
      final s = AuthSession.fromJson(const {
        'accessToken': 'a.b.c',
        'refreshToken': 'r.e.f',
        'id': 'u1',
        'email': 'driver@valet.demo',
        'role': 'driver',
      });
      expect(s.accessToken, 'a.b.c');
      expect(s.refreshToken, 'r.e.f');
      expect(s.user.isDriver, isTrue);
    });

    test('nested tokens/user shape', () {
      final s = AuthSession.fromJson(const {
        'tokens': {'accessToken': 'x', 'refreshToken': 'y'},
        'user': {'id': 'u2', 'email': 'd@v.demo', 'role': 'driver'},
      });
      expect(s.accessToken, 'x');
      expect(s.user.id, 'u2');
    });
  });
}
