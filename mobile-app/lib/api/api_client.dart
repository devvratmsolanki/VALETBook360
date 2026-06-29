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
import '../models/operator_key_slots.dart';
import '../models/transaction.dart';
import 'api_exception.dart';
import 'token_store.dart';

/// Signalled when a 401 is seen on an authed call AND the token could not be
/// refreshed, so the app can bounce to login (doc: "401 → bounce to login").
typedef UnauthorizedHandler = void Function();

/// Signalled after a successful silent token refresh, carrying the fresh access
/// token so dependents (e.g. the realtime socket) can re-authenticate.
typedef TokenRefreshedHandler = void Function(String accessToken);

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
    // 401 auto-refresh + retry. Added AFTER the bearer interceptor so the retry
    // (which re-runs the pipeline) picks up the freshly-saved access token.
    _core.interceptors.add(_refreshInterceptor(_core));
    _auth.interceptors.add(_refreshInterceptor(_auth));
  }

  final TokenStore _tokens;
  final Dio _auth;
  final Dio _core;

  /// Set by the app shell; invoked on a 401 only after a refresh attempt has
  /// itself failed (or there was no refresh token) — i.e. a truly dead session.
  UnauthorizedHandler? onUnauthorized;

  /// Set by the app shell; invoked with the new access token after a successful
  /// silent refresh so the realtime socket can re-auth on the fresh credential.
  TokenRefreshedHandler? onTokenRefreshed;

  /// Single-flight guard: while a refresh is in progress this holds the shared
  /// future so a burst of concurrent 401s triggers exactly one /auth/refresh.
  Future<bool>? _refreshing;

  /// Marks a request that has already been retried once post-refresh, so a
  /// second 401 can't loop back into another refresh+retry.
  static const _retriedFlag = '__valet_retried__';

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

  /// On a 401 for an authed call, transparently refresh the token once and
  /// replay the request. login/refresh are exempt (a 401 there is a real auth
  /// failure, not an expiry), and a request that's already been retried is
  /// exempt — together these break the 401 → refresh → 401 loop. Concurrent
  /// 401s share one in-flight refresh (single-flight). Because dio's
  /// validateStatus accepts <500, a 401 arrives as a normal response, so this
  /// runs in onResponse rather than onError.
  Interceptor _refreshInterceptor(Dio dio) {
    return InterceptorsWrapper(
      onResponse: (response, handler) async {
        final req = response.requestOptions;
        final isRetryable = response.statusCode == 401 &&
            !_isAuthEntryPath(req.path) &&
            req.extra[_retriedFlag] != true;
        if (!isRetryable) {
          handler.next(response);
          return;
        }

        final refreshed = await _refreshOnce();
        if (!refreshed) {
          // The refresh itself failed (or no refresh token): the session is
          // dead — bounce to login and let the 401 surface as usual.
          onUnauthorized?.call();
          handler.next(response);
          return;
        }

        // Replay the original request once with the refreshed token (the bearer
        // interceptor re-reads the now-saved access token on this re-run).
        req.extra[_retriedFlag] = true;
        try {
          final retried = await dio.fetch(req);
          handler.resolve(retried);
        } on DioException catch (e) {
          if (e.response != null) {
            handler.resolve(e.response!);
          } else {
            handler.reject(e);
          }
        }
      },
    );
  }

  /// True for the unauthenticated auth entry points (login/refresh), where a 401
  /// must NOT trigger a refresh attempt.
  static bool _isAuthEntryPath(String path) =>
      path.contains(ApiConfig.loginPath) ||
      path.contains(ApiConfig.refreshPath);

  /// Single-flight refresh: the first caller starts it; concurrent callers await
  /// the same future. Resolves true if a fresh session was saved.
  Future<bool> _refreshOnce() {
    return _refreshing ??=
        _performRefresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _performRefresh() async {
    final refreshToken = await _tokens.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) return false;
    try {
      // Bare post (still on the AUTH dio, but the refresh path is exempt from
      // this very interceptor, so it can't recurse). Send both key spellings to
      // tolerate either backend naming.
      final res = await _auth.post(
        ApiConfig.refreshPath,
        data: {'refreshToken': refreshToken, 'refresh_token': refreshToken},
        options: Options(extra: {_retriedFlag: true}),
      );
      final code = res.statusCode ?? 0;
      if (code < 200 || code >= 300) return false;
      final data = res.data;
      if (data is! Map<String, dynamic>) return false;
      final session = AuthSession.fromJson(data);
      if (session.accessToken.isEmpty) return false;
      await _tokens.save(session);
      onTokenRefreshed?.call(session.accessToken);
      return true;
    } catch (_) {
      return false;
    }
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

  /// GET /auth/me (AUTH, authed) → the current [AuthUser]. Throws an
  /// `isUnauthorized` [ApiException] on 401/403 (dead/invalid token). An expired
  /// access token is transparently refreshed by the interceptor first; only a
  /// dead refresh token reaches the caller as a 401.
  Future<AuthUser> me() async {
    try {
      final res = await _auth.get(ApiConfig.mePath);
      _ensureOk(res);
      final data = res.data;
      if (data is! Map<String, dynamic>) {
        throw ApiException(message: 'Unexpected response from the server.');
      }
      return AuthUser.fromJson(data);
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

  /// GET /key-slots (AUTH, authed) → the effective key-slot pool for the
  /// operator's own location as `{ locationId, keyCapacity, slots }`. Location
  /// scope is server-derived from the JWT. `slots` is the ordered pool (custom
  /// names if set, else "1".."keyCapacity") and may be empty.
  Future<OperatorKeySlots> fetchOperatorKeySlots() async {
    try {
      final res = await _auth.get(ApiConfig.operatorKeySlotsPath);
      _ensureOk(res);
      final data = res.data;
      if (data is! Map<String, dynamic>) {
        throw ApiException(message: 'Unexpected response from the server.');
      }
      return OperatorKeySlots.fromJson(data);
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

  /// PUT /api/users/{id} → edit a staff (valet/driver) account's name, role and
  /// location. Returns the updated user.
  Future<AdminUser> updateStaff(String userId, UpdateStaffInput input) async {
    try {
      final res = await _auth.put(
        ApiConfig.userPath(userId),
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

  /// Throws for non-2xx responses that slipped past dio's validateStatus (since
  /// we accept <500). A 401 here means the refresh interceptor already tried (and
  /// failed) to refresh and has fired [onUnauthorized] — so we only translate it
  /// to a typed exception; the bounce is not re-triggered here.
  void _ensureOk(Response res) {
    final code = res.statusCode ?? 0;
    if (code >= 200 && code < 300) return;
    if (code == 401) {
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
