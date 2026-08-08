import 'package:flutter/material.dart';

/// Swaps the active screen, sliding it in from the side the destination sits
/// on in the nav bar — tap Folder from Home and the folder comes in from the
/// right, tap back and it goes out the same way. Screens that aren't in the
/// bar (the planning flow) keep a plain rise-and-fade.
class ScreenSwitcher extends StatefulWidget {
  const ScreenSwitcher({super.key, required this.screen, required this.child});

  final String screen;
  final Widget child;

  @override
  State<ScreenSwitcher> createState() => _ScreenSwitcherState();
}

class _ScreenSwitcherState extends State<ScreenSwitcher> {
  /// The nav bar's destinations, left to right.
  static const List<String> _navOrder = ['areasMap', 'overview', 'folder'];

  late String _current = widget.screen;

  /// +1 when the last change moved right along the bar, -1 for left, 0 when
  /// either end of the change isn't a nav destination.
  double _direction = 0;

  @override
  void didUpdateWidget(covariant ScreenSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.screen == _current) return;

    final from = _navOrder.indexOf(_current);
    final to = _navOrder.indexOf(widget.screen);
    _direction = (from < 0 || to < 0) ? 0 : (to > from ? 1 : -1);
    _current = widget.screen;
  }

  @override
  Widget build(BuildContext context) {
    final direction = _direction;
    final sliding = direction != 0;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 340),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      // Both screens are opaque and full-bleed, so they can ride past each
      // other; the default builder would size the stack to one of them.
      layoutBuilder: (currentChild, previousChildren) => Stack(
        children: [
          ...previousChildren,
          ?currentChild,
        ],
      ),
      transitionBuilder: (child, animation) {
        // The outgoing child gets the same builder with a reversed animation,
        // so it has to leave towards the opposite edge from the one the new
        // screen arrives at.
        final incoming = child.key == ValueKey(widget.screen);
        final begin = sliding
            ? Offset(incoming ? direction : -direction, 0)
            : const Offset(0, 0.02);

        final slide = SlideTransition(
          position: Tween<Offset>(begin: begin, end: Offset.zero)
              .animate(animation),
          child: child,
        );
        // A full-width slide reads better solid; the subtle rise still wants
        // the fade to cover for how little it moves.
        return sliding ? slide : FadeTransition(opacity: animation, child: slide);
      },
      child: KeyedSubtree(key: ValueKey(widget.screen), child: widget.child),
    );
  }
}
