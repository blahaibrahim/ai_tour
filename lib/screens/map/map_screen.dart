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
    final centre = context.read<AppBloc>().state.mapCenter;
    _liveCentre = ValueNotifier(centre);
    // Seed the applied centre so the first [_syncCameraToState] is a no-op.
    //
    // Without this the screen opens framed on the whole north of the country
    // (see [_northAlgeria]) and is then immediately yanked down to whichever
    // single city the state happens to hold — the country view would flash past
    // in one frame and the picker would open zoomed into a city the traveller
    // never chose. The state centre is a *routing* value, not the camera's
    // opening position.
    _appliedCenter = centre;
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

/// The stretch of country the picker opens on: from Tlemcen in the west to El
/// Tarf in the east, and inland far enough to take in Batna and Djelfa.
///
/// The screen used to open at zoom 11, which is a city — one wilaya filled the
/// viewport, and the map's own question ("which parts of the country?") could
/// not be answered without first zooming out to find the rest of it. Framing
/// the populated north instead means every wilaya a route can currently be
/// built in is on screen from the first frame.
final _northAlgeria = LatLngBounds(
  const LatLng(33.6, -2.4),
  const LatLng(37.3, 8.8),
);

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
        // A fit rather than a centre/zoom pair, because the right zoom for
        // "all of northern Algeria" depends on the shape of the screen — the
        // number that frames it on a tall phone crops the east and west ends
        // off a tablet. The bottom padding keeps the fitted region clear of
        // the planner panel docked over it.
        initialCameraFit: CameraFit.bounds(
          bounds: _northAlgeria,
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 180),
        ),
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
