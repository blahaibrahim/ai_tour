import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/staggered_entrance.dart';

class AreasMapScreen extends StatelessWidget {
  const AreasMapScreen({super.key});

  static const _algiers = LatLng(36.7538, 3.0588);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final points = state.accepted.map((l) => LatLng(l.lat, l.lng)).toList();

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: _algiers,
                initialZoom: 6.0,
                initialCameraFit: points.isNotEmpty
                    ? CameraFit.coordinates(
                        coordinates: points,
                        padding: const EdgeInsets.fromLTRB(50, 140, 50, 220),
                        maxZoom: 11,
                      )
                    : null,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.example.ai_tour',
                ),
                // Real geo-anchored markers — these pan and zoom together
                // with the map instead of floating fixed on screen.
                MarkerLayer(
                  markers: [
                    for (int i = 0; i < state.accepted.length; i++)
                      Marker(
                        point: LatLng(state.accepted[i].lat, state.accepted[i].lng),
                        width: 140,
                        height: 68,
                        alignment: Alignment.topCenter,
                        child: StaggeredEntrance(
                          index: i,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTheme.tertiary,
                                  borderRadius: AppTheme.brPill,
                                  boxShadow: AppTheme.shadowSm,
                                ),
                                child: Text(
                                  state.accepted[i].name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: AppTheme.accent,
                                  shape: BoxShape.circle,
                                  boxShadow: AppTheme.shadowSm,
                                  border: Border.all(color: AppTheme.onAccent, width: 2),
                                ),
                                child: const Icon(Icons.location_on, color: AppTheme.onAccent, size: 14),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          Positioned(
            top: 56,
            left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: AppTheme.tertiary,
                borderRadius: AppTheme.brPill,
                boxShadow: AppTheme.shadowSm,
              ),
              child: Text(
                'YOUR SELECTED AREAS',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontSize: 11,
                      letterSpacing: 1.0,
                      color: AppTheme.primary,
                    ),
              ),
            ),
          ),

          if (state.accepted.isEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: AppTheme.brLg,
                    boxShadow: AppTheme.shadowMd,
                  ),
                  child: Column(
                    children: [
                      Text('No areas selected yet.', style: TextStyle(fontSize: 13, color: AppTheme.text.withOpacity(0.75))),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: () => state.setScreen('map'),
                        child: const Text('Plan a route'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
