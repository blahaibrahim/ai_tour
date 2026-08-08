import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../blocs/app/app_bloc.dart';
import '../../blocs/app/app_event.dart';
import '../../blocs/app/app_state.dart';
import '../../theme.dart';
import '../../utils/geojson_parser.dart';
import 'widgets/map_bottom_panel.dart';

/// The planning surface: a map for orientation, and the route request builder
/// over it.
///
/// The map is context, not input. Routes are scoped to a city's published POI
/// catalogue, so where the camera happens to sit does not affect what gets
/// generated — which is why the camera is no longer reported back into the
/// bloc on every frame of a pan (see [_syncCameraToState]).
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();

  /// The centre the circle is drawn at, updated on every frame of a pan.
  ///
  /// Deliberately local rather than in the bloc. The circle has to track the
  /// finger, but a bloc emission per frame rebuilds the entire planner — every
  /// control, the region readout, the generate button — sixty times a second,
  /// and the resulting programmatic `move` fights the gesture that caused it.
  /// The bloc gets the committed position when the gesture ends
  /// ([_commitCentre]); until then only this notifier changes, so only the
  /// circle layer repaints.
  late final ValueNotifier<LatLng> _liveCentre;

  /// The last centre this screen moved the camera to, so an external move
  /// (search result, "Centre" button) is told apart from the camera simply
  /// being where the user just dragged it.
  LatLng? _appliedCenter;

  bool _entered = false;

  @override
  void initState() {
    super.initState();
    _liveCentre = ValueNotifier(context.read<AppBloc>().state.mapCenter);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _entered = true);
    });
  }

  @override
  void dispose() {
    _liveCentre.dispose();
    super.dispose();
  }

  /// Publishes the camera position to the bloc, which re-resolves which city
  /// the region circle now covers.
  void _commitCentre() {
    final centre = _mapController.camera.center;
    _appliedCenter = centre;
    context.read<AppBloc>().add(SetMapCenterEvent(centre));
  }

  /// Moves the camera when *state* moves — never the other way round.
  void _syncCameraToState(AppState state) {
    if (!_entered) return;
    if (_appliedCenter == state.mapCenter) return;
    _appliedCenter = state.mapCenter;
    _liveCentre.value = state.mapCenter;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.move(state.mapCenter, _mapController.camera.zoom);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppBloc>().state;
    _syncCameraToState(state);

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: _Map(
              state: state,
              controller: _mapController,
              liveCentre: _liveCentre,
              onCentreChanged: (centre) => _liveCentre.value = centre,
              onGestureEnd: _commitCentre,
            ),
          ),

          // The planner, collapsed by default.
          //
          // Opening at the region controls and nothing else is the point: the
          // first thing to decide is *where*, that decision is made on the map,
          // and a sheet covering half the map to show questions with sensible
          // defaults gets in the way of it. Everything else is one drag up —
          // and the generate button is pinned, so the whole trip can be planned
          // without ever expanding the sheet.
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedOpacity(
              opacity: _entered ? 1 : 0,
              duration: AppTheme.motionSlow,
              curve: Curves.easeOut,
              child: const MapBottomPanel(),
            ),
          ),
        ],
      ),
    );
  }
}

class _Map extends StatefulWidget {
  const _Map({
    required this.state,
    required this.controller,
    required this.liveCentre,
    required this.onCentreChanged,
    required this.onGestureEnd,
  });

  final AppState state;
  final MapController controller;
  final ValueNotifier<LatLng> liveCentre;
  final ValueChanged<LatLng> onCentreChanged;
  final VoidCallback onGestureEnd;

  @override
  State<_Map> createState() => _MapState();
}

class _MapState extends State<_Map> {
  List<WilayaPolygon>? _wilayas;

  @override
  void initState() {
    super.initState();
    loadWilayasGeoJson().then((data) {
      if (mounted) setState(() => _wilayas = data);
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: widget.controller,
      options: MapOptions(
        initialCenter: widget.state.mapCenter,
        initialZoom: 11,
        minZoom: 4,
        maxZoom: 18,
        onTap: (tapPosition, point) {
          if (_wilayas == null) return;
          for (final wp in _wilayas!) {
            for (final poly in wp.polygons) {
              if (isPointInPolygon(point, poly)) {
                context.read<AppBloc>().add(ToggleWilayaEvent(wp.id));
                return;
              }
            }
          }
        },
        onPositionChanged: (position, hasGesture) {
          widget.onCentreChanged(position.center);
        },
        onMapEvent: (event) {
          if (event is MapEventMoveEnd || event is MapEventFlingAnimationEnd) {
            widget.onGestureEnd();
          }
        },
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.example.ai_tour',
          retinaMode: RetinaMode.isHighDensity(context),
        ),

        // The wilayas polygons
        if (_wilayas != null)
          PolygonLayer(
            polygons: [
              for (final wp in _wilayas!)
                for (final poly in wp.polygons)
                  Polygon(
                    points: poly,
                    color: widget.state.selectedWilayas.contains(wp.id) 
                        ? AppTheme.accent.withValues(alpha: 0.3) 
                        : Colors.transparent,
                    borderColor: widget.state.selectedWilayas.contains(wp.id) 
                        ? AppTheme.accent 
                        : AppTheme.textSecondary.withValues(alpha: 0.2),
                    borderStrokeWidth: widget.state.selectedWilayas.contains(wp.id) ? 2 : 1,
                  ),
            ],
          ),

        const RichAttributionWidget(
          alignment: AttributionAlignment.bottomLeft,
          showFlutterMapAttribution: false,
          attributions: [
            TextSourceAttribution('OpenStreetMap contributors'),
            TextSourceAttribution('CARTO'),
          ],
        ),
      ],
    );
  }
}
