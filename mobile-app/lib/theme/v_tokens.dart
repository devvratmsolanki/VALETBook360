import 'package:flutter/material.dart';
import 'v_colors.dart';

/// Non-color tokens — spacing, radius, motion, targets — from `tokens.json`.

/// 4pt spacing scale — doc §6.3.
class VSpace {
  const VSpace._();
  static const double x0 = 2;
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16; // default gutter / screen padding
  static const double x5 = 20; // card padding
  static const double x6 = 24; // section gap
  static const double x8 = 32; // major section gap
  static const double x12 = 48; // hero spacing
}

/// Corner radii — doc §6.4.
class VRadius {
  const VRadius._();
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double full = 999;
}

/// Touch targets — doc §6.3 / tokens.target.
class VTarget {
  const VTarget._();
  static const double minTouch = 48;
  static const double thumbBand = 88;
  static const double navBar = 80;
}

/// Motion durations & curves — doc §6.7 / §9.5.
class VMotion {
  const VMotion._();
  static const stateAdvance = Duration(milliseconds: 240);
  static const cardEnter = Duration(milliseconds: 280);
  static const cardExit = Duration(milliseconds: 320);
  static const sheetOpen = Duration(milliseconds: 280);
  static const tabSwitch = Duration(milliseconds: 200);
  static const pulse = Duration(milliseconds: 1600);
  static const celebration = Duration(milliseconds: 600);
  static const reducedMotion = Duration(milliseconds: 120);

  // "spring(stiffness 320, damping 28)" → easeOutBack-like for the rail advance.
  static const Curve advanceCurve = Curves.easeOutBack;
  static const Curve emphasizedDecelerate = Curves.easeOutCubic;
  static const Curve emphasizedAccelerate = Curves.easeInCubic;
}

/// Theme extension carrying the status ramp + glow tokens so widgets read them
/// off `Theme.of(context).extension<VStatusColors>()` (doc §9.2).
@immutable
class VStatusColors extends ThemeExtension<VStatusColors> {
  const VStatusColors({
    this.queued = VColors.statusQueued,
    this.settled = VColors.statusSettled,
    this.secured = VColors.statusSecured,
    this.active = VColors.statusActive,
    this.dispatched = VColors.statusDispatched,
    this.moving = VColors.statusMoving,
    this.ready = VColors.statusReady,
    this.done = VColors.statusDone,
    this.warn = VColors.alertWarn,
    this.danger = VColors.alertDanger,
    this.success = VColors.alertSuccess,
  });

  final Color queued;
  final Color settled;
  final Color secured;
  final Color active;
  final Color dispatched;
  final Color moving;
  final Color ready;
  final Color done;
  final Color warn;
  final Color danger;
  final Color success;

  @override
  VStatusColors copyWith({
    Color? queued,
    Color? settled,
    Color? secured,
    Color? active,
    Color? dispatched,
    Color? moving,
    Color? ready,
    Color? done,
    Color? warn,
    Color? danger,
    Color? success,
  }) {
    return VStatusColors(
      queued: queued ?? this.queued,
      settled: settled ?? this.settled,
      secured: secured ?? this.secured,
      active: active ?? this.active,
      dispatched: dispatched ?? this.dispatched,
      moving: moving ?? this.moving,
      ready: ready ?? this.ready,
      done: done ?? this.done,
      warn: warn ?? this.warn,
      danger: danger ?? this.danger,
      success: success ?? this.success,
    );
  }

  @override
  VStatusColors lerp(ThemeExtension<VStatusColors>? other, double t) {
    if (other is! VStatusColors) return this;
    return VStatusColors(
      queued: Color.lerp(queued, other.queued, t)!,
      settled: Color.lerp(settled, other.settled, t)!,
      secured: Color.lerp(secured, other.secured, t)!,
      active: Color.lerp(active, other.active, t)!,
      dispatched: Color.lerp(dispatched, other.dispatched, t)!,
      moving: Color.lerp(moving, other.moving, t)!,
      ready: Color.lerp(ready, other.ready, t)!,
      done: Color.lerp(done, other.done, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      success: Color.lerp(success, other.success, t)!,
    );
  }
}
