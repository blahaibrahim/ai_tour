import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../blocs/app/app_bloc.dart';
import '../../../theme.dart';
import '../../notifications/notifications_screen.dart';
import '../../../widgets/glass_surface.dart';
import '../../../widgets/points_pill.dart';
import '../../../widgets/pressable_scale.dart';

/// Title, spendable balance, the way into the shop, notifications, and
/// settings.
///
/// The number here is [AppState.pointsBalance] — what is left to spend — rather
/// than the lifetime score, because the control immediately to its right spends
/// exactly that. A pill showing one number beside a button that spends another
/// would be a small lie told every time the screen is opened.
class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key, required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final balance = context.select<AppBloc, int?>((b) => b.state.pointsBalance);
    final l10n = AppLocalizations.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The wordmark, not a translated noun: it stays Latin in French
              // and becomes مسار in Arabic, which is the word the name is
              // taken from to begin with.
              Text(
                l10n.appTitle.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const _Greeting(),
            ],
          ),
        ),
        const SizedBox(width: AppTheme.space3),
        PointsPill(
          value: balance,
          semanticLabel: balance == null
              ? l10n.homePointsSyncing
              : l10n.homePointsToSpend(balance),
        ),
        const SizedBox(width: AppTheme.space2),
        const ShopButton(),
        const SizedBox(width: AppTheme.space2),
        const NotificationsButton(),
        const SizedBox(width: AppTheme.space2),
        PressableScale(
          onTap: onSettings,
          child: GlassSurface(
            tint: GlassTint.dark,
            borderRadius: AppTheme.brPill,
            alignment: Alignment.center,
            child: SizedBox(
              width: AppTheme.minTapTarget,
              height: AppTheme.minTapTarget,
              child: Icon(
                Icons.settings_outlined,
                color: Colors.white,
                size: 20,
                semanticLabel: l10n.actionSettings,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The way into the notification inbox, with a count of what is unread.
///
/// On the home header rather than in Settings, and rather than as a fourth nav
/// destination: an inbox is checked, not visited — the badge is the only thing
/// that ever makes it worth opening, so it belongs next to the badge and not in
/// a bar of equals with the map and the folder.
class NotificationsButton extends StatelessWidget {
  const NotificationsButton({super.key});

  @override
  Widget build(BuildContext context) {
    final unread =
        context.select<AppBloc, int>((b) => b.state.unreadNotifications);
    final l10n = AppLocalizations.of(context);

    return PressableScale(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
        );
      },
      child: GlassSurface(
        tint: GlassTint.dark,
        borderRadius: AppTheme.brPill,
        alignment: Alignment.center,
        child: SizedBox(
          width: AppTheme.minTapTarget,
          height: AppTheme.minTapTarget,
          // Unclipped, so the badge can overhang the pill's corner rather than
          // being cut off by it.
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(
                unread > 0
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_none,
                color: Colors.white,
                size: 20,
                // The count is in the label, not only in the dot: a badge is
                // invisible to a screen reader, and "3 unread" is the whole
                // reason to press this.
                semanticLabel: unread > 0
                    ? l10n.notifInboxUnread(unread)
                    : l10n.notifInboxTitle,
              ),
              if (unread > 0)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 16),
                    height: 16,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryAccent,
                      borderRadius: AppTheme.brPill,
                      // A ring in the surface colour, so the badge reads as
                      // sitting on top of the icon rather than merging with it.
                      border: Border.all(color: AppTheme.deepNavy, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      // Past nine the exact number stops being information and
                      // starts being a layout problem.
                      unread > 9 ? '9+' : '$unread',
                      style: const TextStyle(
                        color: AppTheme.ink,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rendered separately so the headline can pick up the display face the rest of
/// the app's screen titles use, which needs a `BuildContext` the enclosing
/// const `Column` would otherwise deny it.
class _Greeting extends StatelessWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context) {
    return Text(
      AppLocalizations.of(context).homeGreeting,
      style: Theme.of(context)
          .textTheme
          .headlineSmall
          ?.copyWith(fontSize: 23, color: Colors.white),
    );
  }
}
