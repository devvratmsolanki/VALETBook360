/// API endpoint configuration for the Vālet driver app.
///
/// Two independent backends run in parallel against a fixed contract:
///   - AUTH service  → login / refresh / password   (default port 8081)
///   - CORE service  → driver assignments + lifecycle (default port 8082)
///
/// ## Pointing the app at a backend
///
/// The local stack (infra/docker-compose.yml) publishes the services on the host
/// ports chosen in infra/.env — by default AUTH=8091, CORE=8092, GATEWAY=8090
/// (NOT 8081/8082; those are the in-container ports). The defaults below target
/// the **Android emulator** (`10.0.2.2` = host loopback). For every other target,
/// pass a committed config file instead of hand-typing flags:
///
/// ```sh
/// # Android emulator (default — no flags needed; uses 10.0.2.2)
/// flutter run
///
/// # Web / desktop / iOS-sim against the local stack (127.0.0.1:809x)
/// flutter run -d chrome --dart-define-from-file=config/local.json
///
/// # Physical device on the same Wi-Fi: copy config/lan.example.json →
/// # config/lan.json, set your LAN IP, then:
/// flutter run -d chrome --web-hostname 0.0.0.0 \
///   --dart-define-from-file=config/lan.json
///
/// # Remote / staging: a config/staging.json with https URLs, or per-define:
/// flutter run --dart-define=AUTH_BASE_URL=https://auth.staging.valet.app \
///   --dart-define=CORE_BASE_URL=https://core.staging.valet.app
/// ```
class ApiConfig {
  const ApiConfig._();

  /// Android emulator → host loopback. For iOS sim / desktop / web use
  /// `http://127.0.0.1:8081` (or `http://localhost:8081`).
  static const String authBaseUrl = String.fromEnvironment(
    'AUTH_BASE_URL',
    defaultValue: 'http://10.0.2.2:8081',
  );

  /// Android emulator → host loopback. For iOS sim / desktop / web use
  /// `http://127.0.0.1:8082` (or `http://localhost:8082`).
  static const String coreBaseUrl = String.fromEnvironment(
    'CORE_BASE_URL',
    defaultValue: 'http://10.0.2.2:8082',
  );

  /// Socket.IO realtime gateway. Default port 8090. Android emulator → host
  /// loopback; for iOS sim / desktop / web use `http://127.0.0.1:8090`.
  /// Override with --dart-define=REALTIME_URL=...
  static const String realtimeUrl = String.fromEnvironment(
    'REALTIME_URL',
    defaultValue: 'http://10.0.2.2:8090',
  );

  /// Network call timeout. Override with --dart-define=API_TIMEOUT_MS=...
  static const int timeoutMs = int.fromEnvironment(
    'API_TIMEOUT_MS',
    defaultValue: 20000,
  );

  // ---- Contract paths (fixed; shared with the backend agents) ----
  static const String loginPath = '/auth/login';

  /// Exchanges a refresh token for a fresh access+refresh+user (same 200 shape
  /// as [loginPath]). Driven by the 401 auto-refresh interceptor.
  static const String refreshPath = '/auth/refresh';

  /// Returns the current [AuthUser] for the bearer token; 401/403 if the token
  /// is invalid or the account is inactive. Used to verify a restored session.
  static const String mePath = '/auth/me';

  /// In-app help assistant (Claude) — POST {messages:[{role,content}]} → {reply}.
  static const String assistantChatPath = '/assistant/chat';

  /// Tenant-scoped driver directory for the operator's assign picker. Served by
  /// the AUTH service (drivers are users) and authed with the operator's bearer
  /// token; the company scope is derived server-side from the JWT.
  static const String driversPath = '/drivers';

  static const String assignmentsPath = '/api/driver/assignments';

  /// Lifecycle transition endpoints, keyed by the action verb.
  ///   driver_assigned → en-route, en_route → arrived, arrived → delivered
  static String enRoutePath(String txId) =>
      '/api/driver/transactions/$txId/en-route';
  static String arrivedPath(String txId) =>
      '/api/driver/transactions/$txId/arrived';
  static String deliveredPath(String txId) =>
      '/api/driver/transactions/$txId/delivered';
  /// Intake side: the assigned park driver confirms the car is parked
  /// (waiting_for_driver → parked).
  static String parkedPath(String txId) =>
      '/api/driver/transactions/$txId/parked';

  // ---- Operator (valet/manager/admin) endpoints, base CORE ----
  static const String operatorTransactionsPath = '/api/operator/transactions';

  /// Effective key-slot pool for the operator's own location (AUTH service,
  /// authed). Returns `{ locationId, keyCapacity, slots }`.
  static const String operatorKeySlotsPath = '/key-slots';
  /// Company-wide transaction history (all statuses) for the company panel.
  static const String operatorHistoryPath =
      '/api/operator/transactions/history';
  static String operatorParkPath(String txId) =>
      '/api/operator/transactions/$txId/park';
  static String operatorKeyInPath(String txId) =>
      '/api/operator/transactions/$txId/key-in';
  static String operatorRequestPath(String txId) =>
      '/api/operator/transactions/$txId/request';
  static String operatorAssignPath(String txId) =>
      '/api/operator/transactions/$txId/assign';
  /// Intake: assign a driver to PARK the incoming car.
  static String operatorAssignParkPath(String txId) =>
      '/api/operator/transactions/$txId/assign-park';
  static String operatorCancelPath(String txId) =>
      '/api/operator/transactions/$txId/cancel';

  // ---- Admin / company hierarchy (AUTH service, authed) ----
  // Re-platforms src/pages/admin/* against the live auth-service contract.
  // admin sees all companies; manager sees only their own (server-scoped).
  static const String companiesPath = '/api/companies';
  static String companyPath(String id) => '/api/companies/$id';

  /// Contracts (company panel → Contracts tab).
  static String companyContractsPath(String companyId) =>
      '/api/companies/$companyId/contracts';

  /// User lifecycle (activate/deactivate, delete) — company panel.
  static String userActivePath(String userId) => '/api/users/$userId/active';
  static String userPath(String userId) => '/api/users/$userId';

  /// Key slots (Location Detail → Key Slots tab), served by the AUTH service.
  static String locationSlotsPath(String locationId) =>
      '/api/locations/$locationId/slots';
  static String locationSlotsBulkPath(String locationId) =>
      '/api/locations/$locationId/slots/bulk';
  static String slotPath(String slotId) => '/api/slots/$slotId';
  static String companyLocationsPath(String id) =>
      '/api/companies/$id/locations';
  static String locationPath(String id) => '/api/locations/$id';
  static String companyUsersPath(String id, {String? role}) =>
      role == null || role.isEmpty
          ? '/api/companies/$id/users'
          : '/api/companies/$id/users?role=$role';
  static String companyStaffPath(String id) => '/api/companies/$id/staff';

  // Admin-only flat listings for the hierarchy views.
  static const String adminLocationsPath = '/api/admin/locations';
  static const String adminUsersPath = '/api/admin/users';

  // Facility owner self-service.
  static const String facilityOwnerLocationsPath = '/api/facility-owner/locations';
}
