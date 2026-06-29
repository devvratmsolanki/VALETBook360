import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/v_colors.dart';

/// Lightweight delivered-celebration overlay (doc §6.7: 600ms confetti-lite +
/// success haptic). Pure CustomPaint — no extra package. Disabled under
/// reduced motion by the caller (which shows a static success state instead).
class SuccessBurst extends StatefulWidget {
  const SuccessBurst({super.key, this.onComplete});
  final VoidCallback? onComplete;

  @override
  State<SuccessBurst> createState() => _SuccessBurstState();
}

class _SuccessBurstState extends State<SuccessBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..forward();

  final _rng = math.Random(7);
  late final List<_Spark> _sparks = List.generate(18, (_) {
    final a = _rng.nextDouble() * math.pi * 2;
    return _Spark(
      angle: a,
      speed: 80 + _rng.nextDouble() * 120,
      color: [
        VColors.statusReady,
        VColors.alertSuccess,
        VColors.brand400,
        VColors.contentStrong,
      ][_rng.nextInt(4)],
      size: 3 + _rng.nextDouble() * 4,
    );
  });

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onComplete?.call();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size.infinite,
                painter: _BurstPainter(_sparks, _c.value),
              ),
              Opacity(
                opacity: (1 - (_c.value - 0.3).clamp(0, 1) / 0.7).clamp(0, 1),
                child: Transform.scale(
                  scale: 0.6 + Curves.easeOutBack.transform(_c.value) * 0.6,
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: VColors.alertSuccess,
                    size: 96,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Spark {
  _Spark({
    required this.angle,
    required this.speed,
    required this.color,
    required this.size,
  });
  final double angle;
  final double speed;
  final Color color;
  final double size;
}

class _BurstPainter extends CustomPainter {
  _BurstPainter(this.sparks, this.t);
  final List<_Spark> sparks;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final eased = Curves.easeOut.transform(t);
    for (final s in sparks) {
      final d = s.speed * eased;
      final p = center + Offset(math.cos(s.angle) * d, math.sin(s.angle) * d);
      final paint = Paint()
        ..color = s.color.withValues(alpha: (1 - t).clamp(0, 1));
      canvas.drawCircle(p, s.size * (1 - t * 0.5), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) => old.t != t;
}
