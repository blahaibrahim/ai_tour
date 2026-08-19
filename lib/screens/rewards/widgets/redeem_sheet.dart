import 'package:flutter/material.dart';

import '../../../models/reward.dart';
import '../../../theme.dart';
import '../../../l10n/app_localizations.dart';

/// Confirms one purchase before it happens.
///
/// A confirmation step for something free would be friction, but points are not
/// free — they took a walk to earn, and a cosmetic bought by a mis-tap cannot be
/// given back: `spend_points` has no refund path, deliberately, because a debit
/// that can be reversed by the client is not a debit. So the sheet states the
/// price, what the balance becomes, and for the one-time rewards that this is
/// permanent.
///
/// Returns true when the traveller confirmed.
Future<bool?> showRedeemSheet(
  BuildContext context, {
  required Reward reward,
  required int? balance,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => _RedeemSheet(reward: reward, balance: balance),
  );
}

class _RedeemSheet extends StatelessWidget {
  const _RedeemSheet({required this.reward, required this.balance});

  final Reward reward;
  final int? balance;

  @override
  Widget build(BuildContext context) {
    final remaining = balance == null ? null : balance! - reward.costPoints;
    final short = remaining != null && remaining < 0;

    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppTheme.radiusXl)),
        ),
        padding: const EdgeInsets.fromLTRB(
            AppTheme.space5, AppTheme.space3, AppTheme.space5, AppTheme.space5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.ink.withValues(alpha: 0.15),
                  borderRadius: AppTheme.brPill,
                ),
              ),
            ),
            AppTheme.gap5,
            Text(
              reward.title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              reward.blurb,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: AppTheme.text.withValues(alpha: 0.7),
              ),
            ),
            AppTheme.gap5,
            _Line(
              label: AppLocalizations.of(context).redeemCosts,
              value: AppLocalizations.of(context).balancePoints(reward.costPoints),
              emphasis: true,
            ),
            if (remaining != null) ...[
              const SizedBox(height: 8),
              _Line(
                label: short
                    ? AppLocalizations.of(context).redeemYouAreShort
                    : AppLocalizations.of(context).redeemLeftAfterwards,
                value: AppLocalizations.of(context)
                    .balancePoints(short ? -remaining : remaining),
                tint: short ? AppTheme.error : null,
              ),
            ],
            if (!reward.repeatable) ...[
              AppTheme.gap4,
              _Note(
                icon: Icons.lock_outline,
                text: AppLocalizations.of(context).redeemNoteInstant,
              ),
            ],
            if (reward.isVoucher) ...[
              AppTheme.gap3,
              _Note(
                icon: Icons.schedule,
                text: AppLocalizations.of(context).redeemNoteVoucher,
              ),
            ],
            if (reward.kind == RewardKind.physical) ...[
              AppTheme.gap3,
              _Note(
                icon: Icons.person_outline,
                text: AppLocalizations.of(context).redeemNoteManual,
              ),
            ],
            AppTheme.gap6,
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      foregroundColor: AppTheme.textSecondary,
                    ),
                    child: Text(AppLocalizations.of(context).redeemNotYet),
                  ),
                ),
                AppTheme.gap3,
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    // Disabled rather than hidden when short: the traveller
                    // still needs to see what it costs and how close they are.
                    onPressed: short ? null : () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: AppTheme.onAccent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: AppTheme.brMd),
                    ),
                    child: Text(short
                        ? AppLocalizations.of(context).redeemNotEnoughPoints
                        : AppLocalizations.of(context).redeemConfirm),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.value,
    this.emphasis = false,
    this.tint,
  });

  final String label;
  final String value;
  final bool emphasis;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            color: AppTheme.text.withValues(alpha: 0.6),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: emphasis ? 16 : 14,
            fontWeight: emphasis ? FontWeight.w700 : FontWeight.w600,
            color: tint ?? AppTheme.ink,
          ),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: AppTheme.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: AppTheme.text.withValues(alpha: 0.6),
            ),
          ),
        ),
      ],
    );
  }
}
