import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/pressable_scale.dart';
import 'onboarding_content.dart';
import 'widgets/onboarding_page.dart';
import 'widgets/page_dots.dart';

/// The first-run intro: one slide per thing the app does, with a skip out of
/// every one of them.
///
/// The flow owns no persistence and no navigation of its own — it reports
/// "done" through [onFinish] and lets the caller decide what that means. That
/// is what lets the same widget serve both the first launch (where finishing
/// leads to the login screen) and the Settings "Replay intro" entry (where it
/// just pops).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onFinish,
    this.finishLabel = 'Get started',
  });

  /// Called once, whether the traveller read every page or skipped from the
  /// first — both mean "I am done with this".
  final VoidCallback onFinish;

  /// The last page's primary button. "Get started" on first launch; the
  /// replay-from-Settings caller passes "Done".
  final String finishLabel;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  /// Guards against [widget.onFinish] firing twice — a fast double-tap on
  /// "Get started" is otherwise two calls, and on first launch that is two
  /// attempts to swap the whole app out from under this widget.
  bool _finished = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLast => _index == onboardingPages.length - 1;

  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onFinish();
  }

  void _goTo(int index) {
    HapticFeedback.selectionClick();
    _controller.animateToPage(
      index,
      duration: AppTheme.motionBase,
      curve: AppTheme.motionCurve,
    );
  }

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    _goTo(_index + 1);
  }

  void _back() => _goTo(_index - 1);

  @override
  Widget build(BuildContext context) {
    final page = onboardingPages[_index];

    return PopScope(
      // System back walks the flow backwards instead of leaving it. Only the
      // first page can be popped, and on first launch there is nothing behind
      // it to pop to anyway.
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: AppBackdrop(
          variant: AppBackdropVariant.duotone,
          child: SafeArea(
            child: Column(
              children: [
                _TopBar(
                  showBack: _index > 0,
                  showSkip: !_isLast,
                  onBack: _back,
                  onSkip: _finish,
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: onboardingPages.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) {
                      final content = onboardingPages[i];
                      return OnboardingPage(
                        key: ValueKey(content.id),
                        content: content,
                      );
                    },
                  ),
                ),
                _BottomBar(
                  index: _index,
                  count: onboardingPages.length,
                  tint: page.tint,
                  label: _isLast ? widget.finishLabel : 'Next',
                  isLast: _isLast,
                  onNext: _next,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Back and Skip sit over the sand end of the duotone backdrop, where the
/// app's grey secondary colour does not carry enough contrast. Navy at 72%
/// measures 5.2:1 there — still visibly quieter than the page's own text,
/// which runs at full ink.
const Color _chromeColor = Color(0xB814254A); // AppTheme.ink @ 72%

/// Back on the left, Skip on the right — both fade rather than disappear, so
/// the row never changes height and the pages below never shift.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.showBack,
    required this.showSkip,
    required this.onBack,
    required this.onSkip,
  });

  final bool showBack;
  final bool showSkip;
  final VoidCallback onBack;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppTheme.minTapTarget + AppTheme.space2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.space3),
        child: Row(
          children: [
            _Fade(
              visible: showBack,
              child: PressableScale(
                onTap: onBack,
                child: SizedBox(
                  width: AppTheme.minTapTarget,
                  height: AppTheme.minTapTarget,
                  child: Icon(Icons.arrow_back_rounded, color: _chromeColor),
                ),
              ),
            ),
            const Spacer(),
            _Fade(
              visible: showSkip,
              child: TextButton(
                onPressed: onSkip,
                style: TextButton.styleFrom(
                  foregroundColor: _chromeColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.space4,
                    vertical: AppTheme.space3,
                  ),
                ),
                child: const Text('Skip'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dots on the left, the advance button on the right.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.index,
    required this.count,
    required this.tint,
    required this.label,
    required this.isLast,
    required this.onNext,
  });

  final int index;
  final int count;
  final Color tint;
  final String label;
  final bool isLast;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space6,
        AppTheme.space4,
        AppTheme.space6,
        AppTheme.space6,
      ),
      child: Row(
        children: [
          PageDots(count: count, index: index, color: tint),
          const Spacer(),
          ElevatedButton(
            onPressed: onNext,
            style: ElevatedButton.styleFrom(
              backgroundColor: tint,
              foregroundColor: AppTheme.onAccent,
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.space6,
                vertical: AppTheme.space4,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label),
                const SizedBox(width: 6),
                Icon(
                  isLast ? Icons.check_rounded : Icons.arrow_forward_rounded,
                  size: 18,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Fades a control out and stops it taking taps, without removing it from the
/// layout.
class _Fade extends StatelessWidget {
  const _Fade({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: AppTheme.motionBase,
        curve: AppTheme.motionCurve,
        child: child,
      ),
    );
  }
}
