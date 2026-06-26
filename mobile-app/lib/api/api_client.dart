import 'package:dio/dio.dart';
import '../config/api_config.dart';
import '../models/admin_location.dart';
import '../models/admin_user.dart';
import '../models/assignment.dart';
import '../models/auth_user.dart';
import '../models/company.dart';
import '../models/contract.dart';
import '../models/driver.dart';
import '../models/key_slot.dart';
import '../models/lifecycle_status.dart';
import '../models/transaction.dart';
import 'api_exception.dart';
import 'token_store.dart';

/// Signalled when a 401 is seen on an authed call so the app can bounce to
/// login (doc: "401 → bounce to login").
typedef UnauthorizedHandler = void Function();

/// Typed client over the two backends. Handles bearer injection, 401 bounce,
/// and problem+json parsing. AUTH and CORE get separate dio instances so they
/// can point at different hosts/ports while sharing interceptor logic.
class ApiClient {
  ApiClient(this._tokens, {Dio? authDio, Dio? coreDio})
      : _auth = authDio ?? _build(ApiConfig.authBaseUrl),
        _core = coreDio ?? _build(ApiConfig.coreBaseUrl) {
    _core.interceptors.add(_bearerInterceptor());
    // AUTH also carries the bearer for authed reads (e.g. the driver picker).
    // login/refresh simply have no token yet, so the header is omitted there.
    _auth.interceptors.add(_bearerInterceptor());
  }

  final TokenStore _tokens;
  final Dio _auth;
  final Dio _core;

  /// Set by the app shell; invoked on any 401 from an authed (CORE) call.
  UnauthorizedHandler? onUnauthorized;

