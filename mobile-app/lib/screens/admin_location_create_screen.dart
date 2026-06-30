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

/// How the location sheet should persist on submit. The caller wires the actual
/// controller call (company-detail or admin-locations) so this sheet stays
/// agnostic about which slice owns the data. Returns true on success; the
/// caller exposes the error via [errorReader].
typedef LocationSubmit = Future<bool> Function(CreateLocationInput input);
typedef ErrorReader = String? Function();

/// Add/Edit location sheet — re-platforms the Locations tab of
/// `CompanyDetail.jsx` and the create/edit in `AdminLocations.jsx`. Required:
/// name + keyCapacity (int ≥ 0). Address fields are optional.
/// Pass [facilityOwners] to show a facility-owner assignment picker.
class AdminLocationSheet extends ConsumerStatefulWidget {
  const AdminLocationSheet({
    super.key,
    required this.onSubmit,
    required this.errorReader,
    this.existing,
    this.facilityOwners = const [],
  });

  final LocationSubmit onSubmit;
  final ErrorReader errorReader;

  /// When set, the sheet is in edit mode and pre-fills the fields.
  final AdminLocation? existing;

  /// Facility owners to show in the assignment picker. Empty → no picker shown.
  final List<AdminUser> facilityOwners;

  static Future<bool?> show(
    BuildContext context, {
    required LocationSubmit onSubmit,
    required ErrorReader errorReader,
    AdminLocation? existing,
    List<AdminUser> facilityOwners = const [],
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AdminLocationSheet(
        onSubmit: onSubmit,
        errorReader: errorReader,
        existing: existing,
        facilityOwners: facilityOwners,
      ),
    );
  }

  @override
  ConsumerState<AdminLocationSheet> createState() => _AdminLocationSheetState();
}

class _AdminLocationSheetState extends ConsumerState<AdminLocationSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _city;
  late final TextEditingController _state;
  late final TextEditingController _country;
  late final TextEditingController _keyCapacity;
  String? _facilityOwnerId;
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _address = TextEditingController(text: e?.address ?? '');
    _city = TextEditingController(text: e?.city ?? '');
    _state = TextEditingController(text: e?.state ?? '');
    _country = TextEditingController(text: e?.country ?? '');
    _keyCapacity =
        TextEditingController(text: e == null ? '' : e.keyCapacity.toString());
    // Pre-fill only if the owner is still in the picker list.
    if (e?.facilityOwnerId != null &&
        widget.facilityOwners.any((u) => u.id == e!.facilityOwnerId)) {
      _facilityOwnerId = e!.facilityOwnerId;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _city.dispose();
    _state.dispose();
    _country.dispose();
    _keyCapacity.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final input = CreateLocationInput(
      name: _name.text,
      address: _address.text,
      city: _city.text,
      state: _state.text,
      country: _country.text,
      keyCapacity: int.tryParse(_keyCapacity.text.trim()) ?? 0,
      facilityOwnerId: _facilityOwnerId,
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
            Text(_isEdit ? 'Edit location' : 'New location',
                style: VType.title.copyWith(color: VColors.contentStrong)),
            const SizedBox(height: VSpace.x1),
            Text('Set the place and its key-slot capacity.',
                style: VType.caption),
            const SizedBox(height: VSpace.x5),
            if (_error != null) ...[
              VBanner(message: _error!),
              const SizedBox(height: VSpace.x4),
            ],
            AdminFormField(
              controller: _name,
              label: 'Location name',
              hint: 'Downtown Garage',
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Name is required' : null,
            ),
            AdminFormField(
              controller: _keyCapacity,
              label: 'Key capacity',
              hint: '50',
              enabled: !_busy,
              keyboardType: TextInputType.number,
              validator: (v) {
                final s = (v ?? '').trim();
                if (s.isEmpty) return 'Key capacity is required';
                final n = int.tryParse(s);
                if (n == null || n < 0) return 'Enter a whole number ≥ 0';
                return null;
              },
            ),
            AdminFormField(
              controller: _address,
              label: 'Address (optional)',
              hint: '100 Market St',
              enabled: !_busy,
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AdminFormField(
                    controller: _city,
                    label: 'City (optional)',
                    hint: 'Metropolis',
                    enabled: !_busy,
                  ),
                ),
                const SizedBox(width: VSpace.x3),
                Expanded(
                  child: AdminFormField(
                    controller: _state,
                    label: 'State (optional)',
                    hint: 'CA',
                    enabled: !_busy,
                  ),
                ),
              ],
            ),
            AdminFormField(
              controller: _country,
              label: 'Country (optional)',
              hint: 'USA',
              enabled: !_busy,
            ),
            if (widget.facilityOwners.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(left: VSpace.x1, bottom: VSpace.x2),
                child: Text('Facility owner (optional)', style: VType.caption),
              ),
              _FacilityOwnerDropdown(
                owners: widget.facilityOwners,
                value: _facilityOwnerId,
                enabled: !_busy,
                onChanged: (v) => setState(() => _facilityOwnerId = v),
              ),
              const SizedBox(height: VSpace.x3),
            ],
            const SizedBox(height: VSpace.x5),
            VPrimaryButton(
              label: _isEdit ? 'Save location' : 'Add location',
              icon: Icons.place_rounded,
              loading: _busy,
              onPressed: _busy ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _FacilityOwnerDropdown extends StatelessWidget {
  const _FacilityOwnerDropdown({
    required this.owners,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final List<AdminUser> owners;
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
          icon: Icon(Icons.expand_more_rounded, color: VColors.contentMuted),
          hint: Text('None',
              style: VType.bodyLg.copyWith(color: VColors.contentFaint)),
          style: VType.bodyLg.copyWith(color: VColors.contentStrong),
          onChanged: enabled ? onChanged : null,
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text('None',
                  style: VType.bodyLg.copyWith(color: VColors.contentMuted)),
            ),
            for (final u in owners)
              DropdownMenuItem<String?>(
                value: u.id,
                child: Text(u.name ?? u.email,
                    overflow: TextOverflow.ellipsis),
              ),
          ],
        ),
      ),
    );
  }
}
