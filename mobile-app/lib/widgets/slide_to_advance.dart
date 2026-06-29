import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/motion.dart';
import '../theme/v_colors.dart';
import '../theme/v_theme.dart';
import '../theme/v_tokens.dart';

/// The driver's signature direct-manipulation control (doc §7.5 / §9.3).
///
/// A thumb-zone track: drag the knob right; the track fills the target `status`
/// hue as dragged; haptic at the 75% threshold; commit on release past
/// threshold. Tapping the knob (or pressing the whole track when reduced-motion
/// makes dragging awkward) also commits — keeps it operable for everyone.
class SlideToAdvance extends StatefulWidget {
  const SlideToAdvance({
    super.key,
    required this.label,
    required this.fillColor,
    required this.onCommit,
    this.busy = false,
    this.enabled = true,
  });

  final String label;
  final Color fillColor;
  final Future<void> Function() onCommit;
  final bool busy;
  final bool enabled;

  @override
  State<SlideToAdvance> createState() => _SlideToAdvanceState();
}

class _SlideToAdvanceState extends State<SlideToAdvance>
    with SingleTickerProviderStateMixin {
  static const double _height = 64;
  static const double _threshold = 0.75;

  double _drag = 0; // 0..1
  bool _passedThreshold = false;
  late final AnimationController _settle;

  @override
  void initState() {
    super.initState();
    // Create the controller eagerly while mounted. A `late final = ...` lazy
    // initializer would construct it on FIRST access — which, for a slider the
    // user never dragged, is `_settle.dispose()` below. Creating a Ticker during
    // dispose() does an unsafe ancestor lookup on a deactivated widget ("Looking
    // up a deactivated widget's ancestor is unsafe") and throws when the mission
    // card unmounts (e.g. the AnimatedSwitcher swapping cards on a status change).
    _settle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d, double maxTravel) {
    if (!widget.enabled || widget.busy) return;
    final next = (_drag + d.primaryDelta! / maxTravel).clamp(0.0, 1.0);
    setState(() => _drag = next);
    if (!_passedThreshold && next >= _threshold) {
      _passedThreshold = true;
      HapticFeedback.selectionClick(); // threshold reached (doc §6.8)
    } else if (_passedThreshold && next < _threshold) {
      _passedThreshold = false;
    }
  }

  Future<void> _onDragEnd() async {
    if (_drag >= _threshold) {
      await _commit();
    } else {
      _animateBack();
    }
  }

  void _animateBack() {
    final start = _drag;
    _settle.reset();
    final anim = Tween<double>(begin: start, end: 0).animate(
      CurvedAnimation(parent: _settle, curve: Curves.easeOut),
    );
    anim.addListener(() => setState(() => _drag = anim.value));
    _settle.forward();
    _passedThreshold = false;
  }

  Future<void> _commit() async {
    setState(() => _drag = 1);
    HapticFeedback.mediumImpact(); // state advance (doc §6.8)
    await widget.onCommit();
    // Parent rebuilds with the next mission/state; reset locally as a fallback.
    if (mounted) {
      setState(() {
        _drag = 0;
        _passedThreshold = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && !widget.busy;
    final reduced = Motion.reduced(context);

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      hint: 'Double tap to confirm, or slide right',
      onTap: enabled ? _commit : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          const knob = _height - 8;
          final maxTravel = (w - knob - 8).clamp(1.0, double.infinity);
          final knobX = 4 + _drag * maxTravel;

          return GestureDetector(
            onHorizontalDragUpdate: reduced
                ? null
                : (d) => _onDragUpdate(d, maxTravel),
            onHorizontalDragEnd: reduced ? null : (_) => _onDragEnd(),
            // Reduced-motion / a11y: tapping the track commits directly.
            onTap: reduced && enabled ? _commit : null,
            child: Container(
              height: _height,
              decoration: BoxDecoration(
                color: VColors.surface800,
                borderRadius: BorderRadius.circular(VRadius.full),
                border: Border.all(color: VColors.surface600, width: 1),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Fill that tracks the drag.
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 60),
                      width: knobX + knob / 2,
                      decoration: BoxDecoration(
                        color: widget.fillColor.withValues(
                          alpha: 0.18 + 0.22 * _drag,
                        ),
                        borderRadius: BorderRadius.circular(VRadius.full),
                      ),
                    ),
                  ),
                  // Label.
                  Padding(
                    padding: const EdgeInsets.only(left: knob + 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Opacity(
                        opacity: enabled ? (1 - _drag * 0.6) : 0.4,
                        child: Text(
                          widget.busy ? 'Working…' : widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: VType.label.copyWith(
                            color: VColors.contentStrong,
                            fontSize: 14,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Knob.
                  Positioned(
                    left: knobX,
                    child: Container(
                      width: knob,
                      height: knob,
                      decoration: BoxDecoration(
                        color: enabled ? widget.fillColor : VColors.surface600,
                        shape: BoxShape.circle,
                        boxShadow: enabled
                            ? [
                                BoxShadow(
                                  color: widget.fillColor.withValues(alpha: 0.4),
                                  blurRadius: 12,
                                ),
                              ]
                            : null,
                      ),
                      child: widget.busy
                          ? Padding(
                              padding: const EdgeInsets.all(16),
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                valueColor: AlwaysStoppedAnimation(
                                    VColors.contentOnAccent),
                              ),
                            )
                          : Icon(
                              _drag >= _threshold
                                  ? Icons.check_rounded
                                  : Icons.chevron_right_rounded,
                              color: VColors.contentOnAccent,
                              size: 26,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
