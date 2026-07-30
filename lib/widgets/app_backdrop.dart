import 'package:flutter/material.dart';
import '../theme.dart';
import 'noise_texture.dart';

enum AppBackdropVariant {
  /// Cream up from the bottom into compass blue — the default page ground.
  sky,

  /// Runs all the way into the icon's deep navy, for pages that want more
  /// weight at the top.
  deep,

  /// Warm sand and brass, for pages that lean on the secondary color.
  warm,
}

/// A purely code-based gradient page background with a slow drift.
/// Includes an embedded lightweight noise texture to provide a grainy feel.
///
/// Colors come from the app icon: the fennec's sand fur at the bottom rising
/// into the compass blue / navy field at the top. The band where they meet
/// eases up and down on a long loop, so the blue swells while the sand pulls
/// back and then the other way round — slow enough to read as light changing
/// rather than as an animation.
class AppBackdrop extends StatefulWidget {
  final Widget child;
  final AppBackdropVariant variant;

  const AppBackdrop({
    super.key,
    required this.child,
    this.variant = AppBackdropVariant.sky,
  });

  @override
  State<AppBackdrop> createState() => _AppBackdropState();
}

class _AppBackdropState extends State<AppBackdrop>
    with SingleTickerProviderStateMixin {
  /// One full breath in, one out. Long on purpose — at anything brisker the
  /// page starts to shimmer under the content.
  static const Duration _driftPeriod = Duration(seconds: 16);

  /// Range the meeting point travels, as a fraction of page height.
  static const double _driftLow = 0.30;
  static const double _driftHigh = 0.52;

  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: _driftPeriod,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  List<Color> get _gradientColors => switch (widget.variant) {
        AppBackdropVariant.sky => [
            Colors.white,
            AppTheme.sand,
            AppTheme.compassBlue.withOpacity(0.85),
          ],
        AppBackdropVariant.deep => [
            Colors.white,
            AppTheme.compassBlue.withOpacity(0.8),
            AppTheme.deepNavy,
          ],
        AppBackdropVariant.warm => [
            Colors.white,
            AppTheme.secondarySoft,
            AppTheme.amber,
          ],
      };

  @override
  Widget build(BuildContext context) {
    final colors = _gradientColors;

    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _drift,
              builder: (context, _) {
                final t = Curves.easeInOut.transform(_drift.value);
                final meeting = _driftLow + (_driftHigh - _driftLow) * t;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: colors,
                      stops: [0.0, meeting, 1.0],
                    ),
                  ),
                );
              },
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
          widget.child,
        ],
      ),
    );
  }
}
