import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// The row of mode names that sits just above a camera shutter, swiped
/// sideways to change what the shutter does.
///
/// Shaped after the phone's own camera — photo, video, portrait — because that
/// is where the gesture was learnt. A segmented control would say the same
/// thing, but next to a shutter button people reach for the swipe first, and
/// finding it there means the second mode is discovered rather than hunted
/// for. Labels are tappable too, for anyone who doesn't.
class CameraModeSelector extends StatefulWidget {
  const CameraModeSelector({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.enabled = true,
  });

  /// Mode names, in the order they are swiped through. Rendered upper-case.
  final List<String> labels;

  /// Index of the mode currently in effect.
  final int index;

  final ValueChanged<int> onChanged;

  /// False while the shutter is busy, so a mode can't change under a capture
  /// that is already running.
  final bool enabled;

  @override
  State<CameraModeSelector> createState() => _CameraModeSelectorState();
}

class _CameraModeSelectorState extends State<CameraModeSelector> {
  /// Narrow enough that the neighbouring modes stay visible on either side —
  /// the whole point of the strip is that you can see there is somewhere else
  /// to go.
  static const double _viewportFraction = 0.4;

  late final PageController _controller = PageController(
    initialPage: widget.index,
    viewportFraction: _viewportFraction,
  );

  /// Live scroll position, so labels warm up and grow as they are dragged
  /// towards the centre instead of changing colour once the swipe lands.
  late double _page = widget.index.toDouble();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    final page = _controller.page;
    if (page != null && page != _page) setState(() => _page = page);
  }

  @override
  void didUpdateWidget(covariant CameraModeSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The mode is owned by the camera screen, so it can also change from
    // outside this strip; follow it rather than keeping a second copy that
    // could drift. After a swipe the controller is already there, which is
    // what the page check skips — animating to where we are would fight the
    // settling scroll.
    if (widget.index != oldWidget.index &&
        _controller.hasClients &&
        _controller.page?.round() != widget.index) {
      _controller.animateToPage(
        widget.index,
        duration: AppTheme.motionBase,
        curve: AppTheme.motionCurve,
      );
    }
  }

  void _select(int index) {
    if (index == widget.index) return;
    _controller.animateToPage(
      index,
      duration: AppTheme.motionBase,
      curve: AppTheme.motionCurve,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: PageView.builder(
        controller: _controller,
        itemCount: widget.labels.length,
        physics: widget.enabled
            ? const PageScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        onPageChanged: (index) {
          HapticFeedback.selectionClick();
          widget.onChanged(index);
        },
        itemBuilder: (context, index) {
          // 0 when this label is centred, 1 once it is a full page away.
          final distance = (index - _page).abs().clamp(0.0, 1.0);

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.enabled ? () => _select(index) : null,
            child: Center(
              child: Transform.scale(
                scale: 1 - distance * 0.12,
                child: Text(
                  widget.labels[index].toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                    color: Color.lerp(
                      AppTheme.sand,
                      Colors.white.withValues(alpha: 0.55),
                      distance,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
