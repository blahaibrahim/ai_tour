import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/app/app_bloc.dart';
import '../../blocs/app/app_event.dart';
import '../../models/route.dart';
import '../../theme.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/route_map.dart';
import 'route_map_screen.dart';
import 'widgets/itinerary_list.dart';
import 'widgets/route_header.dart';

/// The generated route, before the traveller commits to walking it.
///
/// Built as a `CustomScrollView` with the map as a collapsing header rather
/// than a plain scrolling column: the map is the answer to "what did you plan
/// for me", so it earns the top of the screen, and it should give that space
/// back as soon as the traveller starts reading the stops.
///
/// The accept button lives outside the scroll view. As a trailing widget in the
/// column it sat below the fold on any route longer than about four stops, so
/// the primary action on the screen was reachable only by scrolling to the end
/// of a list whose whole purpose was to be skimmed.
class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppBloc>().state;
    final route = state.route;

    if (route == null || route.stops.isEmpty) {
      return _EmptyRoute(hadRoute: route != null);
    }

    return Scaffold(
      body: AppBackdrop(
        child: CustomScrollView(
          slivers: [
            _RouteMapHeader(route: route),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.space5,
                AppTheme.space4,
                AppTheme.space5,
                0,
              ),
              sliver: SliverList.list(
                children: [
                  const RouteHeader(),
                  _ItineraryHeaderRow(modifyMode: state.modifyMode),
                  const SizedBox(height: AppTheme.space2),
                  const ItineraryList(),
                  // Clears the bottom bar so the last stop is never trapped
                  // under it.
                  const SizedBox(height: AppTheme.space6),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _AcceptBar(route: route, busy: state.isGeneratingRoute),
    );
  }
}

/// The map, collapsing into a title bar as the page scrolls.
class _RouteMapHeader extends StatelessWidget {
  const _RouteMapHeader({required this.route});

  final GeneratedRoute route;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 280,
      backgroundColor: AppTheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 2,
      leading: Padding(
        padding: const EdgeInsets.all(AppTheme.space2),
        child: _CircleButton(
          icon: Icons.arrow_back,
          semanticLabel: 'Back to planning',
          onTap: () => context.read<AppBloc>().add(const SetScreenEvent('map')),
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.space2, vertical: 8),
          child: ElevatedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => RouteMapScreen(route: route),
              ),
            ),
            icon: const Icon(Icons.map_rounded, size: 20, color: Colors.white),
            label: const Text('Open map', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              elevation: 2,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            ),
          ),
        ),
      ],
      title: const Text(
        'Your route',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppTheme.text,
        ),
      ),
      // The title belongs to the collapsed bar only — over the map it would sit
      // on top of the route.
      forceMaterialTransparency: false,
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Non-interactive: a pannable map inside a scroll view swallows
            // every vertical drag, so the page below it becomes unreachable.
            // The expand button is the way in.
            RouteMap(
              route: route,
              interactive: false,
              padding: const EdgeInsets.fromLTRB(40, 76, 40, 40),
            ),
            // Keeps the pinned bar's icons legible against whatever map
            // features happen to be under them.
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppTheme.surface.withValues(alpha: 0.9),
                      AppTheme.surface.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 0.28],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItineraryHeaderRow extends StatelessWidget {
  const _ItineraryHeaderRow({required this.modifyMode});

  final bool modifyMode;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'ITINERARY',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
            color: AppTheme.text.withValues(alpha: 0.55),
          ),
        ),
        TextButton.icon(
          onPressed: () {
            HapticFeedback.selectionClick();
            context.read<AppBloc>().add(const ToggleModifyEvent());
          },
          icon: Icon(
            modifyMode ? Icons.check_rounded : Icons.edit_outlined,
            size: 16,
          ),
          // "Modify manually" promised reordering, which the screen does not
          // offer — the order is the optimizer's output over a real travel-time
          // matrix and cannot be hand-dragged without invalidating every
          // duration on the page. Removing stops is what the mode actually
          // does, so that is what it now says.
          label: Text(modifyMode ? 'Done' : 'Remove stops'),
          style: TextButton.styleFrom(
            foregroundColor: modifyMode ? AppTheme.accent : AppTheme.text,
          ),
        ),
      ],
    );
  }
}

/// The commit action, pinned above the home indicator.
class _AcceptBar extends StatelessWidget {
  const _AcceptBar({required this.route, required this.busy});

  final GeneratedRoute route;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: const Border(top: BorderSide(color: AppTheme.divider)),
        boxShadow: AppTheme.shadowMd,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.space5,
            AppTheme.space3,
            AppTheme.space5,
            AppTheme.space3,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${route.stops.length} stops',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.text,
                      ),
                    ),
                    Text(
                      formatMinutes(route.estimatedTotalDurationMinutes),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.text.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTheme.space4),
              ElevatedButton(
                onPressed: busy
                    ? null
                    : () {
                        HapticFeedback.mediumImpact();
                        context.read<AppBloc>().add(const AcceptRouteEvent());
                      },
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, AppTheme.minTapTarget + 4),
                  padding: const EdgeInsets.symmetric(horizontal: AppTheme.space6),
                ),
                child: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: AppTheme.onAccent,
                        ),
                      )
                    : const Text('Start this route'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when generation succeeded but nothing survived — every stop dropped in
/// review, or a theme with no published stops in this city.
class _EmptyRoute extends StatelessWidget {
  const _EmptyRoute({required this.hadRoute});

  final bool hadRoute;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackdrop(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.space5),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.deepNavy,
                  ),
                  child: const Icon(
                    Icons.explore_off_outlined,
                    color: AppTheme.onNavy,
                    size: 34,
                  ),
                ),
                const SizedBox(height: AppTheme.space4),
                Text(
                  hadRoute ? 'No stops left' : 'No route yet',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontSize: 24),
                ),
                const SizedBox(height: AppTheme.space2),
                Text(
                  hadRoute
                      ? 'You dropped every stop on this route. Try another theme, '
                          'a longer time budget, or a different city.'
                      : 'Pick a city and a theme to plan your first route.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: AppTheme.text.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: AppTheme.space6),
                ElevatedButton.icon(
                  onPressed: () =>
                      context.read<AppBloc>().add(const SetScreenEvent('map')),
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('Change the plan'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      shape: const CircleBorder(),
      elevation: 2,
      shadowColor: AppTheme.ink.withValues(alpha: 0.2),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Icon(icon, size: 19, color: AppTheme.text, semanticLabel: semanticLabel),
        ),
      ),
    );
  }
}
