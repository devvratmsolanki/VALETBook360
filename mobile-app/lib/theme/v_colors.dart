import 'package:flutter/material.dart';

/// Vālet color tokens — generated from `docs/design/tokens.json`.
/// Brand magenta + dark surface ramps are PRESERVED from the web app.
/// Do not hand-tune; regenerate from the token source.
class VColors {
  const VColors._();

  // ---- Brand ramp (PRESERVED) — doc §6.1.1 ----
  static const brand300 = Color(0xFFE84A7A); // hover/pressed, gradient top
  static const brand400 = Color(0xFFD42862); // secondary accent, focus glow
  static const brand500 = Color(0xFFA60445); // THE accent (max 1 fill/screen)
  static const brand600 = Color(0xFF8A0339); // pressed primary
  static const brand700 = Color(0xFF6E032E); // deep accent borders
  static const brand900 = Color(0xFF3A0119); // accent tint backgrounds

  // ---- Surface ramp (PRESERVED + extended) — doc §6.1.2 ----
  static const surface950 = Color(0xFF030303); // driver full-bleed bg
  static const surface900 = Color(0xFF050505); // scaffold bg
  static const surface800 = Color(0xFF0F0F0F); // card / sheet base
  static const surface700 = Color(0xFF1A1A1A); // raised card, input field
  static const surface600 = Color(0xFF2A2A2A); // pressed/elevated, dividers
  static const surface500 = Color(0xFF3A3A3A); // hairline borders, disabled

  // ---- Content (text/icon) — doc §6.1.3 ----
  static const contentStrong = Color(0xFFFFFFFF); // plates, headings (19:1)
  static const contentDefault = Color(0xFFE6E6E6); // body (15:1)
  static const contentMuted = Color(0xFF9A9A9A); // secondary labels (6.1:1)
  static const contentFaint = Color(0xFF6B6B6B); // decorative only
  static const contentOnAccent = Color(0xFF0A0A0A); // text on brand fills

  // ---- Status semantic ramp — doc §6.1.4 ----
  static const statusQueued = Color(0xFF7A8AA0); // waiting_for_driver
  static const statusSettled = Color(0xFF5A8FB0); // parked
  static const statusSecured = Color(0xFF5AA0A0); // key_in
  static const statusActive = Color(0xFFC77DAE); // requested (pulses)
  static const statusDispatched = Color(0xFFD08A5A); // driver_assigned
  static const statusMoving = Color(0xFFD6A94E); // en_route
  static const statusReady = Color(0xFF5BB98C); // arrived
  static const statusDone = Color(0xFF6B6B6B); // delivered (receded)

  // ---- Alerts — doc §6.1.4 ----
  static const alertWarn = Color(0xFFE0A93A);
  static const alertDanger = Color(0xFFE0564E);
  static const alertSuccess = Color(0xFF4FB97E);
}
