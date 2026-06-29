import 'package:flutter/material.dart';
import 'v_colors.dart';
import 'v_tokens.dart';

/// "Vālet Type Scale" — doc §6.2. Inter for UI, JetBrains Mono for plates/codes.
/// Fonts are referenced by family name; if the .ttf assets are not bundled
/// (see pubspec note), Flutter falls back gracefully to the platform sans /
/// monospace, so the app still compiles and renders.
const String _sans = 'Inter';
const String _mono = 'JetBrains Mono';
const List<String> _monoFallback = ['JetBrains Mono', 'monospace'];

TextTheme _buildTextTheme() {
  return TextTheme(
    // display — plate hero on driver mission card (34/40/700)
    displayLarge: TextStyle(
      fontFamily: _sans,
      fontSize: 34,
      height: 40 / 34,
      fontWeight: FontWeight.w700,
      color: VColors.contentStrong,
    ),
    // title-lg — screen titles (24/30/700)
    headlineSmall: TextStyle(
      fontFamily: _sans,
      fontSize: 24,
      height: 30 / 24,
      fontWeight: FontWeight.w700,
      color: VColors.contentStrong,
    ),
    // title — section headers (20/26/600)
    titleLarge: TextStyle(
      fontFamily: _sans,
      fontSize: 20,
      height: 26 / 20,
      fontWeight: FontWeight.w600,
      color: VColors.contentStrong,
    ),
    // body-lg — primary body (17/24/500)
    bodyLarge: TextStyle(
      fontFamily: _sans,
      fontSize: 17,
      height: 24 / 17,
      fontWeight: FontWeight.w500,
      color: VColors.contentDefault,
    ),
    // body — default body (15/22/400)
    bodyMedium: TextStyle(
      fontFamily: _sans,
      fontSize: 15,
      height: 22 / 15,
      fontWeight: FontWeight.w400,
      color: VColors.contentDefault,
    ),
    // label — buttons, nav, chips (13/18/600)
    labelLarge: TextStyle(
      fontFamily: _sans,
      fontSize: 13,
      height: 18 / 13,
      fontWeight: FontWeight.w600,
      color: VColors.contentDefault,
    ),
    // caption — secondary meta, the readable floor (12/16/500)
    bodySmall: TextStyle(
      fontFamily: _sans,
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w500,
      color: VColors.contentMuted,
    ),
  );
}

/// Named access to the mono styles and the semantic scale steps that don't map
/// 1:1 onto Material's TextTheme slots.
///
/// These are **getters** (not `const`) so their `color`, sourced from the
/// runtime [VColors] getters, re-reads on a theme toggle. Font/size/weight are
/// stable; only the resolved color differs between light and dark.
class VType {
  const VType._();

  static TextStyle get display => TextStyle(
        fontFamily: _sans,
        fontSize: 34,
        height: 40 / 34,
        fontWeight: FontWeight.w700,
        color: VColors.contentStrong,
      );

  static TextStyle get titleLg => TextStyle(
        fontFamily: _sans,
        fontSize: 24,
        height: 30 / 24,
        fontWeight: FontWeight.w700,
        color: VColors.contentStrong,
      );

  static TextStyle get title => TextStyle(
        fontFamily: _sans,
        fontSize: 20,
        height: 26 / 20,
        fontWeight: FontWeight.w600,
        color: VColors.contentStrong,
      );

  static TextStyle get bodyLg => TextStyle(
        fontFamily: _sans,
        fontSize: 17,
        height: 24 / 17,
        fontWeight: FontWeight.w500,
        color: VColors.contentDefault,
      );

  static TextStyle get body => TextStyle(
        fontFamily: _sans,
        fontSize: 15,
        height: 22 / 15,
        fontWeight: FontWeight.w400,
        color: VColors.contentDefault,
      );

  static TextStyle get label => TextStyle(
        fontFamily: _sans,
        fontSize: 13,
        height: 18 / 13,
        fontWeight: FontWeight.w600,
        color: VColors.contentDefault,
      );

