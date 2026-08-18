import 'package:flutter/material.dart';

import '../screens/rewards/rewards_screen.dart';
import '../theme.dart';
import 'glass_surface.dart';
import 'pressable_scale.dart';

/// The coins readout, for the dark headers on Home and Overview.
///
/// Both screens show a number of points and both sit on `AppBackdropVariant.deep`,
/// so this exists once rather than twice — but *which* number is the screen's
/// own decision and not this widget's. Overview shows what the current walk has
/// earned; Home shows what is left to spend. They are genuinely different
/// questions, so the caller supplies the value and the label that describes it.
class PointsPill extends StatelessWidget {
  const PointsPill({
    super.key,
    required this.value,
    required this.semanticLabel,
  });

  /// Null renders as a dash. It means "not synced yet", and a 0 in its place
  /// would tell a traveller with 400 points that they have none.
  final int? value;

  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.space3,
          vertical: AppTheme.space2 - 2,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: AppTheme.brPill,
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.stars_rounded, size: 15, color: AppTheme.sand),
            const SizedBox(width: AppTheme.space1),
            Text(
              value?.toString() ?? '—',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The way into the shop, sitting immediately beside a [PointsPill].
///
/// Next to the count on purpose: the number and the thing it buys are one idea,
/// and putting the shop three taps away in Settings — where it started — made
/// points look like a statistic rather than a currency.
class ShopButton extends StatelessWidget {
  const ShopButton({super.key, this.size = AppTheme.minTapTarget});

  final double size;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const RewardsScreen()),
      ),
      child: GlassSurface(
        tint: GlassTint.dark,
        borderRadius: AppTheme.brPill,
        alignment: Alignment.center,
        child: SizedBox(
          width: size,
          height: size,
          child: const Icon(
            Icons.redeem_rounded,
            color: AppTheme.sand,
            size: 20,
            semanticLabel: 'Rewards',
          ),
        ),
      ),
    );
  }
}
