import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/providers.dart';
import '../theme/v_colors.dart';
import '../theme/v_theme.dart';
import '../theme/v_tokens.dart';
import 'admin_company_detail_screen.dart';
import 'admin_companies_pane.dart';
import 'admin_locations_pane.dart';
import 'admin_users_pane.dart';

/// Admin / company hierarchy shell — re-platforms the super-admin drilldown
/// from `src/pages/admin/*` + CLAUDE.md "Admin hierarchical drilldown".
///
/// A super admin gets a three-section bottom nav (Companies / Locations /
/// Users). A manager (DB `manager`, UI "company") is scoped to one company by
/// the backend, so we land them straight on their own company detail — no
/// cross-company navigation is offered.
class AdminHomeScreen extends ConsumerWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;

    // Manager → straight to their (single) company's detail.
    if (user != null && user.isManager) {
      return _ManagerHome(companyId: user.companyId);
    }
    return const _AdminShell();
  }
}

/// Manager landing: resolve their one company from GET /api/companies (the
/// backend returns only theirs) and render its detail. If the JWT carries a
/// companyId we could use it directly, but resolving via the list keeps a
/// single source of truth and a clean sign-out affordance in the app bar.
class _ManagerHome extends ConsumerWidget {
  const _ManagerHome({required this.companyId});
  final String? companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companies = ref.watch(companiesControllerProvider);

    // Prefer the JWT companyId; otherwise the first (only) company returned.
    final id = (companyId != null && companyId!.isNotEmpty)
        ? companyId
        : (companies.companies.isNotEmpty
            ? companies.companies.first.id
            : null);

    if (id == null) {
      // Still loading the company list, or no company is linked.
      return Scaffold(
        backgroundColor: VColors.surface950,
        appBar: _SignOutAppBar(title: 'My Company', ref: ref),
        body: const Center(
          child: CircularProgressIndicator(color: VColors.brand400),
        ),
      );
    }

    return Stack(
      children: [
        AdminCompanyDetailScreen(companyId: id),
        // Floating sign-out for the manager (the detail screen has no logout).
        Positioned(
          top: MediaQuery.of(context).padding.top + 4,
          right: VSpace.x2,
          child: _LogoutButton(ref: ref),
        ),
      ],
    );
  }
}

/// Super-admin shell with a three-tab bottom nav.
class _AdminShell extends ConsumerStatefulWidget {
  const _AdminShell();

  @override
  ConsumerState<_AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<_AdminShell> {
  int _index = 0;

  static const _titles = ['Companies', 'All Locations', 'All Users'];

  @override
  Widget build(BuildContext context) {
    const panes = [
      AdminCompaniesPane(),
      AdminLocationsPane(),
      AdminUsersPane(),
    ];

    return Scaffold(
      backgroundColor: VColors.surface950,
      appBar: AppBar(
        backgroundColor: VColors.surface950,
        titleSpacing: VSpace.x4,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_titles[_index],
                style: VType.title.copyWith(color: VColors.contentStrong)),
            Text(ref.watch(authControllerProvider).user?.displayName ?? 'Admin',
                style: VType.caption),
          ],
        ),
        actions: [
          _LogoutButton(ref: ref),
          const SizedBox(width: VSpace.x2),
        ],
      ),
      body: SafeArea(
        top: false,
        child: IndexedStack(index: _index, children: panes),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: VColors.surface900,
        indicatorColor: VColors.brand900,
        selectedIndex: _index,
        height: VTarget.navBar,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.business_outlined),
            selectedIcon: Icon(Icons.business_rounded),
            label: 'Companies',
          ),
          NavigationDestination(
            icon: Icon(Icons.place_outlined),
            selectedIcon: Icon(Icons.place_rounded),
            label: 'Locations',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline_rounded),
            selectedIcon: Icon(Icons.people_rounded),
            label: 'Users',
          ),
        ],
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  const _LogoutButton({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Sign out',
      constraints: const BoxConstraints(
        minWidth: VTarget.minTouch,
        minHeight: VTarget.minTouch,
      ),
      icon: const Icon(Icons.logout_rounded, color: VColors.contentMuted),
      onPressed: () => ref.read(authControllerProvider.notifier).logout(),
    );
  }
}

class _SignOutAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _SignOutAppBar({required this.title, required this.ref});
  final String title;
  final WidgetRef ref;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: VColors.surface950,
      title: Text(title, style: VType.title.copyWith(color: VColors.contentStrong)),
      actions: [_LogoutButton(ref: ref), const SizedBox(width: VSpace.x2)],
    );
  }
}
