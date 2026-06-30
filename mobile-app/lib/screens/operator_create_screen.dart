import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/operator_key_slots.dart';
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

  /// True once the operator taps a slot — drives the "(auto)" suffix on the
  /// selection label, and tells [_ensureSelection] not to silently re-pick.
  bool _manualPick = false;

  /// Whether the full slot picker grid is expanded (operator wants to override).
  bool _slotPickerExpanded = false;

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
      setState(() {
        _selectedSlot = next;
        _manualPick = false;
      });
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
                  _keySlotSection(slotsAsync, occupied),
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

  /// Key slot section: auto-assigns the first free slot silently, shows it as
  /// a badge. A "Change" button expands the full picker grid for overrides.
  Widget _keySlotSection(
    AsyncValue<OperatorKeySlots> slotsAsync,
    Set<String> occupied,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: VSpace.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: VSpace.x1, bottom: VSpace.x2),
            child: Text('Key slot', style: VType.caption),
          ),
          slotsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: VSpace.x3),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (_, __) => const VBanner(
              message: 'Could not load key slots. You can still add the car.',
            ),
            data: (pool) {
              if (pool.slots.isEmpty) {
                return Text('No key slots configured for this location.',
                    style: VType.caption);
              }
              final free = pool.slots.where((s) => !occupied.contains(s)).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Auto-assigned badge row
                  Row(
                    children: [
                      if (_selectedSlot != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: VSpace.x3, vertical: VSpace.x2),
                          decoration: BoxDecoration(
                            color: VColors.brand500,
                            borderRadius: BorderRadius.circular(VRadius.md),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.vpn_key_rounded,
                                  size: 14, color: VColors.contentOnAccent),
                              const SizedBox(width: VSpace.x1),
                              Text(_selectedSlot!,
                                  style: VType.label
                                      .copyWith(color: VColors.contentOnAccent)),
                              if (!_manualPick) ...[
                                const SizedBox(width: VSpace.x2),
                                Text('auto',
                                    style: VType.caption.copyWith(
                                        color: VColors.contentOnAccent
                                            .withValues(alpha: 0.75))),
                              ],
                            ],
                          ),
                        ),
                      ] else ...[
                        Text(
                          free.isEmpty ? 'No free slots' : 'Assigning…',
                          style: VType.caption,
                        ),
                      ],
                      const SizedBox(width: VSpace.x3),
                      if (free.isNotEmpty)
                        GestureDetector(
                          onTap: () => setState(
                              () => _slotPickerExpanded = !_slotPickerExpanded),
                          child: Text(
                            _slotPickerExpanded ? 'Hide' : 'Change',
                            style: VType.caption.copyWith(
                                color: VColors.brand400,
                                decoration: TextDecoration.underline,
                                decorationColor: VColors.brand400),
                          ),
                        ),
                    ],
                  ),
                  // Expandable full grid for manual override
                  if (_slotPickerExpanded) ...[
                    const SizedBox(height: VSpace.x3),
                    Wrap(
                      spacing: VSpace.x2,
                      runSpacing: VSpace.x2,
                      children: [
                        for (final slot in pool.slots)
                          _slotBox(
                            slot,
                            occupied: occupied.contains(slot),
                            selected: slot == _selectedSlot,
                          ),
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _slotBox(
    String slot, {
    required bool occupied,
    required bool selected,
  }) {
    final disabled = occupied || _busy;
    final Color bg;
    final Color fg;
    final Color border;
    if (selected) {
      bg = VColors.brand500;
      fg = VColors.contentOnAccent;
      border = VColors.brand500;
    } else if (occupied) {
      bg = VColors.surface800;
      fg = VColors.contentFaint;
      border = VColors.surface600;
    } else {
      bg = VColors.surface700;
      fg = VColors.contentStrong;
      border = VColors.surface600;
    }

    return Semantics(
      button: !occupied,
      selected: selected,
      enabled: !disabled,
      label: occupied ? 'Key slot $slot, occupied' : 'Key slot $slot',
      child: Opacity(
        opacity: occupied ? 0.55 : 1,
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(VRadius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(VRadius.md),
            onTap: disabled
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _selectedSlot = slot;
                      _manualPick = true;
                    });
                  },
            child: Container(
              constraints: const BoxConstraints(
                minWidth: 52,
                minHeight: VTarget.minTouch,
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: VSpace.x3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(VRadius.md),
                border: Border.all(color: border, width: selected ? 2 : 1),
              ),
              child: Text(
                slot,
                style: VType.label.copyWith(color: fg),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
    );
  }

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
