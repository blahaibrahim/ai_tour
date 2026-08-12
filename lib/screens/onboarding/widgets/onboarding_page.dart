import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../../../widgets/staggered_entrance.dart';
import '../onboarding_content.dart';
import 'onboarding_art.dart';

/// One intro slide.
///
/// The three [OnboardingLayout]s reorder the same three pieces — art, title,
/// body — rather than restyling them, so the pages stay recognisably one flow
/// while none of them looks like the one before it. Each layout gives the art a
/// different share of the height, because art at the bottom of a page needs
/// less room than art leading it.
class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key, required this.content});

  final OnboardingPageContent content;

  /// Fraction of the page's height the art gets, per layout.
  double get _artFraction => switch (content.layout) {
        OnboardingLayout.artFirst => 0.46,
        OnboardingLayout.titleArtBody => 0.36,
        OnboardingLayout.textFirst => 0.42,
      };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Short devices give the art less room rather than pushing the body
        // text off the bottom — the sentence is the part that has to be read.
        final artHeight =
            (constraints.maxHeight * _artFraction).clamp(150.0, 360.0);

        final art = SizedBox(
          height: artHeight,
          width: double.infinity,
          child: OnboardingArt(
            assetPath: content.artAsset,
            icon: content.icon,
          ),
        );

        final title = Text(
          content.title,
          style: textTheme.headlineMedium?.copyWith(fontSize: 28, height: 1.15),
        );

        final body = Text(
          content.body,
          style: textTheme.bodyLarge?.copyWith(
            fontSize: 15.5,
            height: 1.55,
            // Navy rather than the app's grey secondary colour: the duotone
            // backdrop is genuinely coloured, and grey body text fell under
            // 4.5:1 on it. 0.82 is the lowest alpha that still clears 4.5
            // against the darkest end of the ramp (4.85:1 at the very bottom),
            // which keeps the "quieter than the title" reading — the title
            // above it runs at full ink, 6.9:1 in the same place.
            color: AppTheme.ink.withValues(alpha: 0.82),
          ),
        );

        // Ordered per layout, then staggered in the order they are read —
        // whatever is at the top of the page arrives first.
        final blocks = switch (content.layout) {
          OnboardingLayout.artFirst => [art, title, body],
          OnboardingLayout.titleArtBody => [title, art, body],
          OnboardingLayout.textFirst => [title, body, art],
        };

        return SingleChildScrollView(
          // Only scrolls when it has to (a small screen with large system
          // text); on a normal phone the column fits and nothing moves.
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.space6),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < blocks.length; i++) ...[
                  StaggeredEntrance(index: i, child: blocks[i]),
                  // The gap after the art is wider than the one between the two
                  // text blocks, whichever order they came out in.
                  if (i < blocks.length - 1)
                    SizedBox(
                      height: identical(blocks[i], art) ||
                              identical(blocks[i + 1], art)
                          ? AppTheme.space6
                          : AppTheme.space3,
                    ),
                ],
                AppTheme.gap6,
              ],
            ),
          ),
        );
      },
    );
  }
}
