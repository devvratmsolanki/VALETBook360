import 'package:flutter_test/flutter_test.dart';
import 'package:valet_driver_app/models/admin_location.dart';
import 'package:valet_driver_app/models/admin_user.dart';
import 'package:valet_driver_app/models/auth_user.dart';
import 'package:valet_driver_app/models/company.dart';

void main() {
  group('AuthUser role routing', () {
    AuthUser u(String role) =>
        AuthUser(id: '1', email: 'x@y.z', role: role);

    test('admin → /admin panel', () {
      final a = u('admin');
      expect(a.isAdmin, isTrue);
      expect(a.isAdminPanel, isTrue);
      expect(a.isOperator, isFalse);
      expect(a.homeRoute, '/admin');
    });

    test('manager (UI "company") → /company panel, scoped to own company', () {
      final m = u('manager');
      expect(m.isManager, isTrue);
      expect(m.isCompany, isTrue);
      expect(m.isAdmin, isFalse);
      expect(m.isAdminPanel, isTrue);
      // Managers now land on the dedicated company panel, not the admin one.
      expect(m.homeRoute, '/company');
    });

    test('valet → /operator (not the admin panel)', () {
      final v = u('valet');
      expect(v.isOperator, isTrue);
      expect(v.isAdminPanel, isFalse);
      expect(v.homeRoute, '/operator');
    });

    test('driver → /driver, unchanged', () {
      final d = u('driver');
      expect(d.isDriver, isTrue);
      expect(d.isAdminPanel, isFalse);
      expect(d.homeRoute, '/driver');
    });
  });

  group('Company.fromJson maps the contract shape', () {
    test('full payload + null tolerance', () {
      final c = Company.fromJson(const {
        'id': '22222222-2222-2222-2222-222222222222',
        'companyName': 'Demo Valet Co',
        'ownerName': 'Demo Owner',
        'phone': null,
        'email': 'owner@valet.demo',
        'createdAt': '2026-06-25T13:26:49Z',
      });
      expect(c.id, startsWith('2222'));
      expect(c.companyName, 'Demo Valet Co');
      expect(c.phone, isNull);
      expect(c.email, 'owner@valet.demo');
      expect(c.displayName, 'Demo Valet Co');
    });

    test('CreateCompanyInput omits blank optionals', () {
      final json = const CreateCompanyInput(
        companyName: 'Acme',
        ownerName: '   ',
        phone: '',
        email: 'a@b.c',
        password: 'Passw0rd',
      ).toJson();
      expect(json.containsKey('ownerName'), isFalse);
      expect(json.containsKey('phone'), isFalse);
      expect(json['companyName'], 'Acme');
      expect(json['email'], 'a@b.c');
    });
  });

  group('AdminLocation', () {
    test('parses keyCapacity as int and builds a location line', () {
      final l = AdminLocation.fromJson(const {
        'id': 'l1',
        'companyId': 'c1',
        'companyName': 'Skyline Parking',
        'name': 'Skyline Downtown',
        'address': '100 Market St',
        'city': 'Metropolis',
        'state': 'CA',
        'country': 'USA',
        'keyCapacity': 120,
      });
      expect(l.keyCapacity, 120);
      expect(l.companyName, 'Skyline Parking');
      expect(l.locationLine, contains('Market St'));
      expect(l.locationLine, contains('Metropolis, CA'));
    });

    test('CreateLocationInput always sends keyCapacity', () {
      final json =
          const CreateLocationInput(name: 'Lot', keyCapacity: 0).toJson();
      expect(json['name'], 'Lot');
      expect(json['keyCapacity'], 0);
      expect(json.containsKey('city'), isFalse);
    });
  });

  group('AdminUser role buckets', () {
    test('roleLabel maps DB roles to the legacy UI vocabulary', () {
      expect(AdminUser.fromJson(const {'id': '1', 'email': 'a', 'role': 'admin'})
          .roleLabel, 'Super Admin');
      expect(AdminUser.fromJson(const {'id': '1', 'email': 'a', 'role': 'manager'})
          .roleLabel, 'Company Owner');
      expect(AdminUser.fromJson(const {'id': '1', 'email': 'a', 'role': 'valet'})
          .roleLabel, 'Operator');
      expect(AdminUser.fromJson(const {'id': '1', 'email': 'a', 'role': 'driver'})
          .roleLabel, 'Driver');
    });

    test('CreateStaffInput drops a blank locationId', () {
      final json = const CreateStaffInput(
        email: 'd@valet.demo',
        password: 'Passw0rd',
        name: 'Dee',
        role: 'driver',
        locationId: '',
      ).toJson();
      expect(json.containsKey('locationId'), isFalse);
      expect(json['role'], 'driver');
    });
  });
}
