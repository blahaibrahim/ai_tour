import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/glass_surface.dart';
import '../widgets/pressable_scale.dart';
import '../widgets/location_search_bar.dart';

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

  static const _algiers = LatLng(36.7538, 3.0588);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

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
          // The Map — a clean, minimal basemap that reads as one palette with
          // the rest of the app. The radius circle and center pin are real
          // map layers anchored to Algiers' coordinates, so they pan and
          // zoom together with the map instead of floating fixed on screen.
          Positioned(
            top: -300,
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

          // Search Bar (replaces the top-left Floating Badge)
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

          // Fixed Bottom Panel
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
                child: GlassSurface(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXl)),
                  boxShadow: AppTheme.shadowLg,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Where do you want to explore?',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 20, height: 1.1),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Set a radius, tell us your vibe.",
                            style: TextStyle(fontSize: 12.5, color: AppTheme.text.withOpacity(0.7)),
                          ),
                          const SizedBox(height: 16),

                          // Radius Slider
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Search radius',
                                style: TextStyle(fontSize: 11.5, color: AppTheme.text.withOpacity(0.65)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppTheme.accentSoft,
                                  borderRadius: AppTheme.brPill,
                                ),
                                child: Text(
                                  '${state.radiusKm.toInt()} km',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.accentDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: state.radiusKm,
                            min: 5,
                            max: 60,
                            divisions: 11,
                            onChanged: state.setRadius,
                          ),

                          const SizedBox(height: 16),
                          // Wanted Visits Slider
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Number of visits wanted',
                                style: TextStyle(fontSize: 11.5, color: AppTheme.text.withOpacity(0.65)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppTheme.accentSoft,
                                  borderRadius: AppTheme.brPill,
                                ),
                                child: Text(
                                  '${state.wantedVisits}',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.accentDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: state.wantedVisits.toDouble(),
                            min: 1,
                            max: 20,
                            divisions: 19,
                            onChanged: state.setWantedVisits,
                          ),

                          const SizedBox(height: 8),
                          Text(
                            "TELL THE AI WHAT YOU'RE AFTER",
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 0.8,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.text.withOpacity(0.5),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Text Area
                          Container(
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceAlt,
                              borderRadius: AppTheme.brMd,
                            ),
                            child: TextField(
                              maxLines: 2,
                              onChanged: state.setPrompt,
                              decoration: InputDecoration(
                                hintText: "quiet Roman ruins, coastal viewpoints...",
                                hintStyle: TextStyle(color: AppTheme.text.withOpacity(0.4), fontSize: 13),
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),
                          // Button
                          ElevatedButton(
                            onPressed: state.onGenerate,
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 52),
                            ),
                            child: const Text('Generate my route', style: TextStyle(fontSize: 14.5)),
                          ),
                        ],
                      ),
                    ),
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