  static TextStyle get caption => TextStyle(
        fontFamily: _sans,
        fontSize: 12,
        height: 16 / 12,
        fontWeight: FontWeight.w500,
        color: VColors.contentMuted,
      );

  // mono-lg — plate / slot hero (22/28/600 mono)
  static TextStyle get monoLg => TextStyle(
        fontFamily: _mono,
        fontFamilyFallback: _monoFallback,
        fontSize: 22,
        height: 28 / 22,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
        color: VColors.contentStrong,
      );

  // mono — timers, key codes, IDs (15/20/500 mono)
  static TextStyle get mono => TextStyle(
        fontFamily: _mono,
        fontFamilyFallback: _monoFallback,
        fontSize: 15,
        height: 20 / 15,
        fontWeight: FontWeight.w500,
        color: VColors.contentMuted,
      );

  // Plate hero on the driver mission card — display size in mono.
  static TextStyle get plateHero => TextStyle(
        fontFamily: _mono,
        fontFamilyFallback: _monoFallback,
        fontSize: 44,
        height: 48 / 44,
        fontWeight: FontWeight.w700,
        letterSpacing: 4,
        color: VColors.contentStrong,
      );
}

/// Shared ThemeData builder for both brightnesses. The per-mode colors come
/// from [VColors] getters (set via [VColors.setBrightness] before build) so the
/// light and dark themes differ only in the [brightness]/[ColorScheme] flavour
/// and the resolved token values — the structure is identical.
ThemeData _buildValetTheme(Brightness brightness) {
  final textTheme = _buildTextTheme();
  final isDark = brightness == Brightness.dark;
  final colorScheme = (isDark
      ? const ColorScheme.dark()
      : const ColorScheme.light());

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: VColors.surface900,
    canvasColor: VColors.surface900,
    fontFamily: _sans,
    textTheme: textTheme,
    // Ripple/hover tints: brand-blue at low alpha (reads on paper and charcoal).
    splashColor: VColors.brand500.withValues(alpha: 0.12),
    highlightColor: VColors.brand500.withValues(alpha: 0.06),
    colorScheme: colorScheme.copyWith(
      primary: VColors.brand500, // blue #0073C0 — white button text passes AA
      onPrimary: VColors.contentOnAccent, // WHITE on blue fill
      primaryContainer: VColors.brand900, // blue tint bg
      onPrimaryContainer:
          isDark ? VColors.brand300 : VColors.brand700, // legible on the tint
      secondary: VColors.accent, // terracotta
      onSecondary: VColors.contentOnAccent,
      surface: VColors.surface800, // card surface
      onSurface: VColors.contentDefault, // body ink
      surfaceContainerHighest: VColors.surface700, // raised / input
      outline: VColors.surface500, // strong borders
      outlineVariant: VColors.surface600, // hairlines
      error: VColors.alertDanger,
      onError: VColors.contentOnAccent, // white on the danger fill
    ),
    dividerColor: VColors.surface600,
    iconTheme: IconThemeData(color: VColors.contentDefault),
    appBarTheme: AppBarTheme(
      backgroundColor: VColors.surface900,
      foregroundColor: VColors.contentStrong,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: VColors.surface700,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: VSpace.x4,
        vertical: VSpace.x4,
      ),
      hintStyle: VType.body.copyWith(color: VColors.contentFaint),
      labelStyle: VType.caption,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(VRadius.md),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(VRadius.md),
        borderSide: BorderSide(color: VColors.surface600, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(VRadius.md),
        borderSide: BorderSide(color: VColors.brand500, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(VRadius.md),
        borderSide: BorderSide(color: VColors.alertDanger, width: 1.4),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(VRadius.md),
        borderSide: BorderSide(color: VColors.alertDanger, width: 1.6),
      ),
      errorStyle: VType.caption.copyWith(color: VColors.alertDanger),
    ),
    extensions: [VStatusColors.current()],
  );
}

/// logbook360 warm-paper LIGHT theme (default).
ThemeData buildValetLightTheme() => _buildValetTheme(Brightness.light);

/// logbook360 warm-charcoal DARK theme.
ThemeData buildValetDarkTheme() => _buildValetTheme(Brightness.dark);
