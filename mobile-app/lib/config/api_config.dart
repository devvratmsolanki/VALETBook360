/// API endpoint configuration for the Vālet driver app.
///
/// Two independent backends run in parallel against a fixed contract:
///   - AUTH service  → login / refresh / password   (default port 8081)
///   - CORE service  → driver assignments + lifecycle (default port 8082)
///
/// ## Pointing the app at a backend
///
/// Defaults below target the **Android emulator**, where `10.0.2.2` is the host
/// machine's loopback. Override per environment without editing code:
///
/// ```sh
/// # Android emulator (default — no flags needed)
/// flutter run
///
/// # iOS simulator / desktop / web  → host loopback is 127.0.0.1
/// flutter run \
///   --dart-define=AUTH_BASE_URL=http://127.0.0.1:8081 \
///   --dart-define=CORE_BASE_URL=http://127.0.0.1:8082
///
/// # Physical device on the same LAN  → your machine's IP
/// flutter run \
///   --dart-define=AUTH_BASE_URL=http://192.168.1.20:8081 \
///   --dart-define=CORE_BASE_URL=http://192.168.1.20:8082
///
/// # Remote / staging
/// flutter run \
///   --dart-define=AUTH_BASE_URL=https://auth.staging.valet.app \
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
}
