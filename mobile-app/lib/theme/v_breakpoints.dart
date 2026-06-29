import 'package:flutter/widgets.dart';

import 'v_tokens.dart';

/// Responsive foundation — Material 3 *window size classes*.
///
/// The app ships one codebase across phone, tablet, desktop and web. Rather than
/// scatter ad-hoc `MediaQuery.of(context).size.width > 600` checks, every screen
/// resolves layout off the semantic [VWindowClass] below. Thresholds follow the
/// Material 3 window-size-class spec (compact / medium / expanded), with an extra
/// `large` step for wide desktop so dashboards can spread to a third column.
///
/// Width boundaries (logical pixels), inclusive-low / exclusive-high:
///   compact   :    0 – 599   phones (portrait), narrow web
///   medium    :  600 – 904   large phones (landscape), small tablets
///   expanded  :  905 – 1239  tablets, small desktop windows
///   large     : 1240 +       desktop, wide web
enum VWindowClass { compact, medium, expanded, large }

/// Raw width thresholds. Exposed for the rare call-site that needs the number
/// (e.g. an animated layout interpolation) — prefer the [VWindowClass] enum and
/// the [VResponsive] helpers everywhere else.
class VBreakpoints {
  const VBreakpoints._();

  /// Upper bound of the `compact` class — the classic "phone vs not" line.
  static const double compact = 600;

  /// Upper bound of the `medium` class.
  static const double medium = 905;

  /// Upper bound of the `expanded` class; at/above this we're `large`.
  static const double expanded = 1240;

  static VWindowClass classify(double width) {
    if (width < compact) return VWindowClass.compact;
    if (width < medium) return VWindowClass.medium;
    if (width < expanded) return VWindowClass.expanded;
    return VWindowClass.large;
  }
}

/// Ergonomic, allocation-free responsive helpers hung off [BuildContext].
///
/// Uses [MediaQuery.sizeOf] (not `MediaQuery.of`) so a dependent widget only
/// rebuilds when the *size* changes — not on every unrelated MediaQuery mutation
/// (text scale, padding, view insets from the keyboard, …). That keeps resize
/// rebuilds cheap, which matters on web where the viewport can change often.
extension VResponsive on BuildContext {
  /// Current viewport width in logical pixels.
  double get screenWidth => MediaQuery.sizeOf(this).width;

  /// Current viewport height in logical pixels.
  double get screenHeight => MediaQuery.sizeOf(this).height;

  /// Semantic window size class for the current width.
  VWindowClass get windowClass => VBreakpoints.classify(screenWidth);

  /// `true` for phones / narrow web — the single-column, thumb-zone layout.
  bool get isCompact => windowClass == VWindowClass.compact;

  /// `true` once there's room for a two-pane / multi-column layout
  /// (tablet landscape and up).
  bool get isExpanded =>
      windowClass == VWindowClass.expanded || windowClass == VWindowClass.large;

  /// `true` on wide desktop — room for three columns / a persistent side rail.
  bool get isLarge => windowClass == VWindowClass.large;

  /// Resolve a value per window class, cascading downward from the nearest
  /// larger value that's provided. Only `compact` is required, so a caller can
  /// opt into only the breakpoints it cares about:
  ///
  /// ```dart
  /// final cols = context.responsive(compact: 1, expanded: 2, large: 3);
  /// ```
  T responsive<T>({
    required T compact,
    T? medium,
    T? expanded,
    T? large,
  }) {
    switch (windowClass) {
      case VWindowClass.large:
        return large ?? expanded ?? medium ?? compact;
      case VWindowClass.expanded:
        return expanded ?? medium ?? compact;
      case VWindowClass.medium:
        return medium ?? compact;
      case VWindowClass.compact:
        return compact;
    }
  }

  /// Symmetric page gutter that grows with the viewport so content isn't glued
  /// to the edges on desktop while staying thumb-friendly on phones.
  EdgeInsets get pagePadding => EdgeInsets.symmetric(
        horizontal: responsive(
          compact: VSpace.x4,
          medium: VSpace.x6,
          expanded: VSpace.x8,
        ),
        vertical: VSpace.x4,
      );

  /// Readable max line-length for centered single-column content (forms, reading
  /// flows). Caps growth on ultra-wide displays instead of stretching edge-to-edge.
  double get readableMaxWidth => 560;

  /// Max width for a content column inside a dashboard before it should switch
  /// to a multi-column grid. Used to center dashboards on very wide screens.
  double get dashboardMaxWidth => 1180;
}
