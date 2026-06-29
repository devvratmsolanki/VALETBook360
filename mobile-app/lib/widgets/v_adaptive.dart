import 'package:flutter/widgets.dart';

import '../theme/v_breakpoints.dart';

/// Responsive layout primitives shared by every screen.
///
/// Before this existed each screen re-implemented the same
/// `Center > ConstrainedBox > SingleChildScrollView` boilerplate with a
/// hand-picked `maxWidth`, which drifted screen-to-screen and never adapted past
/// "narrow centered column". These widgets centralize the rules so responsive
/// behaviour is consistent and tunable from one place.

/// Constrains [child] to a readable/centered max width and applies the
/// viewport-aware [VResponsive.pagePadding] gutter. On compact screens it's a
/// full-bleed padded column; on wide screens the content centers instead of
/// stretching edge-to-edge.
///
/// Pass [maxWidth] to override the default cap (defaults to
/// [VResponsive.dashboardMaxWidth] for dashboard-style content; pass
/// `context.readableMaxWidth` for forms / reading flows).
class VBoundedContent extends StatelessWidget {
  const VBoundedContent({
    super.key,
    required this.child,
    this.maxWidth,
    this.padding,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double? maxWidth;
  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth ?? context.dashboardMaxWidth,
        ),
        child: Padding(
          padding: padding ?? context.pagePadding,
          child: child,
        ),
      ),
    );
  }
}

/// A responsive grid that reflows its [children] from a single column on compact
/// screens to N columns on wider ones, sizing each cell to an equal share of the
/// available width. Replaces the common "Column of cards on every size" pattern
/// that wastes horizontal space on tablet/desktop.
///
/// [columnsFor] defaults to 1/2/2/3 across compact/medium/expanded/large; pass a
/// custom resolver for screens that want a different cadence.
class VResponsiveGrid extends StatelessWidget {
  const VResponsiveGrid({
    super.key,
    required this.children,
    this.spacing = 16,
    this.runSpacing = 16,
    this.columnsFor,
  });

  final List<Widget> children;
  final double spacing;
  final double runSpacing;
  final int Function(VWindowClass windowClass)? columnsFor;

  int _defaultColumns(VWindowClass w) {
    switch (w) {
      case VWindowClass.compact:
        return 1;
      case VWindowClass.medium:
      case VWindowClass.expanded:
        return 2;
      case VWindowClass.large:
        return 3;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final columns =
        (columnsFor ?? _defaultColumns)(context.windowClass).clamp(1, children.length);

    // One column → a plain Column (no width math, no wasted Wrap run logic).
    if (columns == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: runSpacing),
            children[i],
          ],
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalSpacing = spacing * (columns - 1);
        final cellWidth = (constraints.maxWidth - totalSpacing) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: [
            for (final child in children)
              SizedBox(width: cellWidth, child: child),
          ],
        );
      },
    );
  }
}

/// Two-pane master/detail layout that collapses to a single pane on compact
/// screens. On wide viewports [master] and [detail] sit side-by-side at the
/// given [masterFlex]/[detailFlex] ratio; on phones only [master] (or [detail]
/// when [showDetailOnCompact]) is shown so the caller can push the detail as a
/// route instead.
class VMasterDetail extends StatelessWidget {
  const VMasterDetail({
    super.key,
    required this.master,
    required this.detail,
    this.masterFlex = 2,
    this.detailFlex = 3,
    this.gap = 24,
    this.showDetailOnCompact = false,
  });

  final Widget master;
  final Widget detail;
  final int masterFlex;
  final int detailFlex;
  final double gap;
  final bool showDetailOnCompact;

  @override
  Widget build(BuildContext context) {
    if (!context.isExpanded) {
      return showDetailOnCompact ? detail : master;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: masterFlex, child: master),
        SizedBox(width: gap),
        Expanded(flex: detailFlex, child: detail),
      ],
    );
  }
}
