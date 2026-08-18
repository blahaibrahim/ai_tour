import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../../../widgets/glass_surface.dart';

/// The wallet, at the top of the rewards screen.
///
/// Shows one number, not two. The lifetime score already has a home in Settings
/// and answers a different question — "how much have I done" rather than "what
/// can I have" — and putting both here invites the traveller to subtract them
/// and find that they do not reconcile, which by design they do not.
class BalanceHeader extends StatelessWidget {
  const BalanceHeader({super.key, required this.balance});

  /// Null is "not synced yet", and is shown as such. A zero here would tell a
  /// traveller with 900 points that they have nothing to spend.
  final int? balance;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      borderRadius: AppTheme.brLg,
      padding: const EdgeInsets.fromLTRB(
          AppTheme.space5, AppTheme.space5, AppTheme.space5, AppTheme.space5),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: AppTheme.secondarySoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.stars_rounded,
                color: AppTheme.secondaryAccent, size: 24),
          ),
          AppTheme.gap4,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TO SPEND',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: AppTheme.text.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  balance == null ? 'Syncing…' : '$balance points',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
