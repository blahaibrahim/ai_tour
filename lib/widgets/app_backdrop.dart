import 'package:flutter/material.dart';
import '../theme.dart';
import 'noise_texture.dart';

enum AppBackdropVariant {
  orange,
  orangeAndBlue,
  teal,
}

/// A purely code-based gradient page background with animated color blobs.
/// Includes an embedded lightweight noise texture to provide a grainy feel.
/// Allows for smooth animations and transitions.
class AppBackdrop extends StatelessWidget {
  final Widget child;
  final AppBackdropVariant variant;

  const AppBackdrop({
    super.key,
    required this.child,
    this.variant = AppBackdropVariant.orange,
  });

  @override
  Widget build(BuildContext context) {
    // Define gradient colors based on the selected variant
    List<Color> gradientColors;

    switch (variant) {
      case AppBackdropVariant.orange:
        gradientColors = [Colors.white, AppTheme.bgTop, AppTheme.accent.withOpacity(0.85)];
        break;
      case AppBackdropVariant.orangeAndBlue:
        gradientColors = [Colors.white, AppTheme.accent.withOpacity(0.8), AppTheme.duskDeep];
        break;
      case AppBackdropVariant.teal:
        gradientColors = [Colors.white, AppTheme.tealSoft, AppTheme.teal];
        break;
    }

    return SizedBox.expand(
      child: Stack(
        children: [
          // Base Rectangle Gradient fading to white at the top
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 800),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: gradientColors,
                  stops: const [0.0, 0.4, 1.0],
                ),
              ),
            ),
          ),

        // Grainy texture overlay using embedded base64 Image.memory (No performance penalty)
        Positioned.fill(
          child: IgnorePointer(
            child: Image.memory(
              noiseTextureData,
              repeat: ImageRepeat.repeat,
              fit: BoxFit.none,
              opacity: const AlwaysStoppedAnimation(0.25), // reduced noise intensity
            ),
          ),
        ),

        // Content
        child,
      ],
    ));
  }
}

class _AnimatedBlob extends StatelessWidget {
  final double size;
  final Color color;
  final double opacity;

  const _AnimatedBlob({
    required this.size,
    required this.color,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(begin: color, end: color),
        duration: const Duration(milliseconds: 1200),
        curve: Curves.easeInOut,
        builder: (context, animatedColor, child) {
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  (animatedColor ?? color).withOpacity(opacity),
                  (animatedColor ?? color).withOpacity(0),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

