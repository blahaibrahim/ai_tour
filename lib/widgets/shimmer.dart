import 'package:flutter/material.dart';
import '../theme.dart';

/// A soft skeleton placeholder with a sweeping highlight — used while
/// network images (the app's only real loading moments) are in flight.
class ShimmerBox extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadius borderRadius;

  const ShimmerBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = BorderRadius.zero,
  });

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: Alignment(-1.8 + 3.6 * t, -0.3),
              end: Alignment(-0.8 + 3.6 * t, 0.3),
              colors: const [
                AppTheme.surfaceAlt,
                AppTheme.divider,
                AppTheme.surfaceAlt,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Fills the space it's given — for use inside loading builders where the
/// surrounding widget (Image, etc.) is already sized by its parent.
class ShimmerFill extends StatelessWidget {
  const ShimmerFill({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand(child: ShimmerBox());
  }
}
