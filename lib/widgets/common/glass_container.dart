import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;

class GlassContainer extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;

  const GlassContainer({
    super.key,
    required this.child,
    this.blur = 20.0,
    this.opacity = 0.05,
    this.borderRadius,
    this.padding,
    this.margin,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    // Keep this small adapter so existing screens retain their layout while
    // using the package's shader-based liquid glass renderer.
    final radius = borderRadius?.topLeft.x ?? 20.0;
    return liquid.GlassContainer(
      margin: margin,
      width: width,
      height: height,
      padding: padding,
      useOwnLayer: true,
      quality: liquid.GlassQuality.standard,
      shape: liquid.LiquidRoundedSuperellipse(borderRadius: radius),
      child: child,
    );
  }
}
