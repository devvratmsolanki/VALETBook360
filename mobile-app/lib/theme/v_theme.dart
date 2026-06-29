import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'v_colors.dart';
import 'v_tokens.dart';

/// "Vālet Type Scale" — redesigned typography.
///
/// Display + headings use **Space Grotesk** (geometric, characterful, with
/// distinctive figures that complement the mono plate codes); UI/body uses
/// **Inter** (the gold standard for dense product UI); codes/plates use
/// **JetBrains Mono**. All three are real faces loaded via `google_fonts`
/// (fetched + cached at runtime) rather than the OS fallback the app shipped
/// with before. Headings carry slightly negative tracking for a tighter,
/// more premium feel; sizes/line-heights are unchanged so no layout shifts.
///
/// Helpers below centralize the family choice so the scale stays consistent and
/// a future face swap is a one-line change.

TextStyle _display(
        {required double size,
        required double height,
        required FontWeight weight,
        double letterSpacing = 0,
        Color? color}) =>
    GoogleFonts.spaceGrotesk(
      fontSize: size,
      height: height / size,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      color: color,
    );

TextStyle _ui(
        {required double size,
        required double height,
        required FontWeight weight,
        double letterSpacing = 0,
        Color? color}) =>
    GoogleFonts.inter(
      fontSize: size,
      height: height / size,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      color: color,
    );

TextStyle _code(
        {required double size,
        required double height,
        required FontWeight weight,
        double letterSpacing = 0,
        Color? color}) =>
    GoogleFonts.jetBrainsMono(
      fontSize: size,
      height: height / size,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      color: color,
    );

TextTheme _buildTextTheme() {
  return TextTheme(
    // display — plate/section hero (34/40/700, tight tracking)
    displayLarge: _display(
        size: 34,
        height: 40,
        weight: FontWeight.w700,
        letterSpacing: -0.8,
        color: VColors.contentStrong),
    // title-lg — screen titles (24/30/700)
    headlineSmall: _display(
        size: 24,
        height: 30,
        weight: FontWeight.w700,
        letterSpacing: -0.6,
        color: VColors.contentStrong),
    // title — section headers (20/26/600)
    titleLarge: _display(
        size: 20,
        height: 26,
        weight: FontWeight.w600,
        letterSpacing: -0.3,
        color: VColors.contentStrong),
    // body-lg — primary body (17/24/500)
    bodyLarge: _ui(
        size: 17, height: 24, weight: FontWeight.w500, color: VColors.contentDefault),
    // body — default body (15/22/400)
    bodyMedium: _ui(
        size: 15, height: 22, weight: FontWeight.w400, color: VColors.contentDefault),
    // label — buttons, nav, chips (13/18/600)
    labelLarge: _ui(
        size: 13,
        height: 18,
        weight: FontWeight.w600,
        letterSpacing: 0.1,
        color: VColors.contentDefault),
    // caption — secondary meta (12/16/500)
    bodySmall: _ui(
        size: 12,
        height: 16,
        weight: FontWeight.w500,
        letterSpacing: 0.2,
        color: VColors.contentMuted),
  );
}

/// Named access to the semantic scale steps that don't map 1:1 onto Material's
/// TextTheme slots. Getters (not `const`) so their `color`, sourced from the
/// runtime [VColors] getters, re-reads on a theme toggle.
class VType {
  const VType._();

  static TextStyle get display => _display(
      size: 34,
      height: 40,
      weight: FontWeight.w700,
      letterSpacing: -0.8,
      color: VColors.contentStrong);

  static TextStyle get titleLg => _display(
      size: 24,
      height: 30,
      weight: FontWeight.w700,
      letterSpacing: -0.6,
      color: VColors.contentStrong);

  static TextStyle get title => _display(
      size: 20,
      height: 26,
      weight: FontWeight.w600,
      letterSpacing: -0.3,
      color: VColors.contentStrong);

  static TextStyle get bodyLg => _ui(
      size: 17, height: 24, weight: FontWeight.w500, color: VColors.contentDefault);

  static TextStyle get body => _ui(
      size: 15, height: 22, weight: FontWeight.w400, color: VColors.contentDefault);

  static TextStyle get label => _ui(
      size: 13,
      height: 18,
      weight: FontWeight.w600,
      letterSpacing: 0.1,
      color: VColors.contentDefault);

  static TextStyle get caption => _ui(
      size: 12,
      height: 16,
      weight: FontWeight.w500,
      letterSpacing: 0.2,
      color: VColors.contentMuted);

  // mono-lg — plate / slot hero (22/28/600 mono)
  static TextStyle get monoLg => _code(
      size: 22,
      height: 28,
      weight: FontWeight.w600,
      letterSpacing: 1.5,
      color: VColors.contentStrong);

  // mono — timers, key codes, IDs (15/20/500 mono)
  static TextStyle get mono => _code(
      size: 15, height: 20, weight: FontWeight.w500, color: VColors.contentMuted);

  // Plate hero on the driver mission card — display size in mono.
  static TextStyle get plateHero => _code(
      size: 44,
      height: 48,
      weight: FontWeight.w700,
      letterSpacing: 4,
      color: VColors.contentStrong);
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
    fontFamily: GoogleFonts.inter().fontFamily,
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
