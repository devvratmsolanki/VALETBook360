import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'screens/admin_home_screen.dart';
import 'screens/company_home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/mission_stack_screen.dart';
import 'screens/operator_floor_screen.dart';
import 'state/auth_controller.dart';
import 'state/providers.dart';

/// go_router with a role-aware auth redirect (replaces ProtectedRoute/AuthGate).
/// Drivers land on `/driver`; operators (valet) land on `/operator`; admin +
/// manager (the company hierarchy panel) land on `/admin`. A user hitting the
/// wrong home is bounced to their own.
final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthRouterNotifier(ref);

  return GoRouter(
    initialLocation: '/driver',
    refreshListenable: notifier,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);

      // Don't redirect until the stored session has been resolved.
      if (auth.status == AuthStatus.unknown) return null;

      final loggingIn = state.matchedLocation == '/login';
      if (!auth.isAuthed) return loggingIn ? null : '/login';

      // Authenticated: route by role.
      final home = auth.user!.homeRoute;
      if (loggingIn) return home;

      final loc = state.matchedLocation;
      // Keep each role on its own home; bounce cross-role navigation.
      if (loc == '/driver' && !auth.user!.isDriver) return home;
      if (loc == '/operator' && !auth.user!.isOperator) return home;
      if (loc == '/admin' && !auth.user!.isAdmin) return home;
      if (loc == '/company' && !auth.user!.isManager) return home;
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/driver',
        builder: (context, state) => const MissionStackScreen(),
      ),
      GoRoute(
        path: '/operator',
        builder: (context, state) => const OperatorFloorScreen(),
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminHomeScreen(),
      ),
      GoRoute(
        path: '/company',
        builder: (context, state) => const CompanyHomeScreen(),
      ),
    ],
  );
});

/// Bridges Riverpod auth state → go_router's Listenable so redirects re-run on
/// sign-in / sign-out / 401 expiry.
class _AuthRouterNotifier extends ChangeNotifier {
  _AuthRouterNotifier(this._ref) {
    _ref.listen<AuthState>(authControllerProvider, (prev, next) {
      if (prev?.status != next.status) notifyListeners();
    });
  }
  final Ref _ref;
}
