import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/realtime_client.dart';
import '../api/token_store.dart';
import '../models/admin_location.dart';
import '../models/contract.dart';
import '../models/key_slot.dart';
import '../models/operator_key_slots.dart';
import '../models/transaction.dart';
import 'admin_locations_controller.dart';
import 'admin_users_controller.dart';
import 'auth_controller.dart';
import 'companies_controller.dart';
import 'company_detail_controller.dart';
import 'package:flutter/material.dart';
import 'drivers_controller.dart';
import 'floor_controller.dart';
import 'missions_controller.dart';
import 'theme_controller.dart';

/// Secure token store singleton.
final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

/// Persisted theme preference store.
final themeStoreProvider = Provider<ThemeStore>((ref) => ThemeStore());

/// App theme mode (light / dark / system), restored from secure storage on
/// boot. The root ConsumerWidget watches this to drive MaterialApp.themeMode
/// AND to flip VColors.setBrightness before each build.
final themeControllerProvider =
    StateNotifierProvider<ThemeController, ThemeMode>((ref) {
  return ThemeController(ref.watch(themeStoreProvider));
});

/// Typed API client. The 401 → bounce-to-login wiring is attached by the auth
/// controller after it constructs (avoids a provider dependency cycle).
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref.watch(tokenStoreProvider));
});

/// Socket.IO realtime gateway client (single instance for the app).
final realtimeClientProvider = Provider<RealtimeClient>((ref) {
  final client = RealtimeClient();
  // On auto-reconnect the socket re-reads the freshest token from the store so a
  // token refreshed while it was down doesn't replay on a stale credential.
  client.currentToken = () => ref.read(tokenStoreProvider).accessToken;
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
  final api = ref.watch(apiClientProvider);
  final auth = ref.watch(authControllerProvider);

  // BUG-13: when the HTTP client silently refreshes the access token, the auth
  // STATUS doesn't change (still authenticated), so this provider wouldn't
  // otherwise re-run. Reconnect the socket on the fresh token explicitly — the
  // connect() equality guard sees a new token and rebuilds with it.
  api.onTokenRefreshed = (token) {
    if (auth.isAuthed && token.isNotEmpty) realtime.connect(token);
  };

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

/// Effective key-slot pool for the operator's own location, powering the
/// "New car" key-slot grid picker. `ref.invalidate(operatorKeySlotsProvider)`
/// re-pulls (rarely needed — the pool is static; occupancy is computed live
/// from [floorControllerProvider]). autoDispose so it refetches per sheet open.
final operatorKeySlotsProvider =
    FutureProvider.autoDispose<OperatorKeySlots>((ref) async {
  return ref.watch(apiClientProvider).fetchOperatorKeySlots();
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

/// Per-company rollup counts for the super-admin hierarchical dashboard:
/// locations, operators (DB role `valet`), and drivers per company. One pair of
/// admin fetches (all locations + all users), grouped client-side — no
/// per-company round trips. Keyed by company id.
///
/// ponytail: counts only — a live active-car badge per company would need a
/// cross-tenant admin transactions endpoint (none exists; OperatorController is
/// JWT-companyId scoped). Add that endpoint if live counts are wanted.
typedef CompanyRollup = ({int locations, int operators, int drivers});

final companyRollupsProvider =
    FutureProvider.autoDispose<Map<String, CompanyRollup>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final (locs, users) = await (api.fetchAllLocations(), api.fetchAllUsers()).wait;
  final loc = <String, int>{};
  for (final l in locs) {
    loc[l.companyId] = (loc[l.companyId] ?? 0) + 1;
  }
  final op = <String, int>{};
  final drv = <String, int>{};
  for (final u in users) {
    final cid = u.companyId;
    if (cid == null) continue;
    if (u.role == 'driver') {
      drv[cid] = (drv[cid] ?? 0) + 1;
    } else if (u.role == 'valet') {
      op[cid] = (op[cid] ?? 0) + 1;
    }
  }
  return {
    for (final id in {...loc.keys, ...op.keys, ...drv.keys})
      id: (
        locations: loc[id] ?? 0,
        operators: op[id] ?? 0,
        drivers: drv[id] ?? 0,
      ),
  };
});

/// Chatbot FAB bottom offset — screens with a NavigationBar set this to
/// navBar + FAB height + margins so the chatbot clears the FAB above the bar.
final chatbotBottomOffsetProvider = StateProvider<double>((ref) => 88.0);

/// Locations visible to the calling facility owner (their own panel).
/// autoDispose so it refetches when the panel is reopened.
final facilityOwnerLocationsProvider =
    FutureProvider.autoDispose<List<AdminLocation>>((ref) async {
  return ref.watch(apiClientProvider).fetchFacilityOwnerLocations();
});

/// Active (non-terminal) transactions at the facility owner's location.
final facilityOwnerTransactionsProvider =
    FutureProvider.autoDispose<List<Transaction>>((ref) async {
  return ref.watch(apiClientProvider).fetchFacilityOwnerTransactions();
});

/// Full transaction history for the facility owner's location (newest 200).
final facilityOwnerHistoryProvider =
    FutureProvider.autoDispose<List<Transaction>>((ref) async {
  return ref.watch(apiClientProvider).fetchFacilityOwnerTransactionHistory();
});
