import 'package:flutter/material.dart';

/// Vālet color tokens — the **logbook360.com** design system, now with a
/// runtime-switchable LIGHT (warm paper) and DARK (warm charcoal) variant of
/// the same OKLCH system (blue primary + terracotta accent).
///
/// IMPLEMENTATION NOTE — why these are getters, not `static const`:
/// the app references `VColors.*` ~400 times statically. A plain ThemeData
/// switch will NOT repaint those direct references. So every token is a
/// brightness-aware **static getter** backed by [_dark]; flipping [_dark] via
/// [setBrightness] and forcing a tree rebuild (the root ConsumerWidget watches
/// the ThemeController) makes the whole app re-read the new value.
///
/// Both palettes are EXACT sRGB hex from logbook360's OKLCH `:root` tokens —
/// do not approximate. Token *names* are preserved; only values vary by mode.
class VColors {
  const VColors._();

  /// Active brightness flag. Light is the default (logbook360 default theme).
  static bool _dark = false;

  /// Flip the palette. Call BEFORE building MaterialApp on every theme change
  /// (the root ConsumerWidget does this) so getters return the right variant.
  static void setBrightness(Brightness b) => _dark = b == Brightness.dark;

  /// Whether the dark variant is currently active (for any widget that needs
  /// to branch on mode without a BuildContext).
  static bool get isDark => _dark;

  // ======================================================================
  // Brand ramp — logbook BLUE. brand500 is THE primary fill; kept mid-deep
  // in BOTH modes so WHITE button text (contentOnAccent) passes AA on it.
  // ======================================================================
  static Color get brand300 => _dark ? const Color(0xFF33B4EE) : const Color(0xFF0092E1); // light hover / gradient top
  static Color get brand400 => _dark ? const Color(0xFF0092E1) : const Color(0xFF0073C0); // secondary / focus glow
  static Color get brand500 => const Color(0xFF0073C0); // THE primary fill (same both modes)
  static Color get brand600 => _dark ? const Color(0xFF007FC8) : const Color(0xFF005496); // pressed primary
  static Color get brand700 => _dark ? const Color(0xFF0B4C92) : const Color(0xFF0E3D82); // deep accent borders
  static Color get brand900 => _dark ? const Color(0xFF00324C) : const Color(0xFFDDF2FF); // accent tint background

  // ======================================================================
  // Surface ramp. LIGHT = cream "paper"; DARK = warm charcoal (hue 85).
  // surface950 = driver full-bleed bg + mission-card fill + scaffold/appbar
  // bg on operator/admin/company homes (ink layered on top).
  // ======================================================================
  static Color get surface950 => _dark ? const Color(0xFF0B0905) : const Color(0xFFEEE9DF); // full-bleed / card base
  static Color get surface900 => _dark ? const Color(0xFF13100A) : const Color(0xFFF5F1E9); // scaffold bg
  static Color get surface800 => _dark ? const Color(0xFF1C1913) : const Color(0xFFFEFCF7); // card / sheet base
  static Color get surface700 => _dark ? const Color(0xFF28251E) : const Color(0xFFF1ECE3); // raised card, input field
  static Color get surface600 => _dark ? const Color(0xFF39352D) : const Color(0xFFDEDAD2); // dividers, hairlines
  static Color get surface500 => _dark ? const Color(0xFF4B473F) : const Color(0xFFC8C4BA); // strong borders, disabled

  // ======================================================================
  // Content (text/icon). LIGHT = dark warm "ink"; DARK = light warm ink.
  // contentOnAccent stays WHITE in BOTH modes (text on blue/terracotta fills).
  // ======================================================================
  static Color get contentStrong => _dark ? const Color(0xFFF5F1EA) : const Color(0xFF141208); // headings, plates
  static Color get contentDefault => _dark ? const Color(0xFFC7C4BC) : const Color(0xFF3F3D34); // body
  static Color get contentMuted => _dark ? const Color(0xFF8F8C85) : const Color(0xFF6B6961); // secondary labels
  static Color get contentFaint => _dark ? const Color(0xFF66635C) : const Color(0xFF94928B); // decorative / faint
  static Color get contentOnAccent => const Color(0xFFFBF8F2); // WHITE ink on blue/terracotta fills (both modes)

  // ======================================================================
  // Status semantic ramp — tuned to read on each background.
  // DARK values are LIFTED so they read on warm charcoal; LIGHT values are
  // deepened so they read on cream. Used as: chip = color@14% bg + color text.
  // ======================================================================
  static Color get statusQueued => _dark ? const Color(0xFF8F8C85) : const Color(0xFF6B6961); // waiting_for_driver
  static Color get statusSettled => _dark ? const Color(0xFF32A5D4) : const Color(0xFF006D91); // parked (info)
  static Color get statusSecured => _dark ? const Color(0xFF0092E1) : const Color(0xFF0073C0); // key_in (blue)
  static Color get statusActive => _dark ? const Color(0xFFDD6D49) : const Color(0xFFC65029); // requested (terracotta)
  static Color get statusDispatched => _dark ? const Color(0xFFD5A13C) : const Color(0xFFC17924); // driver_assigned (warn)
  static Color get statusMoving => _dark ? const Color(0xFFDD6D49) : const Color(0xFFC65029); // en_route (terracotta)
  static Color get statusReady => _dark ? const Color(0xFF43A96E) : const Color(0xFF187C49); // arrived (success)
  static Color get statusDone => _dark ? const Color(0xFF66635C) : const Color(0xFF94928B); // delivered (receded)

  // ======================================================================
  // Alerts — lifted on dark, deepened on light.
  // ======================================================================
  static Color get alertWarn => _dark ? const Color(0xFFD5A13C) : const Color(0xFFC17924);
  static Color get alertDanger => _dark ? const Color(0xFFE36558) : const Color(0xFFB93F35);
  static Color get alertSuccess => _dark ? const Color(0xFF43A96E) : const Color(0xFF187C49);

  // ======================================================================
  // Accent (terracotta) + tints — logbook secondary accent & status tints.
  // ======================================================================
  static Color get accent => _dark ? const Color(0xFFDD6D49) : const Color(0xFFC65029); // terracotta
  static Color get accentTint => _dark ? const Color(0xFF472216) : const Color(0xFFFFE9E3);
  static Color get successTint => _dark ? const Color(0xFF13301F) : const Color(0xFFDFF0E4);
  static Color get warnTint => _dark ? const Color(0xFF332611) : const Color(0xFFFDEBDA);
  static Color get dangerTint => _dark ? const Color(0xFF3A1814) : const Color(0xFFFFE4E0);
  static Color get infoTint => _dark ? const Color(0xFF0E2A33) : const Color(0xFFE0F2FB);
}
