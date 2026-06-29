import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/admin_location.dart';
import '../models/admin_user.dart';
import '../theme/v_colors.dart';
import '../theme/v_theme.dart';
import '../theme/v_tokens.dart';
import '../widgets/admin_form_field.dart';
import '../widgets/v_primary_button.dart';
import '../widgets/v_states.dart';

typedef StaffSubmit = Future<bool> Function(CreateStaffInput input);
typedef ErrorReader = String? Function();

/// Add operator / driver sheet — re-platforms the Operators & Drivers tabs of
/// `CompanyDetail.jsx`, which both call create-staff and link the auth login.
/// `role` is fixed by the caller to `valet` (operator) or `driver`; the backend
/// rejects manager/admin. Location is an optional picker scoped to the company.
class AdminStaffSheet extends ConsumerStatefulWidget {
  const AdminStaffSheet({
    super.key,
    required this.role,
    required this.locations,
    required this.onSubmit,
    required this.errorReader,
  });

  /// `valet` | `driver`.
  final String role;
  final List<AdminLocation> locations;
  final StaffSubmit onSubmit;
  final ErrorReader errorReader;

  static Future<bool?> show(
    BuildContext context, {
    required String role,
    required List<AdminLocation> locations,
    required StaffSubmit onSubmit,
    required ErrorReader errorReader,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AdminStaffSheet(
        role: role,
        locations: locations,
        onSubmit: onSubmit,
        errorReader: errorReader,
      ),
    );
  }

  @override
  ConsumerState<AdminStaffSheet> createState() => _AdminStaffSheetState();
}

class _AdminStaffSheetState extends ConsumerState<AdminStaffSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _locationId;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  bool get _isDriver => widget.role == 'driver';
  String get _roleNoun => _isDriver ? 'driver' : 'operator';

  @override
  void dispose() {
    _name.dispose();
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

    final input = CreateStaffInput(
      email: _email.text,
      password: _password.text,
      name: _name.text,
      role: widget.role,
      locationId: _locationId,
    );
    final ok = await widget.onSubmit(input);

    if (!mounted) return;
    if (ok) {
      HapticFeedback.lightImpact();
      Navigator.of(context).pop(true);
    } else {
      HapticFeedback.vibrate();
      setState(() {
        _busy = false;
        _error = widget.errorReader();
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
            Text('New $_roleNoun',
                style: VType.title.copyWith(color: VColors.contentStrong)),
            const SizedBox(height: VSpace.x1),
            Text('Creates a login for this $_roleNoun in the company.',
                style: VType.caption),
            const SizedBox(height: VSpace.x5),
            if (_error != null) ...[
              VBanner(message: _error!),
              const SizedBox(height: VSpace.x4),
            ],
            AdminFormField(
              controller: _name,
              label: 'Full name',
              hint: 'Riya Sharma',
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Name is required' : null,
            ),
            AdminFormField(
              controller: _email,
              label: 'Email',
              hint: '$_roleNoun@company.com',
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              validator: validateEmail,
            ),
            AdminFormField(
              controller: _password,
              label: 'Password',
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
            if (widget.locations.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(left: VSpace.x1, bottom: VSpace.x2),
                child: Text('Location (optional)', style: VType.caption),
              ),
              _LocationDropdown(
                locations: widget.locations,
                value: _locationId,
                enabled: !_busy,
                onChanged: (v) => setState(() => _locationId = v),
              ),
              const SizedBox(height: VSpace.x3),
            ],
            const SizedBox(height: VSpace.x4),
            VPrimaryButton(
              label: 'Add $_roleNoun',
              icon: _isDriver
                  ? Icons.person_pin_circle_rounded
                  : Icons.badge_rounded,
              loading: _busy,
              onPressed: _busy ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationDropdown extends StatelessWidget {
  const _LocationDropdown({
    required this.locations,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final List<AdminLocation> locations;
  final String? value;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: VSpace.x4),
      decoration: BoxDecoration(
        color: VColors.surface700,
        borderRadius: BorderRadius.circular(VRadius.md),
        border: Border.all(color: VColors.surface600, width: 1),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: value,
          isExpanded: true,
          dropdownColor: VColors.surface800,
          icon: Icon(Icons.expand_more_rounded,
              color: VColors.contentMuted),
          hint: Text('Unassigned',
              style: VType.bodyLg.copyWith(color: VColors.contentFaint)),
          style: VType.bodyLg.copyWith(color: VColors.contentStrong),
          onChanged: enabled ? onChanged : null,
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text('Unassigned',
                  style: VType.bodyLg.copyWith(color: VColors.contentMuted)),
            ),
            for (final loc in locations)
              DropdownMenuItem<String?>(
                value: loc.id,
                child: Text(loc.name, overflow: TextOverflow.ellipsis),
              ),
          ],
        ),
      ),
    );
  }
}
