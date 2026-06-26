import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/realtime_client.dart';
import '../api/token_store.dart';
import '../models/contract.dart';
import '../models/key_slot.dart';
import '../models/transaction.dart';
import 'admin_locations_controller.dart';
import 'admin_users_controller.dart';
import 'auth_controller.dart';
import 'companies_controller.dart';
import 'company_detail_controller.dart';
import 'drivers_controller.dart';
import 'floor_controller.dart';
import 'missions_controller.dart';

/// Secure token store singleton.
final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

/// Typed API client. The 401 → bounce-to-login wiring is attached by the auth
/// controller after it constructs (avoids a provider dependency cycle).
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref.watch(tokenStoreProvider));
});

/// Socket.IO realtime gateway client (single instance for the app).
final realtimeClientProvider = Provider<RealtimeClient>((ref) {
  final client = RealtimeClient();
  ref.onDispose(client.dispose);
  return client;
});

/// Auth state — drives the router redirect. On construction it registers its
/// `onExpired` handler with the client so any 401 bounces to login.
final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  final client = ref.watch(apiClientProvider);
  final controller = AuthController(
    client: client,
    tokens: ref.watch(tokenStoreProvider),
  );
  client.onUnauthorized = () {
    // Defer so we don't mutate state mid-request.
    Future.microtask(controller.onExpired);
  };
  return controller;
});

/// Connects / disconnects the realtime socket as auth state flips. Watched once
/// at the app shell so the socket follows the session (connect on auth with the
/// stored access token, disconnect on logout / expiry).
final realtimeConnectorProvider = Provider<void>((ref) {
  final realtime = ref.watch(realtimeClientProvider);
  final tokens = ref.watch(tokenStoreProvider);
  final auth = ref.watch(authControllerProvider);

  if (auth.isAuthed) {
    // Pull the freshest token from secure storage and (re)connect.
    tokens.accessToken.then((token) {
      if (token != null && token.isNotEmpty) realtime.connect(token);
    });
  } else {
    realtime.disconnect();
  }
});

/// Driver missions state. Realtime is layered on top of the existing poll.
///
/// autoDispose so the controller is torn down when the driver screen unmounts
/// (e.g. on redirect to /login before auth is resolved). When the user logs in
/// and the screen remounts, a fresh controller is created and load() fires with
/// a valid token — preventing the permanent loading-skeleton caused by the
/// unauthenticated 401 that fires during the auth-resolution window on boot.
final missionsControllerProvider =
    StateNotifierProvider.autoDispose<MissionsController, MissionsState>((ref) {
  return MissionsController(
    client: ref.watch(apiClientProvider),
    realtime: ref.watch(realtimeClientProvider),
  );
});

/// Operator floor state. Loads the active feed and applies realtime deltas live.
///
/// autoDispose for the same reason as [missionsControllerProvider]: prevents a
/// permanent loading state if the operator screen is pre-rendered before auth
/// resolves (e.g. on a future initialLocation change) and gets a 401.
final floorControllerProvider =
    StateNotifierProvider.autoDispose<FloorController, FloorState>((ref) {
  return FloorController(
    client: ref.watch(apiClientProvider),
    realtime: ref.watch(realtimeClientProvider),
  );
});

/// Company-scoped driver directory for the operator's assign-driver picker.
final driversControllerProvider =
    StateNotifierProvider<DriversController, DriversState>((ref) {
  return DriversController(client: ref.watch(apiClientProvider));
});

// ---- Admin / company hierarchy (re-platforms src/pages/admin/*) ----

/// Companies list. admin → all; manager → own (server-scoped 1-element list).
final companiesControllerProvider =
    StateNotifierProvider<CompaniesController, CompaniesState>((ref) {
  return CompaniesController(client: ref.watch(apiClientProvider));
});

/// One company's drill-down (overview + locations + operators + drivers),
/// keyed by company id so each detail screen owns its own controller instance.
final companyDetailControllerProvider = StateNotifierProvider.family<
    CompanyDetailController, CompanyDetailState, String>((ref, companyId) {
  return CompanyDetailController(
    client: ref.watch(apiClientProvider),
    companyId: companyId,
  );
});

/// Full company transaction history (every status, newest first) — powers the
/// company panel Dashboard, Transactions, and Analytics tabs. autoDispose so it
/// refetches when the panel is reopened; `ref.refresh` re-pulls on demand.
final companyHistoryProvider =
    FutureProvider.autoDispose<List<Transaction>>((ref) async {
  return ref.watch(apiClientProvider).fetchTransactionHistory();
});

/// Custom key slots for one location (Location Detail → Key Slots tab), keyed by
/// location id. `ref.invalidate(locationSlotsProvider(id))` re-pulls after a
/// bulk-generate / rename / delete.
final locationSlotsProvider = FutureProvider.autoDispose
    .family<List<KeySlot>, String>((ref, locationId) async {
  return ref.watch(apiClientProvider).fetchSlots(locationId);
});

/// Contracts for one company (company panel → Contracts tab), keyed by company
/// id. `ref.invalidate(companyContractsProvider(id))` re-pulls after a create.
final companyContractsProvider = FutureProvider.autoDispose
    .family<List<Contract>, String>((ref, companyId) async {
  return ref.watch(apiClientProvider).fetchContracts(companyId);
});

/// All locations across every company (ADMIN only).
final adminLocationsControllerProvider =
    StateNotifierProvider<AdminLocationsController, AdminLocationsState>((ref) {
  return AdminLocationsController(client: ref.watch(apiClientProvider));
});

/// Every user, for the admin hierarchy (ADMIN only).
final adminUsersControllerProvider =
    StateNotifierProvider<AdminUsersController, AdminUsersState>((ref) {
  return AdminUsersController(client: ref.watch(apiClientProvider));
});
