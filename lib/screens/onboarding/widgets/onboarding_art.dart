import 'package:flutter/material.dart';

import '../../../theme.dart';

/// The illustration slot on an intro page.
///
/// Frameless on purpose: the artwork sits directly on the page background with
/// no card, border or fill behind it, so a transparent PNG reads as part of the
/// page rather than as a picture pasted onto it.
///
/// The artwork does not exist yet, so this renders the asset if it is there and
/// a plain stand-in if it is not — dropping a file into `assets/onboarding/` is
/// the entire hand-off, with no code change and no layout to re-tune, because
/// both states occupy the same box.
class OnboardingArt extends StatelessWidget {
  const OnboardingArt({
    super.key,
    required this.assetPath,
    required this.icon,
    required this.tint,
  });

  final String assetPath;
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'Illustration',
      child: Image.asset(
        assetPath,
        fit: BoxFit.contain,
        // Reached on every build until the real art lands. Cheap: the asset
        // bundle resolves the miss without touching the disk, and the stand-in
        // is an icon and two lines of text.
        errorBuilder: (_, _, _) => _ArtPlaceholder(
          assetPath: assetPath,
          icon: icon,
          tint: tint,
        ),
      ),
    );
  }
}

/// What the slot shows before the artwork exists.
///
/// Names the file it is waiting for rather than showing a generic shape — the
/// stand-in is also the spec for what to draw and where to put it.
class _ArtPlaceholder extends StatelessWidget {
  const _ArtPlaceholder({
    required this.assetPath,
    required this.icon,
    required this.tint,
  });

  final String assetPath;
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Scales with whatever room the layout gave it — the three page
        // layouts hand the art quite different heights.
        final iconSize = (constraints.maxHeight * 0.42).clamp(48.0, 132.0);

        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Neutral navy rather than the page's tint. The two warm pages
              // put an amber stand-in over the sand end of the backdrop, where
              // it all but disappears; the tint still shows up where it can be
              // read, on the advance button and the progress dots.
              Icon(icon, size: iconSize, color: AppTheme.ink.withValues(alpha: 0.30)),
              AppTheme.gap4,
              Text(
                'Artwork goes here',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.ink.withValues(alpha: 0.62),
                ),
              ),
              AppTheme.gap1,
              Text(
                assetPath,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  color: AppTheme.ink.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
