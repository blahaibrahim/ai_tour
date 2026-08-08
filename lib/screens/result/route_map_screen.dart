import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/app/app_bloc.dart';
import '../../blocs/app/app_event.dart';
import '../../models/route.dart';
import '../../theme.dart';
import '../../widgets/location_detail_overlay.dart';
import '../../widgets/route_map.dart';

/// The route, full screen and pannable.
///
/// Pushed rather than embedded: the preview on the result screen has to be
/// non-interactive so the page can still be scrolled past it, and "let me
/// actually look at this" is a different intent that deserves the whole
/// viewport.
class RouteMapScreen extends StatelessWidget {
  const RouteMapScreen({super.key, required this.route, this.activeStopIndex});

  final GeneratedRoute route;
  final int? activeStopIndex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: RouteMap(
              route: route,
              activeStopIndex: activeStopIndex,
              showNames: true,
              // Room for the top bar and the legend card, so no pin is ever
              // fitted underneath the chrome.
              padding: const EdgeInsets.fromLTRB(40, 110, 40, 140),
              onStopTap: (stop) {
                final regionLabel =
                    context.read<AppBloc>().state.selectedCity?.name ?? '';
                context
                    .read<AppBloc>()
                    .add(OpenDetailEvent(stop.toLocation(regionLabel: regionLabel)));
              },
            ),
          ),

          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.space4),
                child: Row(
                  children: [
                    _MapChromeButton(
                      icon: Icons.arrow_back,
                      semanticLabel: 'Back',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: AppTheme.space3),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.space4,
                          vertical: AppTheme.space2 + 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: AppTheme.brPill,
                          boxShadow: AppTheme.shadowSm,
                        ),
                        child: Text(
                          '${route.stops.length} stops · '
                          '${formatMinutes(route.estimatedTotalDurationMinutes)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.text,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Legend
          Positioned(
            left: AppTheme.space4,
            right: AppTheme.space4,
            bottom: AppTheme.space4,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.space4,
                  vertical: AppTheme.space3,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: AppTheme.brLg,
                  boxShadow: AppTheme.shadowMd,
                ),
                child: Center(
                  child: Text(
                    'Tap a pin to see more details',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.text.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ),
            ),
          ),
          
          const LocationDetailOverlay(),
        ],
      ),
    );
  }
}

class _MapChromeButton extends StatelessWidget {
  const _MapChromeButton({
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
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: AppTheme.minTapTarget,
          height: AppTheme.minTapTarget,
          child: Icon(icon, size: 20, color: AppTheme.text, semanticLabel: semanticLabel),
        ),
      ),
    );
  }
}
