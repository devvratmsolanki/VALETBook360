import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/company.dart';
import '../state/companies_controller.dart';
import '../state/providers.dart';
import '../theme/v_colors.dart';
import '../theme/v_theme.dart';
import '../theme/v_tokens.dart';
import '../widgets/v_states.dart';
import 'admin_company_create_screen.dart';
import 'admin_company_detail_screen.dart';

/// Companies list pane — re-platforms `Companies.jsx`. One card per company,
/// tappable into the detail drill-down. A "+ New company" FAB opens the create
/// sheet (ADMIN only). admin sees all companies; manager (handled elsewhere)
/// never reaches this pane.
class AdminCompaniesPane extends ConsumerWidget {
  const AdminCompaniesPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(companiesControllerProvider);
    final notifier = ref.read(companiesControllerProvider.notifier);

    return Scaffold(
      backgroundColor: VColors.surface950,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-company',
        backgroundColor: VColors.brand500,
        foregroundColor: VColors.contentOnAccent,
        icon: const Icon(Icons.add_rounded),
        label: Text('New company',
            style: VType.label.copyWith(color: VColors.contentOnAccent)),
        onPressed: () => _create(context),
      ),
      body: _body(context, state, notifier),
    );
  }

  Future<void> _create(BuildContext context) async {
    final name = await AdminCompanyCreateSheet.show(context);
    if (name != null && context.mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: VColors.surface700,
          content: Text('Created · $name',
              style: VType.body.copyWith(color: VColors.contentStrong)),
        ));
    }
  }

  Widget _body(
    BuildContext context,
    CompaniesState state,
    CompaniesController notifier,
  ) {
    switch (state.status) {
      case CompaniesStatus.loading:
        return Center(
          child: CircularProgressIndicator(color: VColors.brand400),
        );
      case CompaniesStatus.error:
        return Padding(
          padding: const EdgeInsets.all(VSpace.x4),
          child: Center(
            child: VBanner(
              message: state.error ?? 'Something went wrong.',
              onRetry: notifier.load,
            ),
          ),
        );
      case CompaniesStatus.empty:
        return RefreshIndicator(
          color: VColors.brand400,
          backgroundColor: VColors.surface800,
          onRefresh: notifier.load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 120),
              VEmptyState(
                icon: Icons.business_outlined,
                headline: 'No companies yet',
                hint: 'Tap “New company” to provision the first one.',
              ),
            ],
          ),
        );
      case CompaniesStatus.ready:
        return RefreshIndicator(
          color: VColors.brand400,
          backgroundColor: VColors.surface800,
          onRefresh: notifier.load,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
                VSpace.x4, VSpace.x4, VSpace.x4, 96),
            itemCount: state.companies.length,
            separatorBuilder: (_, __) => const SizedBox(height: VSpace.x3),
            itemBuilder: (_, i) => _CompanyCard(company: state.companies[i]),
          ),
        );
    }
  }
}

class _CompanyCard extends StatelessWidget {
  const _CompanyCard({required this.company});
  final Company company;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: VColors.surface900,
      borderRadius: BorderRadius.circular(VRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(VRadius.lg),
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  AdminCompanyDetailScreen(companyId: company.id),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(VSpace.x4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(VRadius.lg),
            border: Border.all(color: VColors.surface700, width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: VColors.brand900,
                  borderRadius: BorderRadius.circular(VRadius.md),
                ),
                child: Icon(Icons.business_rounded,
                    color: VColors.brand300),
              ),
              const SizedBox(width: VSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(company.displayName,
                        style: VType.bodyLg
                            .copyWith(color: VColors.contentStrong),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: VSpace.x1),
                    Text(
                      company.ownerName ?? company.email ?? '—',
                      style: VType.caption,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: VColors.contentMuted),
            ],
          ),
        ),
      ),
    );
  }
}
