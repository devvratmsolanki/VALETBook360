import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/lifecycle_status.dart';
import '../theme/motion.dart';
import '../theme/v_colors.dart';
import '../theme/v_theme.dart';
import '../theme/v_tokens.dart';

/// `VStatusRail` (doc §6.9 / §6.1.4) — the live status spine.
///
/// 8 nodes (one per lifecycle state). Past = filled status hue, current =
/// filled + pulse if action-needed, future = surface/600 outline. The fill
/// animates 240ms on advance (the "machine moved" feeling). State is read by
/// position + a single hue temperature shift, never by 9 memorized colors.
class VStatusRail extends StatefulWidget {
  const VStatusRail({
    super.key,
    required this.status,
    this.labeled = false,
  });

  final LifecycleStatus status;

  /// Full variant with the current label beneath; otherwise the compact dots.
  final bool labeled;

  @override
  State<VStatusRail> createState() => _VStatusRailState();
}

class _VStatusRailState extends State<VStatusRail>
    with TickerProviderStateMixin {
  late final AnimationController _advance;
  late final AnimationController _pulse;
  late Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    final idx = widget.status.railIndex.clamp(0, LifecycleStatus.rail.length - 1);
    _advance = AnimationController(vsync: this, value: 1);
    _progress = AlwaysStoppedAnimation(idx.toDouble());

    _pulse = AnimationController(
      vsync: this,
      duration: VMotion.pulse,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.status.shouldPulse && !Motion.reduced(context)) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void didUpdateWidget(covariant VStatusRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      final from = oldWidget.status.railIndex
          .clamp(0, LifecycleStatus.rail.length - 1)
          .toDouble();
      final to = widget.status.railIndex
          .clamp(0, LifecycleStatus.rail.length - 1)
          .toDouble();
      _advance
        ..duration = Motion.duration(context, VMotion.stateAdvance)
        ..reset();
      _progress = Tween<double>(begin: from, end: to).animate(
        CurvedAnimation(
          parent: _advance,
          curve: Motion.curve(context, VMotion.advanceCurve),
        ),
      );
      _advance.forward();

      if (widget.status.shouldPulse && !Motion.reduced(context)) {
        if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
      } else {
        _pulse.stop();
        _pulse.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _advance.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rail = RepaintBoundary(
      child: SizedBox(
        height: 14,
        child: AnimatedBuilder(
          animation: Listenable.merge([_advance, _pulse]),
          builder: (context, _) {
            return CustomPaint(
              painter: _RailPainter(
                progress: _progress.value,
                currentColor: widget.status.color,
                pulse: widget.status.shouldPulse ? _pulse.value : 0,
                nodeColors: LifecycleStatus.rail.map((s) => s.color).toList(),
              ),
              size: Size.infinite,
            );
          },
        ),
      ),
    );

    if (!widget.labeled) return rail;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        rail,
        const SizedBox(height: VSpace.x2),
        Text(
          widget.status.label,
          style: VType.caption.copyWith(color: widget.status.color),
        ),
      ],
    );
  }
}

class _RailPainter extends CustomPainter {
  _RailPainter({
    required this.progress,
    required this.currentColor,
    required this.pulse,
    required this.nodeColors,
  });

  /// Fractional position along the 8-node rail (0..7), animated.
  final double progress;
  final Color currentColor;
  final double pulse; // 0..1
  final List<Color> nodeColors;

  static const _count = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    const r = 3.5;
    final usable = size.width - r * 2;
    final step = usable / (_count - 1);

    final track = Paint()
      ..color = VColors.surface600
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    // Base track.
    canvas.drawLine(Offset(r, cy), Offset(size.width - r, cy), track);

    // Filled portion up to progress.
    final fillEnd = r + step * progress;
    final fill = Paint()
      ..shader = LinearGradient(
        colors: [
          nodeColors.first,
          currentColor,
        ],
      ).createShader(Rect.fromLTWH(0, 0, math.max(fillEnd, 1), size.height))
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(r, cy), Offset(fillEnd, cy), fill);

    // Nodes.
    final currentIndex = progress.round();
    for (var i = 0; i < _count; i++) {
      final x = r + step * i;
      final isPast = i < progress - 0.001;
      final isCurrent = i == currentIndex;

      if (isCurrent) {
        // Pulse halo for action-needed current node.
        if (pulse > 0) {
          final halo = Paint()
            ..color = currentColor.withValues(alpha: 0.28 * (1 - pulse));
          canvas.drawCircle(Offset(x, cy), r + 4 + pulse * 5, halo);
        }
        canvas.drawCircle(
            Offset(x, cy), r + 1.5, Paint()..color = currentColor);
      } else if (isPast) {
        canvas.drawCircle(Offset(x, cy), r, Paint()..color = nodeColors[i]);
      } else {
        // Future = outline only.
        canvas.drawCircle(Offset(x, cy), r,
            Paint()..color = VColors.surface600);
        canvas.drawCircle(
          Offset(x, cy),
          r - 1.2,
          Paint()..color = VColors.surface800,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RailPainter old) =>
      old.progress != progress ||
      old.pulse != pulse ||
      old.currentColor != currentColor;
}
