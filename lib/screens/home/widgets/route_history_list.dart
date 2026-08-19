import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../blocs/app/app_bloc.dart';
import '../../../blocs/app/app_event.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/route.dart';
import '../../../theme.dart';
import '../../../widgets/glass_surface.dart';

/// Routes this traveller has already generated, newest first.
///
/// Tapping one re-opens it through [OpenRouteByIdEvent] — the same path a
/// tapped "route ready" notification takes, which until now was the *only* way
/// back to a route the app had forgotten. The list carries summaries, not
/// routes: the stops are fetched when one is opened.
class RouteHistoryList extends StatelessWidget {
  const RouteHistoryList({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppBloc>().state;
    final routes = state.routeHistory;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context).homeYourRoutes,
          style: const TextStyle(
            fontSize: 11,
            letterSpacing: 1.2,
            color: Colors.white70,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppTheme.space3),
        if (routes.isEmpty)
          // The loading and the empty case are told apart here and nowhere
          // else: an empty list while the fetch is still out would read as "you
          // have never made one", which is a discouraging thing to say to
          // somebody who has.
          state.isLoadingRouteHistory
              ? const _HistoryPlaceholder()
              : const _NoRoutesYet()
        else
          for (final route in routes)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.space3),
              child: _RouteCard(route: route),
            ),
      ],
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.route});

  final RouteSummary route;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GlassSurface(
      borderRadius: AppTheme.brMd,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppTheme.brMd,
          onTap: () =>
              context.read<AppBloc>().add(OpenRouteByIdEvent(route.id)),
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.space4),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.accentSoft,
                    borderRadius: AppTheme.brSm,
                  ),
                  child: Icon(
                    route.transportMode == TransportMode.walking
                        ? Icons.directions_walk
                        : route.transportMode == TransportMode.driving
                            ? Icons.directions_car_outlined
                            : Icons.alt_route,
                    color: AppTheme.accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppTheme.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              route.title(l10n),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.ink,
                              ),
                            ),
                          ),
                          if (route.generatedAt != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              _relative(l10n, route.generatedAt!),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AppTheme.text.withValues(alpha: 0.45),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        route.subtitle(l10n),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.text.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    size: 20, color: AppTheme.text.withValues(alpha: 0.3)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// "today", "3d", "2w" — enough to place a route in time. Still deliberately
  /// not a real date format: this sits in a tight row beside the title, and a
  /// spelled-out date would push the name it belongs to out of the card.
  static String _relative(AppLocalizations l10n, DateTime when) {
    final days = DateTime.now().difference(when).inDays;
    if (days <= 0) return l10n.relativeToday;
    if (days == 1) return l10n.relativeYesterday;
    if (days < 7) return l10n.relativeDays(days);
    if (days < 365) return l10n.relativeWeeks(days ~/ 7);
    return l10n.relativeYears(days ~/ 365);
  }
}

class _NoRoutesYet extends StatelessWidget {
  const _NoRoutesYet();

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      borderRadius: AppTheme.brMd,
      padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.space4, vertical: AppTheme.space5),
      child: Row(
        children: [
          Icon(Icons.route_outlined,
              size: 20, color: AppTheme.text.withValues(alpha: 0.35)),
          const SizedBox(width: AppTheme.space3),
          Expanded(
            child: Text(
              AppLocalizations.of(context).homeRoutesEmpty,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: AppTheme.text.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Two dim cards standing in for the list while it loads, sized like the real
/// ones so the screen does not jump when they arrive.
class _HistoryPlaceholder extends StatelessWidget {
  const _HistoryPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < 2; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.space3),
            child: Opacity(
              opacity: 0.4,
              child: GlassSurface(
                borderRadius: AppTheme.brMd,
                child: const SizedBox(height: 72, width: double.infinity),
              ),
            ),
          ),
      ],
    );
  }
}
