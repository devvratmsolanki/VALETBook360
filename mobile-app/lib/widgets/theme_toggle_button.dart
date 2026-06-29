import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/providers.dart';
import '../theme/v_colors.dart';

/// App-bar control that flips light↔dark and persists the choice.
///
/// Lives in the action area of every panel's app bar (driver, operator, admin,
/// company) so the toggle is reachable everywhere. Shows a sun when dark is
/// active (tap → go light) and a moon when light is active (tap → go dark),
/// matching the convention that the icon previews the destination mode.
class ThemeToggleButton extends ConsumerWidget {
  const ThemeToggleButton({super.key, this.color});

  /// Optional icon tint override (panels use `contentMuted` to match their
  /// existing refresh/logout icons). Defaults to `contentMuted`.
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch so the icon updates immediately when the mode changes.
    ref.watch(themeControllerProvider);
    final platform = MediaQuery.platformBrightnessOf(context);
    final controller = ref.read(themeControllerProvider.notifier);
    final isDark = controller.resolve(platform) == Brightness.dark;
    final tint = color ?? VColors.contentMuted;

    return IconButton(
      tooltip: isDark ? 'Switch to light theme' : 'Switch to dark theme',
      visualDensity: VisualDensity.compact,
      icon: Icon(
        isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
        color: tint,
      ),
      onPressed: () => controller.toggle(platform),
    );
  }
}
