import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../blocs/app/app_bloc.dart';
import '../../../models/route.dart';
import '../../../theme.dart';
import '../../../widgets/route_map.dart';

/// Summary of the generated route: how the time breaks down, the map's colour
/// key, an optional trip date, and the day-count warning.
///
/// The duration is the module's own estimate — Σ travel time from a real
/// travel-time matrix plus Σ per-POI dwell time — not a guess derived from the
/// stop count.
class RouteHeader extends StatefulWidget {
  const RouteHeader({super.key});

  @override
  State<RouteHeader> createState() => _RouteHeaderState();
}

class _RouteHeaderState extends State<RouteHeader> {

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppBloc>().state;
    final route = state.route;
    if (route == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // How the estimate is made up. Worth breaking out because it is what
        // the hybrid transport model actually produced: a drive between
        // clusters, walking inside them, and time standing still at the stops.
        Container(
          padding: const EdgeInsets.all(AppTheme.space4),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: AppTheme.brLg,
            border: Border.all(color: AppTheme.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _TimeStat(
                    icon: Icons.schedule_rounded,
                    value: formatMinutes(route.estimatedTotalDurationMinutes),
                    label: 'total',
                    emphasised: true,
                  ),
                  _TimeStat(
                    icon: Icons.place_outlined,
                    value: '${route.stops.length}',
                    label: route.stops.length == 1 ? 'stop' : 'stops',
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.space3),
              const Divider(height: 1, color: AppTheme.divider),
              const SizedBox(height: AppTheme.space3),
              // Doubles as the map's key — same colours, same dash language.
              RouteMapLegend(route: route),
            ],
          ),
        ),

        const SizedBox(height: AppTheme.space3),

        // The day-count flag, from the module's isochrone check. Not a
        // stops-per-day heuristic: it says the remaining stops aren't reachable
        // in what's left of the budget, which is a fact about geography rather
        // than arithmetic.
        if (route.needsMoreThanOneDay) ...[
          const SizedBox(height: AppTheme.space3),
          _Notice(
            icon: Icons.wb_twilight_rounded,
            // Amber, not red. A route that needs a second day is a good route
            // with a scheduling consequence, and painting it in the error
            // colour told travellers something had gone wrong.
            color: AppTheme.warning,
            background: AppTheme.warningSoft,
            title: 'Longer than your ${formatMinutes(route.timeBudgetMinutes)}',
            body: 'This route needs about '
                '${formatMinutes(route.estimatedTotalDurationMinutes)}. '
                'Plan on ${route.dayCountFlag} days, or remove a few stops below.',
          ),
        ],

        // A generation-time problem that didn't stop the route being shown —
        // a refine that failed, for instance. Distinct from the day-count
        // notice above, which is about the route rather than about the app.
        if (state.routeError != null) ...[
          const SizedBox(height: AppTheme.space3),
          _Notice(
            icon: Icons.error_outline_rounded,
            color: AppTheme.error,
            background: AppTheme.errorSoft,
            title: 'Something went wrong',
            body: state.routeError!,
          ),
        ],

        const SizedBox(height: AppTheme.space5),
      ],
    );
  }
}

/// One figure in the summary row.
class _TimeStat extends StatelessWidget {
  const _TimeStat({
    required this.icon,
    required this.value,
    required this.label,
    this.emphasised = false,
  });

  final IconData icon;
  final String value;
  final String label;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      // The icon is decorative — the value and label already say everything —
      // so the whole stat is announced as one string instead of three nodes.
      child: Semantics(
        label: '$value $label',
        excludeSemantics: true,
        child: Column(
          children: [
            Icon(
              icon,
              size: 16,
              color: emphasised
                  ? AppTheme.accent
                  : AppTheme.text.withValues(alpha: 0.5),
            ),
            const SizedBox(height: AppTheme.space1 + 2),
            Text(
              value,
              style: TextStyle(
                fontSize: emphasised ? 17 : 15,
                fontWeight: FontWeight.w700,
                color: emphasised ? AppTheme.accentDark : AppTheme.text,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                color: AppTheme.text.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A titled inline message. Used for both the day-count flag and route errors,
/// so the two read as the same kind of object at different severities.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.color,
    required this.background,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.space3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppTheme.brMd,
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: AppTheme.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: AppTheme.text.withValues(alpha: 0.8),
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
