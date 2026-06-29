import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/company.dart';
import '../state/companies_controller.dart';
import '../state/providers.dart';
import '../theme/v_breakpoints.dart';
import '../theme/v_colors.dart';
import '../theme/v_theme.dart';
import '../theme/v_tokens.dart';
import '../widgets/v_adaptive.dart';
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
    Future<void> deleteCompany(Company c) async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: VColors.surface900,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(VRadius.lg),
            side: BorderSide(color: VColors.surface700),
          ),
          title: Text('Delete ${c.displayName}?',
              style: VType.body.copyWith(color: VColors.contentStrong)),
          content: Text(
              'This permanently deletes the company and ALL of its locations, '
              'key slots, contracts, and user accounts. This cannot be undone.',
              style: VType.caption),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel', style: TextStyle(color: VColors.contentMuted)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Delete', style: TextStyle(color: VColors.alertDanger)),
            ),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
      final done = await notifier.delete(c.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(done
              ? 'Company deleted'
              : (notifier.createError ?? 'Could not delete the company')),
          backgroundColor: VColors.surface700,
          behavior: SnackBarBehavior.floating,
        ));
    }

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
            children: [
              SizedBox(
                  height: context.responsive(compact: 80, expanded: 160)),
              const VEmptyState(
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
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
                VSpace.x4, VSpace.x4, VSpace.x4, 96),
            children: [
              VBoundedContent(
                padding: EdgeInsets.zero,
                child: VResponsiveGrid(
                  spacing: VSpace.x3,
                  runSpacing: VSpace.x3,
                  children: [
                    for (final c in state.companies)
                      _CompanyCard(company: c, onDelete: () => deleteCompany(c)),
                  ],
                ),
              ),
            ],
          ),
        );
    }
  }
}

class _CompanyCard extends StatelessWidget {
  const _CompanyCard({required this.company, this.onDelete});
  final Company company;
  final VoidCallback? onDelete;

  String get _initials {
    final name = company.displayName.trim();
    final parts = name.split(RegExp(r'\s+'));
    return parts.isNotEmpty ? parts.first[0].toUpperCase() : 'C';
  }

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
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(VRadius.lg),
            border: Border.all(color: VColors.surface700, width: 1),
          ),
          child: Column(
            children: [
              // ---- Top: icon + name/owner + chevron ----
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    VSpace.x4, VSpace.x4, VSpace.x3, VSpace.x3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: VColors.brand900,
                        borderRadius: BorderRadius.circular(VRadius.md),
                      ),
                      child: Text(_initials,
                          style: VType.label.copyWith(
                              color: VColors.brand300, fontSize: 16)),
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
                          const SizedBox(height: 2),
                          Text(
                            company.ownerName ?? company.email ?? '—',
                            style: VType.caption,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (onDelete != null)
                      IconButton(
                        tooltip: 'Delete company',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.delete_outline_rounded,
                            color: VColors.alertDanger, size: 20),
                        onPressed: onDelete,
                      ),
                    Icon(Icons.chevron_right_rounded,
                        color: VColors.contentMuted, size: 20),
                  ],
                ),
              ),
              // ---- Divider + footer ----
              Divider(height: 1, color: VColors.surface700),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    VSpace.x4, VSpace.x2, VSpace.x4, VSpace.x2),
                child: Row(
                  children: [
                    Icon(Icons.location_on_outlined,
                        size: 13, color: VColors.contentFaint),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        company.email ?? 'No email',
                        style: VType.caption.copyWith(
                            color: VColors.contentFaint, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: VColors.brand900,
                        borderRadius: BorderRadius.circular(VRadius.full),
                        border: Border.all(
                            color: VColors.brand400.withValues(alpha: 0.3),
                            width: 1),
                      ),
                      child: Text('View →',
                          style: VType.caption.copyWith(
                              color: VColors.brand300,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
