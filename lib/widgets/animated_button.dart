import 'package:flutter/material.dart';

class AnimatedButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color? color;
  final BorderRadius? borderRadius;
  final double scaleFactor;

  const AnimatedButton({
    super.key,
    required this.child,
    this.onTap,
    this.color,
    this.borderRadius,
    this.scaleFactor = 0.94,
  });

  @override
  State<AnimatedButton> createState() => _AnimatedButtonState();
}

class _AnimatedButtonState extends State<AnimatedButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      lowerBound: 0.0,
      upperBound: 1.0 - widget.scaleFactor,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown: (_) {
          if (widget.onTap != null) _controller.forward();
        },
        onTapUp: (_) {
          if (widget.onTap != null) {
            _controller.reverse();
            widget.onTap?.call();
          }
        },
        onTapCancel: () {
          if (widget.onTap != null) _controller.reverse();
        },
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final scale = 1.0 - _controller.value + (_isHovered && widget.onTap != null ? 0.02 : 0.0);
            return Transform.scale(
              scale: scale,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  borderRadius: widget.borderRadius ?? BorderRadius.circular(16),
                  boxShadow: _isHovered && widget.onTap != null
                      ? [
                          BoxShadow(
                            color: (widget.color ?? Theme.of(context).primaryColor).withOpacity(0.3),
                            blurRadius: 10,
                            spreadRadius: 1,
                          )
                        ]
                      : [],
                ),
                child: widget.child,
              ),
            );
          },
        ),
      ),
    );
  }
}
