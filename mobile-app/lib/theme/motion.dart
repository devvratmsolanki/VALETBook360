import 'package:flutter/widgets.dart';
import 'v_tokens.dart';

/// Reduced-motion helpers. Per doc §6.7/§9.5: when the OS requests reduced
/// motion, all transitions degrade to ≤120ms cross-fades and pulses/celebration
/// animations are disabled (haptic + static state instead).
class Motion {
  const Motion._();

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  /// Effective duration honoring reduced motion.
  static Duration duration(BuildContext context, Duration full) =>
      reduced(context) ? VMotion.reducedMotion : full;

  /// Effective curve honoring reduced motion (linear cross-fade when reduced).
  static Curve curve(BuildContext context, Curve full) =>
      reduced(context) ? Curves.linear : full;
}
