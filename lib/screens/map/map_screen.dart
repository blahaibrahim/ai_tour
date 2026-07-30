import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../blocs/app/app_bloc.dart';
import '../../blocs/app/app_event.dart';
import '../../theme.dart';
import '../../widgets/location_search_bar.dart';
import 'widgets/map_bottom_panel.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  bool _entered = false;
  final MapController _mapController = MapController();
  LatLng? _lastCenter;
  late final ValueNotifier<LatLng> _centerNotifier;

  @override
  void initState() {
    super.initState();
    _centerNotifier = ValueNotifier(const LatLng(36.7538, 3.0588));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _entered = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppBloc>().state;

    // Update map if center changes from external search
    if (_lastCenter != state.mapCenter && _entered) {
      _lastCenter = state.mapCenter;
      _centerNotifier.value = state.mapCenter;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _mapController.move(state.mapCenter, _mapController.camera.zoom);
        }
      });
    }

    return Scaffold(
      body: Stack(
        children: [
          // The Map
          Positioned(
            top: -250,
            bottom: 0,
            left: 0,
            right: 0,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: state.mapCenter,
                initialZoom: 12.0,
                onPositionChanged: (position, hasGesture) {
                  if (position.center != null) {
                    _centerNotifier.value = position.center!;
                  }
                },
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
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: state.radiusKm, end: state.radiusKm),
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  builder: (context, animatedRadiusKm, child) {
                    return ValueListenableBuilder<LatLng>(
                      valueListenable: _centerNotifier,
                      builder: (context, center, child) {
                        return CircleLayer(
                          circles: [
                            CircleMarker(
                              point: center,
                              radius: animatedRadiusKm * 1000,
                              useRadiusInMeter: true,
                              color: AppTheme.accent.withOpacity(0.12),
                              borderColor: AppTheme.accent.withOpacity(0.85),
                              borderStrokeWidth: 2,
                            ),
                          ],
                        );
                      }
                    );
                  },
                ),
              ],
            ),
          ),

          // Search Bar
          Positioned(
            top: 56,
            left: 16,
            right: 16,
            child: AnimatedSlide(
              offset: _entered ? Offset.zero : const Offset(0, -0.4),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: _entered ? 1 : 0,
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOut,
                child: const LocationSearchBar(),
              ),
            ),
          ),

          // Bottom Panel
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedSlide(
              offset: _entered ? Offset.zero : const Offset(0, 0.25),
              duration: const Duration(milliseconds: 460),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: _entered ? 1 : 0,
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeOut,
                child: const MapBottomPanel(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