  static Dio _build(String baseUrl) {
    return Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(milliseconds: ApiConfig.timeoutMs),
        receiveTimeout: const Duration(milliseconds: ApiConfig.timeoutMs),
        sendTimeout: const Duration(milliseconds: ApiConfig.timeoutMs),
        contentType: 'application/json',
        // Don't let dio throw on 4xx; we parse the envelope ourselves.
        validateStatus: (s) => s != null && s < 500,
        headers: {'Accept': 'application/json'},
      ),
    );
  }

  Interceptor _bearerInterceptor() {
    return InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _tokens.accessToken;
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    );
  }

  // ---- AUTH ----

  /// POST /auth/login → 200 stores tokens+user, 401 throws unauthorized.
  Future<AuthSession> login(String email, String password) async {
    try {
      final res = await _auth.post(
        ApiConfig.loginPath,
        data: {'email': email, 'password': password},
      );
      _ensureOk(res);
      final data = res.data;
      if (data is! Map<String, dynamic>) {
        throw ApiException(message: 'Unexpected response from the server.');
      }
      return AuthSession.fromJson(data);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// GET /drivers (AUTH, authed) → the active drivers in the operator's own
  /// company as `[{ id, name, email }]`. Company scope is server-derived from
  /// the JWT; this client never sends a company filter. Used to populate the
  /// assign-driver picker.
  Future<List<Driver>> fetchDrivers() async {
    try {
      final res = await _auth.get(ApiConfig.driversPath);
      _ensureOk(res);
      final list = _asList(res.data);
      return list
          .whereType<Map<String, dynamic>>()
          .map(Driver.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  // ---- ADMIN / COMPANY HIERARCHY (AUTH, authed) ----
  // Re-platforms src/pages/admin/*. All company scoping is server-derived from
  // the JWT: admin sees all, manager sees only its own company.

  /// GET /api/companies → admin: all; manager: own (1-element list).
  Future<List<Company>> fetchCompanies() async {
    try {
      final res = await _auth.get(ApiConfig.companiesPath);
      _ensureOk(res);
      return _asList(res.data)
          .whereType<Map<String, dynamic>>()
          .map(Company.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// POST /api/companies (ADMIN only) → 201 the created company.
  Future<Company> createCompany(CreateCompanyInput input) async {
    try {
      final res = await _auth.post(
        ApiConfig.companiesPath,
        data: input.toJson(),
      );
      _ensureOk(res);
      final data = res.data;
      if (data is! Map<String, dynamic>) {
        throw ApiException(message: 'Unexpected response from the server.');
      }
      return Company.fromJson(data);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// GET /api/companies/{id} → the company overview (admin any; manager own).
  Future<Company> fetchCompany(String id) async {
    try {
      final res = await _auth.get(ApiConfig.companyPath(id));
      _ensureOk(res);
      final data = res.data;
      if (data is! Map<String, dynamic>) {
        throw ApiException(message: 'Unexpected response from the server.');
      }
      return Company.fromJson(data);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// GET /api/companies/{id}/locations.
  Future<List<AdminLocation>> fetchCompanyLocations(String companyId) async {
    try {
      final res = await _auth.get(ApiConfig.companyLocationsPath(companyId));
      _ensureOk(res);
      return _asList(res.data)
          .whereType<Map<String, dynamic>>()
          .map(AdminLocation.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// POST /api/companies/{id}/locations → 201 the created location.
  Future<AdminLocation> createLocation(
    String companyId,
    CreateLocationInput input,
  ) async {
    try {
      final res = await _auth.post(
        ApiConfig.companyLocationsPath(companyId),
        data: input.toJson(),
      );
      _ensureOk(res);
      final data = res.data;
      if (data is! Map<String, dynamic>) {
        throw ApiException(message: 'Unexpected response from the server.');
      }
      return AdminLocation.fromJson(data);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// PUT /api/locations/{id} → 200 the edited location.
  Future<AdminLocation> updateLocation(
    String locationId,
    CreateLocationInput input,
  ) async {
    try {
      final res = await _auth.put(
        ApiConfig.locationPath(locationId),
        data: input.toJson(),
      );
      _ensureOk(res);
      final data = res.data;
      if (data is! Map<String, dynamic>) {
        throw ApiException(message: 'Unexpected response from the server.');
      }
      return AdminLocation.fromJson(data);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  // ---- CONTRACTS (company panel → Contracts tab) ----

  /// GET /api/companies/{id}/contracts → contracts for a company, newest first.
  Future<List<Contract>> fetchContracts(String companyId) async {
    try {
      final res = await _auth.get(ApiConfig.companyContractsPath(companyId));
      _ensureOk(res);
      return _asList(res.data)
          .whereType<Map<String, dynamic>>()
          .map(Contract.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// POST /api/companies/{id}/contracts → create a contract.
  Future<Contract> createContract(
      String companyId, CreateContractInput input) async {
    try {
      final res = await _auth.post(
        ApiConfig.companyContractsPath(companyId),
        data: input.toJson(),
      );
      _ensureOk(res);
      final data = res.data;
      if (data is! Map<String, dynamic>) {
        throw ApiException(message: 'Unexpected response from the server.');
      }
      return Contract.fromJson(data);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  // ---- USER LIFECYCLE (activate / deactivate / delete) ----

  /// PUT /api/users/{id}/active → toggle a staff user's active flag.
  Future<AdminUser> setUserActive(String userId, bool active) async {
    try {
      final res = await _auth.put(
        ApiConfig.userActivePath(userId),
        data: {'active': active},
      );
      _ensureOk(res);
      final data = res.data;
      if (data is! Map<String, dynamic>) {
        throw ApiException(message: 'Unexpected response from the server.');
      }
      return AdminUser.fromJson(data);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// DELETE /api/users/{id} → delete a staff (valet/driver) account.
  Future<void> deleteUser(String userId) async {
    try {
      final res = await _auth.delete(ApiConfig.userPath(userId));
      _ensureOk(res);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  // ---- KEY SLOTS (Location Detail → Key Slots tab) ----

  /// GET /api/locations/{id}/slots → custom key slots for a location.
  Future<List<KeySlot>> fetchSlots(String locationId) async {
    try {
      final res = await _auth.get(ApiConfig.locationSlotsPath(locationId));
      _ensureOk(res);
      return _asList(res.data)
          .whereType<Map<String, dynamic>>()
          .map(KeySlot.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// POST /api/locations/{id}/slots/bulk → generate `<prefix><startFrom+i>`
  /// slots. Returns the created slots.
  Future<List<KeySlot>> bulkGenerateSlots(
    String locationId, {
    required String prefix,
    required int count,
    required int startFrom,
  }) async {
    try {
      final res = await _auth.post(
        ApiConfig.locationSlotsBulkPath(locationId),
        data: {'prefix': prefix, 'count': count, 'startFrom': startFrom},
      );
      _ensureOk(res);
      return _asList(res.data)
          .whereType<Map<String, dynamic>>()
          .map(KeySlot.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// PUT /api/slots/{id} → rename a slot.
  Future<KeySlot> renameSlot(String slotId, String slotName) async {
    try {
      final res = await _auth.put(
        ApiConfig.slotPath(slotId),
        data: {'slotName': slotName},
      );
      _ensureOk(res);
      final data = res.data;
      if (data is! Map<String, dynamic>) {
        throw ApiException(message: 'Unexpected response from the server.');
      }
      return KeySlot.fromJson(data);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// DELETE /api/slots/{id} → remove a slot.
  Future<void> deleteSlot(String slotId) async {
    try {
      final res = await _auth.delete(ApiConfig.slotPath(slotId));
      _ensureOk(res);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// GET /api/companies/{id}/users?role= → people in the company. `role` filters
  /// by DB role (`valet`=operators, `driver`=drivers, `manager`=owners).
  Future<List<AdminUser>> fetchCompanyUsers(
    String companyId, {
    String? role,
  }) async {
    try {
      final res =
          await _auth.get(ApiConfig.companyUsersPath(companyId, role: role));
      _ensureOk(res);
      return _asList(res.data)
          .whereType<Map<String, dynamic>>()
          .map(AdminUser.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// POST /api/companies/{id}/staff → 201 the created staff user (valet|driver).
  Future<AdminUser> createStaff(
    String companyId,
    CreateStaffInput input,
  ) async {
    try {
      final res = await _auth.post(
        ApiConfig.companyStaffPath(companyId),
        data: input.toJson(),
      );
      _ensureOk(res);
      final data = res.data;
      if (data is! Map<String, dynamic>) {
        throw ApiException(message: 'Unexpected response from the server.');
      }
      return AdminUser.fromJson(data);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// GET /api/admin/locations (ADMIN only) → all locations across companies.
  Future<List<AdminLocation>> fetchAllLocations() async {
    try {
      final res = await _auth.get(ApiConfig.adminLocationsPath);
      _ensureOk(res);
      return _asList(res.data)
          .whereType<Map<String, dynamic>>()
          .map(AdminLocation.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// GET /api/admin/users (ADMIN only) → every user for the hierarchy view.
  Future<List<AdminUser>> fetchAllUsers() async {
    try {
      final res = await _auth.get(ApiConfig.adminUsersPath);
      _ensureOk(res);
      return _asList(res.data)
          .whereType<Map<String, dynamic>>()
          .map(AdminUser.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  // ---- CORE (authed) ----

  /// GET /api/driver/assignments
  Future<List<Assignment>> fetchAssignments() async {
    try {
      final res = await _core.get(ApiConfig.assignmentsPath);
      _ensureOk(res);
      final data = res.data;
      final list = _asList(data);
      return list
          .whereType<Map<String, dynamic>>()
          .map(Assignment.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Advance one assignment by the given action. Returns the updated status.
  Future<LifecycleStatus> advance(String txId, DriverAction action) async {
    final path = switch (action) {
      DriverAction.confirmParked => ApiConfig.parkedPath(txId),
      DriverAction.enRoute => ApiConfig.enRoutePath(txId),
      DriverAction.arrived => ApiConfig.arrivedPath(txId),
      DriverAction.deliver => ApiConfig.deliveredPath(txId),
    };
    try {
      final res = await _core.post(path);
      _ensureOk(res);
      // Prefer the server-reported status; fall back to the action's target.
      final data = res.data;
      if (data is Map && data['status'] != null) {
        return LifecycleStatus.fromWire(data['status'].toString());
      }
      return action.to;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  // ---- OPERATOR (authed) ----

  /// GET /api/operator/transactions → active floor feed, newest first.
  Future<List<Transaction>> fetchTransactions() async {
    try {
      final res = await _core.get(ApiConfig.operatorTransactionsPath);
      _ensureOk(res);
      final list = _asList(res.data);
      return list
          .whereType<Map<String, dynamic>>()
          .map(Transaction.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// GET /api/operator/transactions/history → full company history (every
  /// status, newest first). Powers the company panel Dashboard / Transactions /
  /// Analytics tabs.
  Future<List<Transaction>> fetchTransactionHistory() async {
    try {
      final res = await _core.get(ApiConfig.operatorHistoryPath);
      _ensureOk(res);
      return _asList(res.data)
          .whereType<Map<String, dynamic>>()
          .map(Transaction.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// POST /api/operator/transactions → 201 with the created transaction.
  Future<Transaction> createTransaction(CreateTransactionInput input) async {
    try {
      final res = await _core.post(
        ApiConfig.operatorTransactionsPath,
        data: input.toJson(),
      );
      _ensureOk(res);
      final data = res.data;
      if (data is! Map<String, dynamic>) {
        throw ApiException(message: 'Unexpected response from the server.');
      }
      return Transaction.fromJson(data);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// POST one of the operator lifecycle transitions for [txId]. `assign`
  /// carries a `{ driverId }` body; the rest are bodyless.
  Future<void> operatorAction(
    String txId,
    OperatorAction action, {
    String? driverId,
  }) async {
    final path = switch (action) {
      OperatorAction.assignPark => ApiConfig.operatorAssignParkPath(txId),
      OperatorAction.park => ApiConfig.operatorParkPath(txId),
      OperatorAction.keyIn => ApiConfig.operatorKeyInPath(txId),
      OperatorAction.request => ApiConfig.operatorRequestPath(txId),
      OperatorAction.assign => ApiConfig.operatorAssignPath(txId),
      OperatorAction.cancel => ApiConfig.operatorCancelPath(txId),
    };
    // Both assignment actions carry the chosen driver in the body.
    final carriesDriver =
        action == OperatorAction.assign || action == OperatorAction.assignPark;
    try {
      final res = await _core.post(
        path,
        data: carriesDriver ? {'driverId': driverId} : null,
      );
      _ensureOk(res);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Throws (and triggers the 401 bounce) for non-2xx responses that slipped
  /// past dio's validateStatus (since we accept <500).
  void _ensureOk(Response res) {
    final code = res.statusCode ?? 0;
    if (code >= 200 && code < 300) return;
    if (code == 401) {
      onUnauthorized?.call();
      throw ApiException(
        message: ApiException.fromDioData(res.data) ??
            'Your session has expired. Please sign in again.',
        statusCode: 401,
        isUnauthorized: true,
      );
    }
    throw ApiException(
      message: ApiException.fromDioData(res.data) ??
          'Something went wrong (${res.statusCode}). Please try again.',
      statusCode: res.statusCode,
    );
  }

  static List<dynamic> _asList(Object? data) {
    if (data is List) return data;
    if (data is Map) {
      // Tolerate a wrapped { data: [...] } or { assignments: [...] } envelope.
      final inner = data['data'] ?? data['assignments'] ?? data['items'];
      if (inner is List) return inner;
    }
    return const [];
  }
}
