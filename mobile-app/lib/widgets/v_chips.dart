import 'package:flutter/material.dart';
import '../theme/v_colors.dart';
import '../theme/v_theme.dart';
import '../theme/v_tokens.dart';

/// `VKeySlotChip` (doc §6.9) — brand/500 @ 12% bg, brand/400 text, vpn_key icon,
/// mono slot code. Replaces the 🔑 emoji.
class VKeySlotChip extends StatelessWidget {
  const VKeySlotChip({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Key slot $code',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: VSpace.x3,
          vertical: VSpace.x2,
        ),
        decoration: BoxDecoration(
          color: VColors.brand500.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(VRadius.sm),
          border: Border.all(
            color: VColors.brand500.withValues(alpha: 0.30),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.vpn_key_rounded, size: 16, color: VColors.brand300),
            const SizedBox(width: VSpace.x2),
            Text(
              code,
              style: VType.mono.copyWith(color: VColors.brand300),
            ),
          ],
        ),
      ),
    );
  }
}

/// A generic dark tinted meta chip (guest, vehicle, mission type ribbon).
class VMetaChip extends StatelessWidget {
  const VMetaChip({
    super.key,
    required this.icon,
    required this.label,
    this.color,
    this.semanticLabel,
  });

  final IconData icon;
  final String label;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = color ?? VColors.contentMuted;
    return Semantics(
      label: semanticLabel ?? label,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: VSpace.x3,
          vertical: VSpace.x2,
        ),
        decoration: BoxDecoration(
          color: VColors.surface700,
          borderRadius: BorderRadius.circular(VRadius.sm),
          border: Border.all(color: VColors.surface600, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: c),
            const SizedBox(width: VSpace.x2),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: VType.label.copyWith(color: VColors.contentDefault),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
