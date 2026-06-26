import 'package:flutter_test/flutter_test.dart';
import 'package:valet_driver_app/api/api_client.dart';
import 'package:valet_driver_app/api/api_exception.dart';
import 'package:valet_driver_app/api/token_store.dart';
import 'package:valet_driver_app/models/admin_location.dart';
import 'package:valet_driver_app/models/admin_user.dart';
import 'package:valet_driver_app/models/company.dart';
import 'package:valet_driver_app/state/admin_locations_controller.dart';
import 'package:valet_driver_app/state/admin_users_controller.dart';
import 'package:valet_driver_app/state/companies_controller.dart';
import 'package:valet_driver_app/state/company_detail_controller.dart';

/// A fake TokenStore that never touches secure storage (no platform channels in
/// the test VM). Mirrors the floor/drivers controller test fakes.
class _FakeTokenStore implements TokenStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

/// Hand-rolled fake ApiClient overriding only the admin surface the controllers
/// touch. Each method can return canned data or throw a canned [ApiException],
/// so we exercise ready / empty / error / create branches without a backend.
class _FakeApiClient extends ApiClient {
  _FakeApiClient({
    this.companies = const [],
    this.locations = const [],
    this.operators = const [],
    this.drivers = const [],
    this.allLocations = const [],
    this.allUsers = const [],
    this.company,
    this.loadError,
    this.createError,
  }) : super(_FakeTokenStore());

  List<Company> companies;
  List<AdminLocation> locations;
  List<AdminUser> operators;
  List<AdminUser> drivers;
  List<AdminLocation> allLocations;
  List<AdminUser> allUsers;
  Company? company;

  /// Thrown by every list fetch when set (drives error-state tests).
  ApiException? loadError;

  /// Thrown by create/update when set (drives create-error tests).
  ApiException? createError;

  int companyCreateCalls = 0;
  int locationCreateCalls = 0;
  int staffCreateCalls = 0;
  String? lastStaffRole;

  @override
  Future<List<Company>> fetchCompanies() async {
    if (loadError != null) throw loadError!;
    return companies;
  }

  @override
  Future<Company> createCompany(CreateCompanyInput input) async {
    if (createError != null) throw createError!;
    companyCreateCalls++;
    final c = Company(id: 'new', companyName: input.companyName);
    companies = [...companies, c];
    return c;
  }

  @override
  Future<Company> fetchCompany(String id) async {
    if (loadError != null) throw loadError!;
    return company ?? Company(id: id, companyName: 'Acme');
  }

  @override
  Future<List<AdminLocation>> fetchCompanyLocations(String companyId) async {
    if (loadError != null) throw loadError!;
    return locations;
  }

  @override
  Future<AdminLocation> createLocation(
    String companyId,
    CreateLocationInput input,
  ) async {
    if (createError != null) throw createError!;
    locationCreateCalls++;
    final l = AdminLocation(
      id: 'loc-new',
      companyId: companyId,
      name: input.name,
      keyCapacity: input.keyCapacity,
    );
    locations = [...locations, l];
    allLocations = [...allLocations, l];
    return l;
  }

  @override
  Future<AdminLocation> updateLocation(
    String locationId,
    CreateLocationInput input,
  ) async {
    if (createError != null) throw createError!;
    return AdminLocation(
      id: locationId,
      companyId: 'c',
      name: input.name,
      keyCapacity: input.keyCapacity,
    );
  }

  @override
  Future<List<AdminUser>> fetchCompanyUsers(
    String companyId, {
    String? role,
  }) async {
    if (loadError != null) throw loadError!;
    return role == 'driver' ? drivers : operators;
  }

  @override
  Future<AdminUser> createStaff(
    String companyId,
    CreateStaffInput input,
  ) async {
    if (createError != null) throw createError!;
    staffCreateCalls++;
    lastStaffRole = input.role;
    final u = AdminUser(
      id: 'u-new',
      email: input.email,
      name: input.name,
      role: input.role,
      companyId: companyId,
    );
    if (input.role == 'driver') {
      drivers = [...drivers, u];
    } else {
      operators = [...operators, u];
    }
    return u;
  }

