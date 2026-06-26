import 'package:flutter/material.dart';
import '../theme/motion.dart';
import '../theme/v_colors.dart';
import '../theme/v_theme.dart';
import '../theme/v_tokens.dart';
import 'v_primary_button.dart';

/// `VEmptyState` (doc §6.9) — one per empty surface. Centered faint icon,
/// body-lg headline, caption hint, optional action.
class VEmptyState extends StatelessWidget {
  const VEmptyState({
    super.key,
    required this.icon,
    required this.headline,
    this.hint,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String headline;
  final String? hint;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(VSpace.x8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: VColors.contentFaint),
            const SizedBox(height: VSpace.x5),
            Text(
              headline,
              textAlign: TextAlign.center,
              style: VType.bodyLg.copyWith(color: VColors.contentDefault),
            ),
            if (hint != null) ...[
              const SizedBox(height: VSpace.x2),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: VType.caption,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: VSpace.x6),
              SizedBox(
                width: 220,
                child: VPrimaryButton(label: actionLabel!, onPressed: onAction),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// `VBanner` (doc §6.9) — persistent inline banner with an alert left edge.
/// Used for the login error state and load-error retry.
class VBanner extends StatelessWidget {
  const VBanner({
    super.key,
    required this.message,
    this.color = VColors.alertDanger,
    this.icon = Icons.error_outline_rounded,
    this.onRetry,
  });

  final String message;
  final Color color;
  final IconData icon;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: VSpace.x4,
          vertical: VSpace.x3,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(VRadius.md),
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: VSpace.x3),
            Expanded(
              child: Text(
                message,
                style: VType.body.copyWith(color: VColors.contentDefault),
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(width: VSpace.x2),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  minimumSize: const Size(VTarget.minTouch, VTarget.minTouch),
                  foregroundColor: color,
                ),
                child: Text('Retry', style: VType.label.copyWith(color: color)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shimmer primitive for `VCardSkeleton` (doc §6.9). 1200ms linear loop;
/// degrades to a static block under reduced motion.
class VShimmer extends StatefulWidget {
  const VShimmer({super.key, required this.child});
  final Widget child;

  @override
  State<VShimmer> createState() => _VShimmerState();
}

class _VShimmerState extends State<VShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final dx = bounds.width * (_c.value * 2 - 1);
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: const [
                VColors.surface700,
                VColors.surface600,
                VColors.surface700,
              ],
              stops: const [0.35, 0.5, 0.65],
              transform: _SlideGradient(dx),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.dx);
  final double dx;
  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(dx, 0, 0);
}

/// A single skeleton block.
class VSkeletonBox extends StatelessWidget {
  const VSkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.radius = VRadius.sm,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: VColors.surface700,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
