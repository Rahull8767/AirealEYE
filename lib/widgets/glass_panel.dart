import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:aerial_eye/core/constants/app_constants.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';

class GlassPanel extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final Color? color;
  final double blur;

  const GlassPanel({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.borderRadius,
    this.color,
    this.blur = 12.0,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius:
          borderRadius ?? BorderRadius.circular(AppConstants.radiusLarge),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          width: width,
          height: height,
          padding: padding ?? const EdgeInsets.all(AppConstants.paddingMedium),
          decoration: BoxDecoration(
            color: color ?? AppTheme.card.withOpacity(0.65),
            borderRadius:
                borderRadius ?? BorderRadius.circular(AppConstants.radiusLarge),
            border: Border.all(
              color: Colors.white.withOpacity(0.08),
              width: 1.0,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