  @override
  Future<List<AdminLocation>> fetchAllLocations() async {
    if (loadError != null) throw loadError!;
    return allLocations;
  }

  @override
  Future<List<AdminUser>> fetchAllUsers() async {
    if (loadError != null) throw loadError!;
    return allUsers;
  }
}

Company _co(String id, String name) => Company(id: id, companyName: name);
AdminLocation _loc(String id, String companyId, String name,
        {String? companyName, int cap = 10}) =>
    AdminLocation(
      id: id,
      companyId: companyId,
      companyName: companyName,
      name: name,
      keyCapacity: cap,
    );
AdminUser _user(String id, String role,
        {String? companyName, String name = 'X'}) =>
    AdminUser(
      id: id,
      email: '$id@valet.demo',
      name: name,
      role: role,
      companyName: companyName,
    );

void main() {
  group('CompaniesController', () {
    test('load() → ready with companies', () async {
      final client =
          _FakeApiClient(companies: [_co('1', 'Demo'), _co('2', 'Skyline')]);
      final c = CompaniesController(client: client);
      addTearDown(c.dispose);
      await Future<void>.delayed(Duration.zero);

      expect(c.state.status, CompaniesStatus.ready);
      expect(c.state.companies.map((x) => x.id), ['1', '2']);
    });

    test('load() with none → empty', () async {
      final client = _FakeApiClient(companies: const []);
      final c = CompaniesController(client: client);
      addTearDown(c.dispose);
      await Future<void>.delayed(Duration.zero);

      expect(c.state.status, CompaniesStatus.empty);
    });

    test('load() surfaces the userMessage on error', () async {
      final client = _FakeApiClient(
          loadError: ApiException(message: 'You do not have access.'));
      final c = CompaniesController(client: client);
      addTearDown(c.dispose);
      await Future<void>.delayed(Duration.zero);

      expect(c.state.status, CompaniesStatus.error);
      expect(c.state.error, contains('access'));
    });

    test('create() refetches and exposes the new company', () async {
      final client = _FakeApiClient(companies: [_co('1', 'Demo')]);
      final c = CompaniesController(client: client);
      addTearDown(c.dispose);
      await Future<void>.delayed(Duration.zero);

      final created = await c.create(const CreateCompanyInput(
        companyName: 'Northwind',
        email: 'owner@northwind.com',
        password: 'Passw0rd',
      ));

      expect(created, isNotNull);
      expect(client.companyCreateCalls, 1);
      expect(c.state.companies.map((x) => x.companyName),
          containsAll(['Demo', 'Northwind']));
    });

    test('create() surfaces EMAIL_TAKEN as createError', () async {
      final client = _FakeApiClient(
        companies: [_co('1', 'Demo')],
        createError: ApiException(
          message: 'That email is already in use.',
          statusCode: 409,
          code: 'EMAIL_TAKEN',
        ),
      );
      final c = CompaniesController(client: client);
      addTearDown(c.dispose);
      await Future<void>.delayed(Duration.zero);

      final created = await c.create(const CreateCompanyInput(
        companyName: 'Dup',
        email: 'owner@valet.demo',
        password: 'Passw0rd',
      ));

      expect(created, isNull);
      expect(c.createError, contains('already in use'));
    });
  });

  group('CompanyDetailController', () {
    test('load() fans out overview + locations + operators + drivers',
        () async {
      final client = _FakeApiClient(
        company: _co('c1', 'Demo'),
        locations: [_loc('l1', 'c1', 'Garage')],
        operators: [_user('op1', 'valet')],
        drivers: [_user('dr1', 'driver')],
      );
      final c = CompanyDetailController(client: client, companyId: 'c1');
      addTearDown(c.dispose);
      await Future<void>.delayed(Duration.zero);

      expect(c.state.status, DetailStatus.ready);
      expect(c.state.company?.companyName, 'Demo');
      expect(c.state.locations.single.name, 'Garage');
      expect(c.state.operators.single.id, 'op1');
      expect(c.state.drivers.single.id, 'dr1');
    });

    test('addLocation() creates and refreshes the locations slice', () async {
      final client = _FakeApiClient(company: _co('c1', 'Demo'));
      final c = CompanyDetailController(client: client, companyId: 'c1');
      addTearDown(c.dispose);
      await Future<void>.delayed(Duration.zero);

      final ok = await c.addLocation(
          const CreateLocationInput(name: 'New Lot', keyCapacity: 20));

      expect(ok, isTrue);
      expect(client.locationCreateCalls, 1);
      expect(c.state.locations.map((l) => l.name), contains('New Lot'));
    });

    test('addStaff(driver) routes to the drivers slice', () async {
      final client = _FakeApiClient(company: _co('c1', 'Demo'));
      final c = CompanyDetailController(client: client, companyId: 'c1');
      addTearDown(c.dispose);
      await Future<void>.delayed(Duration.zero);

      final ok = await c.addStaff(const CreateStaffInput(
        email: 'd@valet.demo',
        password: 'Passw0rd',
        name: 'Dee',
        role: 'driver',
      ));

      expect(ok, isTrue);
      expect(client.lastStaffRole, 'driver');
      expect(c.state.drivers.map((u) => u.email), contains('d@valet.demo'));
      expect(c.state.operators, isEmpty);
    });

    test('addStaff surfaces INVALID_STAFF_ROLE-style error', () async {
      final client = _FakeApiClient(
        company: _co('c1', 'Demo'),
        createError: ApiException(
          message: 'Staff role must be operator or driver.',
          statusCode: 400,
          code: 'INVALID_STAFF_ROLE',
        ),
      );
      final c = CompanyDetailController(client: client, companyId: 'c1');
      addTearDown(c.dispose);
      await Future<void>.delayed(Duration.zero);

      final ok = await c.addStaff(const CreateStaffInput(
        email: 'x@valet.demo',
        password: 'Passw0rd',
        name: 'X',
        role: 'valet',
      ));

      expect(ok, isFalse);
      expect(c.createError, contains('operator or driver'));
    });
  });

  group('AdminLocationsController', () {
    test('load() groups locations by company', () async {
      final client = _FakeApiClient(allLocations: [
        _loc('l1', 'c1', 'A', companyName: 'Demo'),
        _loc('l2', 'c1', 'B', companyName: 'Demo'),
        _loc('l3', 'c2', 'C', companyName: 'Skyline'),
      ]);
      final c = AdminLocationsController(client: client);
      addTearDown(c.dispose);
      await Future<void>.delayed(Duration.zero);

      expect(c.state.status, AdminLocationsStatus.ready);
      final grouped = c.state.byCompany;
      expect(grouped['Demo']!.length, 2);
      expect(grouped['Skyline']!.length, 1);
    });

    test('empty → empty state', () async {
      final client = _FakeApiClient(allLocations: const []);
      final c = AdminLocationsController(client: client);
      addTearDown(c.dispose);
      await Future<void>.delayed(Duration.zero);

      expect(c.state.status, AdminLocationsStatus.empty);
    });
  });

  group('AdminUsersController', () {
    test('separates super admins from company users', () async {
      final client = _FakeApiClient(allUsers: [
        _user('a1', 'admin'),
        _user('m1', 'manager', companyName: 'Demo'),
        _user('v1', 'valet', companyName: 'Demo'),
        _user('d1', 'driver', companyName: 'Skyline'),
      ]);
      final c = AdminUsersController(client: client);
      addTearDown(c.dispose);
      await Future<void>.delayed(Duration.zero);

      expect(c.state.status, AdminUsersStatus.ready);
      expect(c.state.superAdmins.map((u) => u.id), ['a1']);
      expect(c.state.byCompany['Demo']!.map((u) => u.id),
          containsAll(['m1', 'v1']));
      expect(c.state.byCompany['Skyline']!.single.id, 'd1');
    });
  });
}
