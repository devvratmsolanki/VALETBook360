import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/company.dart';
import '../state/providers.dart';
import '../theme/v_colors.dart';
import '../theme/v_theme.dart';
import '../theme/v_tokens.dart';
import '../widgets/admin_form_field.dart';
import '../widgets/v_primary_button.dart';
import '../widgets/v_states.dart';

/// "+ New company" sheet — re-platforms the Add Company flow on
/// `Companies.jsx`. ADMIN only; provisions the company + its owner login
/// (manager role) in one transactional POST /api/companies. Surfaces
/// EMAIL_TAKEN (409) and INSUFFICIENT_PERMISSIONS (403) as inline banners.
class AdminCompanyCreateSheet extends ConsumerStatefulWidget {
  const AdminCompanyCreateSheet({super.key});

  /// Opens the sheet; returns the created company name on success.
  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AdminCompanyCreateSheet(),
    );
  }

  @override
  ConsumerState<AdminCompanyCreateSheet> createState() =>
      _AdminCompanyCreateSheetState();
}

class _AdminCompanyCreateSheetState
    extends ConsumerState<AdminCompanyCreateSheet> {
  final _formKey = GlobalKey<FormState>();
  final _companyName = TextEditingController();
  final _ownerName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _companyName.dispose();
    _ownerName.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final input = CreateCompanyInput(
      companyName: _companyName.text,
      ownerName: _ownerName.text,
      phone: _phone.text,
      email: _email.text,
      password: _password.text,
    );
    final company =
        await ref.read(companiesControllerProvider.notifier).create(input);

    if (!mounted) return;
    if (company != null) {
      HapticFeedback.lightImpact();
      Navigator.of(context).pop(company.displayName);
    } else {
      HapticFeedback.vibrate();
      setState(() {
        _busy = false;
        _error = ref.read(companiesControllerProvider.notifier).createError;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminSheetShell(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('New company',
                style: VType.title.copyWith(color: VColors.contentStrong)),
            const SizedBox(height: VSpace.x1),
            Text('Creates the company and its owner login in one step.',
                style: VType.caption),
            const SizedBox(height: VSpace.x5),
            if (_error != null) ...[
              VBanner(message: _error!),
              const SizedBox(height: VSpace.x4),
            ],
            AdminFormField(
              controller: _companyName,
              label: 'Company name',
              hint: 'Demo Valet Co',
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Company name is required' : null,
            ),
            AdminFormField(
              controller: _ownerName,
              label: 'Owner name (optional)',
              hint: 'Jordan Lee',
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
            ),
            AdminFormField(
              controller: _phone,
              label: 'Phone (optional)',
              hint: '+1 555 0100',
              enabled: !_busy,
              keyboardType: TextInputType.phone,
            ),
            AdminFormField(
              controller: _email,
              label: 'Owner email',
              hint: 'owner@company.com',
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              validator: validateEmail,
            ),
            AdminFormField(
              controller: _password,
              label: 'Owner password',
              hint: 'Min 8 chars, 1 letter + 1 number',
              enabled: !_busy,
              obscureText: _obscure,
              validator: validatePassword,
              suffix: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: VColors.contentMuted,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            const SizedBox(height: VSpace.x5),
            VPrimaryButton(
              label: 'Create company',
              icon: Icons.add_business_rounded,
              loading: _busy,
              onPressed: _busy ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
