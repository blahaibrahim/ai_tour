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
  });

  final String assetPath;
  final IconData icon;

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
        // is a single icon.
        errorBuilder: (_, _, _) => _ArtPlaceholder(icon: icon),
      ),
    );
  }
}

/// What the slot shows before the artwork exists: the page's icon, quietly, and
/// nothing else.
///
/// It used to caption itself with "Artwork goes here" and the filename it was
/// waiting for. That is useful to whoever is wiring the flow up and to nobody
/// else — it reads as an unfinished screen to anyone looking at the app, and
/// the slides get shown to people well before the illustrations land. The
/// filenames live in `assets/onboarding/README.md`, which is where someone
/// looking for them would go anyway.
class _ArtPlaceholder extends StatelessWidget {
  const _ArtPlaceholder({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Scales with whatever room the layout gave it — the three page
        // layouts hand the art quite different heights.
        final iconSize = (constraints.maxHeight * 0.42).clamp(48.0, 132.0);

        return Center(
          // Neutral navy rather than the page's tint, and faint. The two warm
          // pages put an amber stand-in over the sand end of the backdrop,
          // where it all but disappears; the tint still shows up where it can
          // be read, on the advance button and the progress dots.
          child: Icon(
            icon,
            size: iconSize,
            color: AppTheme.ink.withValues(alpha: 0.22),
          ),
        );
      },
    );
  }
}
