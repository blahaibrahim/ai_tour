import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

/// The app icon's brass compass, redrawn as the app's loading indicator.
///
/// The housing (bail, rim, blue face) stays put while the needle sweeps —
/// accelerating away and easing to a stop once per revolution, the way a real
/// needle hunts for north. Flat fills only, matching the rest of the app.
class CompassSpinner extends StatefulWidget {
  final double size;

  /// Duration of one full needle revolution.
  final Duration period;

  const CompassSpinner({
    super.key,
    this.size = 64,
    this.period = const Duration(milliseconds: 1600),
  });

  @override
  State<CompassSpinner> createState() => _CompassSpinnerState();
}

class _CompassSpinnerState extends State<CompassSpinner> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          // easeInOutCubic is flat at both ends, so the sweep loops seamlessly
          // while still reading as a swing-and-settle rather than a spin.
          final turns = Curves.easeInOutCubic.transform(_controller.value);
          return CustomPaint(
            painter: _CompassPainter(angle: turns * 2 * math.pi),
          );
        },
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  /// Needle heading, in radians clockwise from straight up.
  final double angle;

  const _CompassPainter({required this.angle});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    // The bail (the little hanging loop) sits above the housing, so the
    // housing is nudged down to keep the whole compass optically centered.
    final r = s * 0.42;
    final center = Offset(size.width / 2, size.height / 2 + s * 0.05);

    Paint fill(Color color) => Paint()
      ..style = PaintingStyle.fill
      ..color = color;
    Paint line(Color color, double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color;

    // Bail — a small open ring poking out of the top of the case. Drawn as a
    // stroke so whatever is behind the spinner shows through the loop.
    final bailCenter = Offset(center.dx, center.dy - r * 1.02);
    final bailR = s * 0.058;
    canvas.drawCircle(bailCenter, bailR, line(AppTheme.amber, s * 0.042));
    canvas.drawCircle(bailCenter, bailR + s * 0.021, line(AppTheme.cocoa, s * 0.016));
    canvas.drawCircle(bailCenter, bailR - s * 0.021, line(AppTheme.cocoa, s * 0.016));

    // Brass case.
    canvas.drawCircle(center, r, fill(AppTheme.amber));
    canvas.drawCircle(center, r, line(AppTheme.cocoa, s * 0.032));

    // Blue face, inset so the brass reads as a rim.
    final faceR = r * 0.76;
    canvas.drawCircle(center, faceR, fill(AppTheme.compassBlue));
    canvas.drawCircle(center, faceR, line(AppTheme.cocoa.withOpacity(0.55), s * 0.022));

    // Needle — a slim lens split down its long axis: cream on the leading
    // side, brass on the trailing side, exactly as in the icon.
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final tip = faceR * 0.88;
    final waist = faceR * 0.20;
    // Control points sit at 2x the waist so each half bulges widest at the
    // pivot, giving the needle its lens silhouette.
    final leading = Path()
      ..moveTo(0, -tip)
      ..quadraticBezierTo(-waist * 2, 0, 0, tip)
      ..close();
    final trailing = Path()
      ..moveTo(0, -tip)
      ..quadraticBezierTo(waist * 2, 0, 0, tip)
      ..close();

    final needleEdge = line(AppTheme.cocoa.withOpacity(0.75), s * 0.016);
    canvas.drawPath(leading, fill(AppTheme.cream));
    canvas.drawPath(trailing, fill(AppTheme.amber));
    canvas.drawPath(leading, needleEdge);
    canvas.drawPath(trailing, needleEdge);

    canvas.restore();

    // Pivot pin.
    canvas.drawCircle(center, s * 0.026, fill(AppTheme.cocoa));
  }

  @override
  bool shouldRepaint(_CompassPainter oldDelegate) => oldDelegate.angle != angle;
}
