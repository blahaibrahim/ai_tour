import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'noise_texture.dart';

enum AppBackdropVariant {
  /// The default page ground: a barely-there warm wash.
  sky,

  /// Genuinely dark, for the during-tour screen whose header sits in white on
  /// top of it. Not "faint" like the others — see [_AppBackdropPalette.of].
  deep,

  /// Warm sand, for pages leaning on the secondary colour.
  warm,

  /// Both brand colours at once: fennec sand in one corner, compass blue in
  /// the other, with the cream paper holding the middle. Used by the first-run
  /// screens, which have no content of their own to carry the brand — the
  /// intro is mostly whitespace around one illustration, and the other
  /// variants leave it looking like an unfinished page.
  ///
  /// The neutral band is not decoration: it is where the title and body sit,
  /// and it is what keeps navy text at full contrast on a page whose corners
  /// are strongly coloured.
  duotone,
}

/// The app's page background: a faint gradient, a subtle grain, and a few
/// dotted travel trails.
///
/// This used to run two permanent animation controllers — a ten-second
/// gradient drift and a six-second horizontal sway — under every screen in the
/// app. They are gone. A background that moves competes with the content for
/// attention, and two always-on `AnimatedBuilder` rebuilds beneath scrolling
/// lists and a live map is a real cost for something nobody was looking at.
///
/// The trails replace that motion with something static that still reads as
/// "journey": dashed curves ending in a dot — the same visual language the
/// route map uses for a walking leg between two stops.
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({
    super.key,
    required this.child,
    this.variant = AppBackdropVariant.sky,
  });

  final Widget child;
  final AppBackdropVariant variant;

  @override
  Widget build(BuildContext context) {
    final palette = _AppBackdropPalette.of(variant);

    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: palette.begin,
                  end: palette.end,
                  colors: palette.gradient,
                  stops: palette.stops,
                ),
              ),
            ),
          ),

          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _DottedTrailsPainter(color: palette.trail),
              ),
            ),
          ),

          // Paper grain. Lighter than it was: at 0.25 it did most of the
          // texturing work, leaving no room for the trails to read.
          Positioned.fill(
            child: IgnorePointer(
              child: Image.memory(
                noiseTextureData,
                repeat: ImageRepeat.repeat,
                fit: BoxFit.none,
                opacity: const AlwaysStoppedAnimation(0.10),
              ),
            ),
          ),

          child,
        ],
      ),
    );
  }
}

/// The colours a variant paints with.
class _AppBackdropPalette {
  const _AppBackdropPalette({
    required this.gradient,
    required this.stops,
    required this.trail,
    this.begin = Alignment.topCenter,
    this.end = Alignment.bottomCenter,
  });

  final List<Color> gradient;
  final List<double> stops;

  /// Top-to-bottom for every variant but [AppBackdropVariant.duotone], which
  /// runs corner to corner so its two brand colours read as two corners rather
  /// than as two horizontal bands.
  final AlignmentGeometry begin;
  final AlignmentGeometry end;

  /// Trails are drawn in this, already at its final opacity.
  final Color trail;

