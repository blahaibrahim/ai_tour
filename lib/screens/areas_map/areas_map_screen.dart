import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/app/app_bloc.dart';
import '../../blocs/app/app_event.dart';
import '../../theme.dart';
import '../../widgets/glass_surface.dart';
import '../../widgets/route_map.dart';

class AreasMapScreen extends StatelessWidget {
  const AreasMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppBloc>().state;
    final route = state.route;

    if (route == null) {
      return Scaffold(
        body: Center(
          child: Text(
            'No route generated yet.',
            style: TextStyle(color: AppTheme.text.withValues(alpha: 0.7)),
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: RouteMap(
              route: route,
              activeStopIndex: state.currentStopIdx,
              showNames: true,
              padding: const EdgeInsets.fromLTRB(40, 110, 40, 140),
              onStopTap: (stop) {
                final regionLabel = state.selectedCity?.name ?? '';
                context.read<AppBloc>().add(OpenDetailEvent(stop.toLocation(regionLabel: regionLabel)));
              },
            ),
          ),
          
          // Info message moved to the top so it doesn't clash with the navbar
          Positioned(
            top: 60,
            left: 20,
            right: 20,
            child: Center(
              child: GlassSurface(
                borderRadius: AppTheme.brPill,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                boxShadow: AppTheme.shadowSm,
                child: Text(
                  'Tap a pin to see more details',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.text.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
