import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/transaction.dart';
import '../state/providers.dart';
import '../theme/v_colors.dart';
import '../theme/v_theme.dart';
import '../theme/v_tokens.dart';
import '../widgets/v_primary_button.dart';
import '../widgets/v_states.dart';

/// "+ New car" create sheet (doc §7 operator floor). Whitelisted fields only —
/// carPlate is required, the rest optional. Matches the login form's field +
/// validation style. Shown as a modal bottom sheet from the floor screen.
class OperatorCreateSheet extends ConsumerStatefulWidget {
  const OperatorCreateSheet({super.key});

  /// Opens the create sheet; returns the plate of the created car on success.
  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const OperatorCreateSheet(),
    );
  }

  @override
  ConsumerState<OperatorCreateSheet> createState() =>
      _OperatorCreateSheetState();
}

class _OperatorCreateSheetState extends ConsumerState<OperatorCreateSheet> {
  final _formKey = GlobalKey<FormState>();
  final _plate = TextEditingController();
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _color = TextEditingController();
  final _guestName = TextEditingController();
  final _guestPhone = TextEditingController();
  bool _busy = false;

  /// The chosen key slot name (sent as `keyCode`). Auto-selected to the lowest
  /// free slot; null when nothing is selected / no slot is free.
  String? _selectedSlot;



  @override
  void dispose() {
    _plate.dispose();
    _make.dispose();
    _model.dispose();
    _color.dispose();
    _guestName.dispose();
    _guestPhone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);

    final input = CreateTransactionInput(
      carPlate: _plate.text.trim().toUpperCase(),
      carMake: _make.text,
      carModel: _model.text,
      carColor: _color.text,
      guestName: _guestName.text,
      guestPhone: _guestPhone.text,
      keyCode: _selectedSlot ?? '',
    );
    final tx = await ref.read(floorControllerProvider.notifier).create(input);

    if (!mounted) return;
    if (tx != null) {
      HapticFeedback.lightImpact();
      Navigator.of(context).pop(tx.carPlate);
    } else {
      HapticFeedback.vibrate();
      // The create failed (e.g. SLOT_TAKEN 409 from another operator). Refresh
      // the floor so occupancy — and the auto-selection — reflect reality.
      ref.read(floorControllerProvider.notifier).load(silent: true);
      setState(() => _busy = false);
    }
  }

  /// Keep [_selectedSlot] valid against the live pool + occupancy: preserve a
  /// still-free manual/auto pick, otherwise auto-select the lowest free slot
  /// (or null when none are free). Scheduled post-frame so it never mutates
  /// state mid-build.
  void _ensureSelection(List<String> pool, Set<String> occupied) {
    final free = pool.where((s) => !occupied.contains(s)).toList();
    if (_selectedSlot != null && free.contains(_selectedSlot)) return;
    final next = free.isEmpty ? null : free.first;
    if (_selectedSlot == next) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _selectedSlot = next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final floor = ref.watch(floorControllerProvider);
    final err = floor.error;
    final slotsAsync = ref.watch(operatorKeySlotsProvider);

    // Occupied slots are derived live from the floor feed (the set of non-empty
    // keyCodes on active transactions). Exact string match against pool names.
    final occupied = <String>{
      for (final t in floor.transactions)
        if (t.keyCode != null && t.keyCode!.trim().isNotEmpty) t.keyCode!.trim(),
    };
    // Once the pool is loaded, keep the selection in sync with occupancy.
    slotsAsync.whenData((pool) => _ensureSelection(pool.slots, occupied));

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: VColors.surface900,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(VRadius.xl)),
          border: Border(
            top: BorderSide(color: VColors.surface700, width: 1),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              VSpace.x5,
              VSpace.x4,
              VSpace.x5,
              VSpace.x6,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: VSpace.x5),
                      decoration: BoxDecoration(
                        color: VColors.surface600,
                        borderRadius: BorderRadius.circular(VRadius.full),
                      ),
                    ),
                  ),
                  Text('New car',
                      style: VType.title.copyWith(
                          color: VColors.contentStrong)),
                  const SizedBox(height: VSpace.x1),
                  Text('Check a vehicle onto the floor.',
                      style: VType.caption),
                  const SizedBox(height: VSpace.x5),
                  if (err != null) ...[
                    VBanner(message: err),
                    const SizedBox(height: VSpace.x4),
                  ],
                  _field(
                    controller: _plate,
                    label: 'License plate',
                    hint: 'ABC1234',
                    textCapitalization: TextCapitalization.characters,
                    enabled: !_busy,
                    validator: (v) {
                      final s = (v ?? '').trim();
                      if (s.isEmpty) return 'Plate is required';
                      if (!RegExp(r'^[A-Za-z0-9]{4,12}$').hasMatch(s)) {
                        return '4–12 letters/numbers';
                      }
                      return null;
                    },
                  ),
                  _row(
                    _field(
                      controller: _make,
                      label: 'Make',
                      hint: 'Tesla',
                      enabled: !_busy,
                    ),
                    _field(
                      controller: _model,
                      label: 'Model',
                      hint: 'Model 3',
                      enabled: !_busy,
                    ),
                  ),
                  _field(
                    controller: _color,
                    label: 'Color',
                    hint: 'Midnight',
                    enabled: !_busy,
                  ),
                  _field(
                    controller: _guestName,
                    label: 'Guest name',
                    hint: 'Riya Sharma',
                    enabled: !_busy,
                  ),
                  _field(
                    controller: _guestPhone,
                    label: 'Guest phone',
                    hint: '+1 555 0100',
                    keyboardType: TextInputType.phone,
                    enabled: !_busy,
                  ),
                  const SizedBox(height: VSpace.x5),
                  VPrimaryButton(
                    label: 'Add car',
                    icon: Icons.add_rounded,
                    loading: _busy,
                    onPressed: _busy ? null : _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(Widget a, Widget b) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: a),
          const SizedBox(width: VSpace.x3),
          Expanded(child: b),
        ],
      );


  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool enabled = true,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: VSpace.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: VSpace.x1, bottom: VSpace.x2),
            child: Text(label, style: VType.caption),
          ),
          TextFormField(
            controller: controller,
            enabled: enabled,
            keyboardType: keyboardType,
            textCapitalization: textCapitalization,
            validator: validator,
            style: VType.bodyLg.copyWith(color: VColors.contentStrong),
            decoration: InputDecoration(hintText: hint),
          ),
        ],
      ),
    );
  }
}
