import 'package:flutter/material.dart';
import 'package:wave/widgets/horizontal_scroll_arrows.dart';

/// Horizontal scroll list with snap-to-card physics. Replaces the default
/// `ListView` for any horizontal carousel of fixed-width cards.
class SnapHorizontalList extends StatefulWidget {
  const SnapHorizontalList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.itemExtent,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
    this.spacing = 12,
    this.height,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double itemExtent;
  final EdgeInsets padding;
  final double spacing;
  final double? height;

  @override
  State<SnapHorizontalList> createState() => _SnapHorizontalListState();
}

class _SnapHorizontalListState extends State<SnapHorizontalList> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = HorizontalScrollArrows(
      controller: _scrollController,
      padding: EdgeInsets.symmetric(
        horizontal: widget.padding.horizontal / 4,
      ), // slightly offset
      child: ListView.separated(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: _SnapScrollPhysics(
          itemExtent: widget.itemExtent + widget.spacing,
        ),
        padding: widget.padding,
        itemCount: widget.itemCount,
        separatorBuilder: (_, _) => SizedBox(width: widget.spacing),
        itemBuilder: widget.itemBuilder,
      ),
    );
    if (widget.height == null) return view;
    return SizedBox(height: widget.height, child: view);
  }
}

class _SnapScrollPhysics extends ScrollPhysics {
  const _SnapScrollPhysics({required this.itemExtent, super.parent});

  final double itemExtent;

  @override
  _SnapScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _SnapScrollPhysics(itemExtent: itemExtent, parent: buildParent(ancestor));

  double _targetPixels(ScrollMetrics position, double velocity) {
    final raw = position.pixels + velocity * 0.18;
    final n = (raw / itemExtent).round();
    return (n * itemExtent).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final tol = toleranceFor(position);
    if ((velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final target = _targetPixels(position, velocity);
    if ((target - position.pixels).abs() < tol.distance) return null;
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: tol,
    );
  }

  @override
  bool get allowImplicitScrolling => false;
}
