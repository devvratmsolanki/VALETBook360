import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One ticker for all live timers (doc §9.6 performance budget — fixes the
/// "one timer per card" anti-pattern). A single 1s stream that any widget can
/// watch to recompute elapsed time.
final clockProvider = StreamProvider<DateTime>((ref) {
  final controller = StreamController<DateTime>();
  controller.add(DateTime.now());
  final timer = Timer.periodic(
    const Duration(seconds: 1),
    (_) => controller.add(DateTime.now()),
  );
  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });
  return controller.stream;
});

/// Compact "elapsed since" formatter for the mission timer (mm:ss under an
/// hour, then Hh Mm). Returns '—' when [since] is null.
String elapsedSince(DateTime? since, DateTime now) {
  if (since == null) return '—';
  var diff = now.difference(since);
  if (diff.isNegative) diff = Duration.zero;
  final h = diff.inHours;
  final m = diff.inMinutes % 60;
  final s = diff.inSeconds % 60;
  if (h > 0) return '${h}h ${m}m';
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}
