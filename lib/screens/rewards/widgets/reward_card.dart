import 'package:flutter/material.dart';

import '../../../models/reward.dart';
import '../../../theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/glass_surface.dart';

/// One row of the catalogue.
///
/// Four states, and the card has to make them distinguishable at a glance
/// because they lead to different actions: **owned** (nothing to do),
/// **sold out** (nothing to do yet), **unaffordable** (go and finish a task),
/// and plain **available**. Only the last is tappable, so the price is the
/// loudest thing on an available card and the quietest on the others.
class RewardCard extends StatelessWidget {
  const RewardCard({
    super.key,
    required this.reward,
    required this.owned,
    required this.affordable,
    required this.busy,
    required this.onTap,
    this.blockedNote,
  });

  final Reward reward;
  final bool owned;
  final bool affordable;
  final bool busy;
  final VoidCallback onTap;

  /// Why this cannot be bought right now, when the reason is not the price —
  /// a reroll with no tour running, say. Shown in place of the blurb, because
  /// the reason to *not* tap is more useful than the description at that point.
  final String? blockedNote;

  bool get _enabled =>
      !owned && !busy && !reward.soldOut && blockedNote == null;

  @override
  Widget build(BuildContext context) {
    // Dimming the whole card is what makes "you cannot have this yet" read
    // without a label on every row.
    final dimmed =
        owned || reward.soldOut || !affordable || blockedNote != null;

    return Opacity(
      opacity: dimmed ? 0.62 : 1,
      child: GlassSurface(
        borderRadius: AppTheme.brMd,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _enabled ? onTap : null,
            borderRadius: AppTheme.brMd,
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.space4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                reward.title,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.ink,
                                ),
                              ),
                            ),
                            if (owned) ...[
                              const SizedBox(width: 6),
                              _Tag(
                                  label: AppLocalizations.of(context).rewardOwned,
                                  color: AppTheme.success),
                            ] else if (reward.soldOut) ...[
                              const SizedBox(width: 6),
                              _Tag(
                                  label: AppLocalizations.of(context).rewardSoldOut,
                                  color: AppTheme.warning),
                            ] else if (_lowStock) ...[
                              const SizedBox(width: 6),
                              _Tag(
                                label: AppLocalizations.of(context)
                                    .rewardStockLeft(reward.stock ?? 0),
                                color: AppTheme.warning,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          blockedNote ?? reward.blurb,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            fontStyle:
                                blockedNote == null ? null : FontStyle.italic,
                            color: AppTheme.text.withValues(alpha: 0.65),
                          ),
                        ),
                        if (reward.pickupNote != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.place_outlined,
                                  size: 12, color: AppTheme.textSecondary),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  reward.pickupNote!,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  AppTheme.gap3,
                  _Price(
                    reward: reward,
                    owned: owned,
                    affordable: affordable,
                    busy: busy,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Worth saying only when it changes the decision. "12 left" is noise; the
  /// last few are a reason to act now.
  bool get _lowStock =>
      reward.stock != null && reward.stock! > 0 && reward.stock! <= 5;
}

class _Price extends StatelessWidget {
  const _Price({
    required this.reward,
    required this.owned,
    required this.affordable,
    required this.busy,
  });

  final Reward reward;
  final bool owned;
  final bool affordable;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (owned) {
      return const Icon(Icons.check_circle, size: 22, color: AppTheme.success);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '${reward.costPoints}',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            // The accent only when it is actually reachable. A bright price on
            // something unaffordable is an invitation to a rejection.
            color: affordable ? AppTheme.cocoa : AppTheme.textSecondary,
          ),
        ),
        Text(
          AppLocalizations.of(context).rewardPointsUnit,
          style: TextStyle(
            fontSize: 10.5,
            color: AppTheme.text.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppTheme.brPill,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: color,
        ),
      ),
    );
  }
}