  static _AppBackdropPalette of(AppBackdropVariant variant) => switch (variant) {
        // Faint on purpose: three stops within a few percent of each other, so
        // the page reads as warm paper rather than as a coloured wash.
        AppBackdropVariant.sky => _AppBackdropPalette(
            gradient: [
              AppTheme.surface,
              AppTheme.bg,
              AppTheme.secondarySoft.withValues(alpha: 0.55),
            ],
            stops: const [0.0, 0.55, 1.0],
            trail: AppTheme.compassBlue.withValues(alpha: 0.35),
          ),

        // The exception to "faint". The overview screen's header, points pill
        // and progress track are all white, and they are legible because this
        // is dark — softening it to match the others would silently break the
        // contrast on the one screen a traveller reads while walking.
        AppBackdropVariant.deep => const _AppBackdropPalette(
            gradient: [
              AppTheme.deepNavy,
              AppTheme.compassBlue,
              AppTheme.bg,
            ],
            stops: [0.0, 0.34, 1.0],
            trail: Color(0x66FFFFFF), // increased opacity to make dotted lines more apparent
          ),

        AppBackdropVariant.warm => _AppBackdropPalette(
            gradient: [
              AppTheme.surface,
              AppTheme.secondarySoft.withValues(alpha: 0.8),
              AppTheme.sand.withValues(alpha: 1.0),
            ],
            stops: const [0.0, 0.45, 1.0],
            trail: AppTheme.cocoa.withValues(alpha: 0.35),
          ),

        // Sand at the top, soft compass blue at the bottom, ramped so neither
        // the crossover nor the ends read as white.
        //
        // Two things this gets wrong if done the obvious way:
        //
        //  * **The axis.** A corner-to-corner gradient looks appealing but on a
        //    phone-shaped box the bottom-left corner projects only ~82% of the
        //    way along it, so the bottom edge ran from pale to blue and the
        //    page appeared to fade back to white at the bottom. The axis is
        //    near-vertical instead — tilted just enough to not look mechanical,
        //    which keeps the top and bottom edges within 5% of a single colour.
        //
        //  * **The crossover.** Sand and compass blue are on opposite sides of
        //    the wheel, so interpolating between them in sRGB drops through
        //    near-zero chroma — a wide, grey, washed-out middle, and a visible
        //    seam where warm flips to cool. The waypoints below are hand-picked
        //    rather than left to the lerp: chroma is given up gradually on the
        //    warm side and picked up again on the cool side, and the lightest
        //    point on the whole ramp is a tinted greige (#DED6C8, ~84% L)
        //    rather than paper. That is why these are literals and not theme
        //    tokens — they are waypoints on a hue path, not semantic colours.
        AppBackdropVariant.duotone => const _AppBackdropPalette(
            begin: Alignment(-0.35, -1),
            end: Alignment(0.35, 1),
            gradient: [
              AppTheme.sand, // #F8D59B — the token, exactly
              Color(0xFFF5D6A6),
              Color(0xFFEDD7B8),
              Color(0xFFDED6C8), // the warm/cool crossover
              Color(0xFFCBD2E0),
              Color(0xFFB5C3E0),
              Color(0xFFA5B7DA),
              Color(0xFF9CB0D6),
            ],
            stops: [0.0, 0.20, 0.38, 0.50, 0.60, 0.74, 0.88, 1.0],
            // Navy rather than either brand colour: the trails cross the whole
            // ramp, and a blue trail vanishes into the bottom while a warm one
            // vanishes into the top.
            trail: Color(0x2E14254A), // AppTheme.ink @ 18%
          ),
      };
}

/// Dashed travel trails, each ending in a destination dot.
///
/// Drawn rather than shipped as an SVG asset: the project has no `flutter_svg`
/// dependency, and a painter is tintable per variant (the deep backdrop needs
/// light trails, the others dark), resolution-independent, and re-lays itself
/// out for any screen size — none of which a fixed asset does.
///
/// The dash rhythm deliberately matches the route map's walk legs, so the
/// decoration and the data speak the same language.
class _DottedTrailsPainter extends CustomPainter {
  const _DottedTrailsPainter({required this.color});

  final Color color;

  /// Trails in normalised coordinates: start, two control points, end.
  ///
  /// Fixed rather than random, so the background is identical on every
  /// rebuild — a pattern that reshuffles when the keyboard opens looks like a
  /// glitch. They sit toward the edges, where page content is thinnest, and
  /// several run off-canvas so the page feels like a window onto something
  /// larger rather than a box with four arcs in it.
  static const List<List<Offset>> _trails = [
    [Offset(-0.05, 0.30), Offset(0.18, 0.14), Offset(0.10, 0.02), Offset(0.30, -0.02)],
    [Offset(0.62, 0.10), Offset(0.80, 0.02), Offset(1.02, 0.16), Offset(0.88, 0.26)],
    [Offset(-0.02, 0.72), Offset(0.30, 0.62), Offset(0.42, 0.92), Offset(0.72, 0.80)],
    [Offset(0.78, 0.94), Offset(0.90, 0.86), Offset(0.94, 1.02), Offset(1.05, 0.92)],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    final dot = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (final trail in _trails) {
      final start = _scale(trail[0], size);
      final c1 = _scale(trail[1], size);
      final c2 = _scale(trail[2], size);
      final end = _scale(trail[3], size);

      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);

      canvas.drawPath(_dashed(path), stroke);
      canvas.drawCircle(end, 3.2, dot);
    }
  }

  static Offset _scale(Offset normalised, Size size) =>
      Offset(normalised.dx * size.width, normalised.dy * size.height);

  /// Converts a continuous path into dashes.
  ///
  /// Flutter has no dashed-stroke paint mode, so the path is walked with
  /// `PathMetrics` and rebuilt as alternating extracted segments.
  static Path _dashed(Path source, {double dash = 5, double gap = 6}) {
    final result = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dash, metric.length);
        result.addPath(metric.extractPath(distance, next), Offset.zero);
        distance = next + gap;
      }
    }
    return result;
  }

  @override
  bool shouldRepaint(_DottedTrailsPainter old) => old.color != color;
}
