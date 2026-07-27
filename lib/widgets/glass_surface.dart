import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme.dart';

/// Which side of the palette a [GlassSurface] tints toward — `light` for
/// chrome sitting over the app's warm page background, `dark` for chrome
/// sitting over photos/maps where a light tint would wash out.
enum GlassTint { light, dark }

/// Apple-style frosted glass: blurs whatever is behind it, tints it
/// translucently, and adds a thin bright edge + soft sheen so it reads as a
/// physical pane of glass rather than a flat tinted rectangle. Used for the
/// app's chrome (nav bar, cards, buttons) so surfaces pick up the color of
/// whatever is behind them instead of sitting on top as flat white shapes.
class GlassSurface extends StatelessWidget {
  final Widget? child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final double blur;
  final GlassTint tint;
  final List<BoxShadow>? boxShadow;
  final AlignmentGeometry? alignment;

  const GlassSurface({
    super.key,
    this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(AppTheme.radiusLg)),
    this.padding,
    this.blur = 20,
    this.tint = GlassTint.light,
    this.boxShadow,
    this.alignment,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = tint == GlassTint.dark;
    final base = isDark ? AppTheme.ink : Colors.white;

    return Container(
      padding: padding,
      alignment: alignment,
      decoration: BoxDecoration(
        color: base,
        borderRadius: borderRadius,
        boxShadow: boxShadow ?? AppTheme.shadowSm,
        border: Border.all(color: isDark ? Colors.white24 : AppTheme.divider, width: 1),
      ),
      child: child,
    );
  }
}
