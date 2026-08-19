import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';

import '../../../theme.dart';

/// Progress through the intro: one dot per page, the current one stretched
/// into a pill.
///
/// A stretched pill rather than a larger circle because the row has to answer
/// two questions at a glance — where am I, and how much is left — and a size
/// change reads as position while a colour change alone does not.
class PageDots extends StatelessWidget {
  const PageDots({
    super.key,
    required this.count,
    required this.index,
    this.color = AppTheme.accent,
  });

  final int count;
  final int index;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: AppLocalizations.of(context).onboardingPageOf(index + 1, count),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: AppTheme.motionBase,
              curve: AppTheme.motionCurve,
              margin: EdgeInsetsDirectional.only(end: i == count - 1 ? 0 : 6),
              height: 7,
              width: i == index ? 22 : 7,
              decoration: BoxDecoration(
                color: i == index ? color : AppTheme.ink.withValues(alpha: 0.15),
                borderRadius: AppTheme.brPill,
              ),
            ),
        ],
      ),
    );
  }
}
