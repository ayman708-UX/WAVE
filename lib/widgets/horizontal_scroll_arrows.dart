import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class HorizontalScrollArrows extends StatefulWidget {
  final Widget child;
  final ScrollController controller;
  final double arrowSize;
  final EdgeInsetsGeometry padding;

  const HorizontalScrollArrows({
    super.key,
    required this.child,
    required this.controller,
    this.arrowSize = 40.0,
    this.padding = EdgeInsets.zero,
  });

  @override
  State<HorizontalScrollArrows> createState() => _HorizontalScrollArrowsState();
}

class _HorizontalScrollArrowsState extends State<HorizontalScrollArrows> {
  bool _canScrollLeft = false;
  bool _canScrollRight = false;
  bool _isDesktop = false;

  @override
  void initState() {
    super.initState();
    _isDesktop =
        kIsWeb ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;

    widget.controller.addListener(_updateScrollButtons);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateScrollButtons();
    });
  }

  @override
  void didUpdateWidget(HorizontalScrollArrows oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_updateScrollButtons);
      widget.controller.addListener(_updateScrollButtons);
      _updateScrollButtons();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateScrollButtons);
    super.dispose();
  }

  void _updateScrollButtons() {
    if (!widget.controller.hasClients) return;

    final position = widget.controller.position;
    final canScrollLeft = position.pixels > position.minScrollExtent;
    final canScrollRight = position.pixels < position.maxScrollExtent;

    if (canScrollLeft != _canScrollLeft || canScrollRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = canScrollLeft;
        _canScrollRight = canScrollRight;
      });
    }
  }

  void _scrollLeft() {
    if (!widget.controller.hasClients) return;
    final position = widget.controller.position;
    final target = (position.pixels - 300).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    widget.controller.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollRight() {
    if (!widget.controller.hasClients) return;
    final position = widget.controller.position;
    final target = (position.pixels + 300).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    widget.controller.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isDesktop) {
      return widget.child;
    }

    return Stack(
      children: [
        widget.child,
        if (_canScrollLeft)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Padding(
              padding: widget.padding,
              child: Center(
                child: _ArrowButton(
                  icon: Icons.chevron_left,
                  onPressed: _scrollLeft,
                  size: widget.arrowSize,
                ),
              ),
            ),
          ),
        if (_canScrollRight)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Padding(
              padding: widget.padding,
              child: Center(
                child: _ArrowButton(
                  icon: Icons.chevron_right,
                  onPressed: _scrollRight,
                  size: widget.arrowSize,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final double size;

  const _ArrowButton({
    required this.icon,
    required this.onPressed,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon),
        onPressed: onPressed,
        iconSize: size * 0.6,
        constraints: BoxConstraints(minWidth: size, minHeight: size),
        splashRadius: size * 0.6,
        padding: EdgeInsets.zero,
      ),
    );
  }
}
