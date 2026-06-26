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
  return const TextTheme(
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
class VType {
  const VType._();

  static const display = TextStyle(
    fontFamily: _sans,
    fontSize: 34,
    height: 40 / 34,
    fontWeight: FontWeight.w700,
    color: VColors.contentStrong,
  );

  static const titleLg = TextStyle(
    fontFamily: _sans,
    fontSize: 24,
    height: 30 / 24,
    fontWeight: FontWeight.w700,
    color: VColors.contentStrong,
  );

  static const title = TextStyle(
    fontFamily: _sans,
    fontSize: 20,
    height: 26 / 20,
    fontWeight: FontWeight.w600,
    color: VColors.contentStrong,
  );

  static const bodyLg = TextStyle(
    fontFamily: _sans,
    fontSize: 17,
    height: 24 / 17,
    fontWeight: FontWeight.w500,
    color: VColors.contentDefault,
  );

  static const body = TextStyle(
    fontFamily: _sans,
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeight.w400,
    color: VColors.contentDefault,
  );

  static const label = TextStyle(
    fontFamily: _sans,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w600,
    color: VColors.contentDefault,
  );

  static const caption = TextStyle(
    fontFamily: _sans,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w500,
    color: VColors.contentMuted,
  );

  // mono-lg — plate / slot hero (22/28/600 mono)
  static const monoLg = TextStyle(
    fontFamily: _mono,
    fontFamilyFallback: _monoFallback,
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.5,
    color: VColors.contentStrong,
  );

  // mono — timers, key codes, IDs (15/20/500 mono)
  static const mono = TextStyle(
    fontFamily: _mono,
    fontFamilyFallback: _monoFallback,
    fontSize: 15,
    height: 20 / 15,
    fontWeight: FontWeight.w500,
    color: VColors.contentMuted,
  );

  // Plate hero on the driver mission card — display size in mono.
  static const plateHero = TextStyle(
    fontFamily: _mono,
    fontFamilyFallback: _monoFallback,
    fontSize: 44,
    height: 48 / 44,
    fontWeight: FontWeight.w700,
    letterSpacing: 4,
    color: VColors.contentStrong,
  );
}

/// Vālet dark-luxe theme (primary). Generated from tokens → ThemeData (M3).
ThemeData buildValetDarkTheme() {
  final textTheme = _buildTextTheme();
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: VColors.surface900,
    canvasColor: VColors.surface900,
    fontFamily: _sans,
    textTheme: textTheme,
    splashColor: VColors.brand500.withValues(alpha: 0.10),
    highlightColor: VColors.brand500.withValues(alpha: 0.06),
    colorScheme: const ColorScheme.dark(
      primary: VColors.brand500,
      onPrimary: VColors.contentOnAccent,
      primaryContainer: VColors.brand900,
      onPrimaryContainer: VColors.brand300,
      secondary: VColors.brand400,
      onSecondary: VColors.contentOnAccent,
      surface: VColors.surface800,
      onSurface: VColors.contentDefault,
      surfaceContainerHighest: VColors.surface700,
      outline: VColors.surface500,
      outlineVariant: VColors.surface600,
      error: VColors.alertDanger,
      onError: VColors.contentStrong,
    ),
    dividerColor: VColors.surface600,
    iconTheme: const IconThemeData(color: VColors.contentDefault),
    appBarTheme: const AppBarTheme(
      backgroundColor: VColors.surface900,
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
        borderSide: const BorderSide(color: VColors.surface600, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(VRadius.md),
        borderSide: const BorderSide(color: VColors.brand500, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(VRadius.md),
        borderSide: const BorderSide(color: VColors.alertDanger, width: 1.4),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(VRadius.md),
        borderSide: const BorderSide(color: VColors.alertDanger, width: 1.6),
      ),
      errorStyle: VType.caption.copyWith(color: VColors.alertDanger),
    ),
    extensions: const [VStatusColors()],
  );
}
