import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/pressable_scale.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  bool _entered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _entered = true);
    });
  }

  static const _algiers = LatLng(36.7538, 3.0588);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      body: Stack(
        children: [
          // The Map — a clean, minimal basemap that reads as one palette with
          // the rest of the app. The radius circle and center pin are real
          // map layers anchored to Algiers' coordinates, so they pan and
          // zoom together with the map instead of floating fixed on screen.
          Positioned.fill(
            child: FlutterMap(
              options: const MapOptions(
                initialCenter: _algiers,
                initialZoom: 12.0,
                interactionOptions: InteractionOptions(
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
                    return CircleLayer(
                      circles: [
                        CircleMarker(
                          point: _algiers,
                          radius: animatedRadiusKm * 1000,
                          useRadiusInMeter: true,
                          color: AppTheme.accent.withOpacity(0.12),
                          borderColor: AppTheme.accent.withOpacity(0.85),
                          borderStrokeWidth: 2,
                        ),
                      ],
                    );
                  },
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _algiers,
                      width: 100,
                      height: 68,
                      alignment: Alignment.topCenter,
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
                            child: const Text(
                              'Algiers',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: AppTheme.accent,
                              shape: BoxShape.circle,
                              boxShadow: AppTheme.shadowSm,
                              border: Border.all(color: AppTheme.onAccent, width: 2.5),
                            ),
                            child: const Icon(Icons.location_on, color: AppTheme.onAccent, size: 17),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Floating Badge
          Positioned(
            top: 56,
            left: 20,
            child: AnimatedSlide(
              offset: _entered ? Offset.zero : const Offset(0, -0.4),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: _entered ? 1 : 0,
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOut,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: AppTheme.tertiary,
                    borderRadius: AppTheme.brPill,
                    boxShadow: AppTheme.shadowSm,
                  ),
                  child: Text(
                    'AI TOUR',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontSize: 11,
                          letterSpacing: 1.2,
                          color: AppTheme.primary,
                        ),
                  ),
                ),
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
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.bg,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXl)),
                    boxShadow: AppTheme.shadowLg,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Drag handle
                          Center(
                            child: Container(
                              width: 36,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 14),
                              decoration: BoxDecoration(
                                color: AppTheme.divider,
                                borderRadius: AppTheme.brPill,
                              ),
                            ),
                          ),
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
                            child: Stack(
                              children: [
                                TextField(
                                  maxLines: 2,
                                  onChanged: state.setPrompt,
                                  decoration: InputDecoration(
                                    hintText: "quiet Roman ruins, coastal viewpoints...",
                                    hintStyle: TextStyle(color: AppTheme.text.withOpacity(0.4), fontSize: 13),
                                    filled: false,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    contentPadding: const EdgeInsets.fromLTRB(16, 14, 50, 14),
                                  ),
                                ),
                                Positioned(
                                  right: 8,
                                  bottom: 8,
                                  child: PressableScale(
                                    onTap: () => state.onGenerate(),
                                    child: Container(
                                      width: 30,
                                      height: 30,
                                      decoration: const BoxDecoration(
                                        color: AppTheme.accent,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.arrow_upward_rounded, color: AppTheme.onAccent, size: 15),
                                    ),
                                  ),
                                ),
                              ],
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
