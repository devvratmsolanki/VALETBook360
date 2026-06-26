import 'package:flutter/material.dart';
import '../theme/v_colors.dart';
import '../theme/v_theme.dart';
import '../theme/v_tokens.dart';

/// `VPrimaryButton` (doc §6.9). brand/500 fill, 52px tall, accent glow,
/// press scale 0.98, locked-width loading spinner, disabled = surface/600.
/// One per screen.
class VPrimaryButton extends StatefulWidget {
  const VPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  @override
  State<VPrimaryButton> createState() => _VPrimaryButtonState();
}

class _VPrimaryButtonState extends State<VPrimaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1,
        duration: const Duration(milliseconds: 90),
        child: GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel:
              enabled ? () => setState(() => _pressed = false) : null,
          onTap: enabled ? widget.onPressed : null,
          child: Container(
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: enabled
                  ? (_pressed ? VColors.brand600 : VColors.brand500)
                  : VColors.surface600,
              borderRadius: BorderRadius.circular(VRadius.md),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: VColors.brand500.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: widget.loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor:
                          AlwaysStoppedAnimation(VColors.contentOnAccent),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(
                          widget.icon,
                          size: 18,
                          color: enabled
                              ? VColors.contentOnAccent
                              : VColors.contentFaint,
                        ),
                        const SizedBox(width: VSpace.x2),
                      ],
                      Text(
                        widget.label,
                        style: VType.label.copyWith(
                          color: enabled
                              ? VColors.contentOnAccent
                              : VColors.contentFaint,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
