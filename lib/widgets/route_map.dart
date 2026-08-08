import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/route.dart';
import '../theme.dart';

/// Draws a generated route: its legs as polylines and its stops as numbered
/// pins.
///
/// The route response has carried per-leg `geometry` — the actual line to
/// follow, not a straight hop between coordinates — since the module was
/// specified, and nothing in the app drew it. A tour planner that can only
/// describe its route as a list is asking the traveller to hold the shape of
/// the city in their head; the shape is the one thing a map is better at than
/// text.
///
/// Two rules the rendering keeps:
///
///   * **The mode tag comes from the server, never from the cluster ids.** A
///     leg is drive or walk because [RouteSegment.mode] says so. Inferring it
///     from "did the cluster change" breaks the moment a cluster holds one
///     stop.
///   * **Missing geometry degrades to a straight line, and looks like one.**
///     A leg whose geometry the routing provider couldn't supply is drawn
///     dotted and thin, so a straight line is legible as "we don't know the
///     path" rather than as a claim that the road runs that way.
class RouteMap extends StatefulWidget {
  const RouteMap({
    super.key,
    required this.route,
    this.activeStopIndex,
    this.onStopTap,
    this.interactive = true,
    this.showPaths = false,
    this.showNames = false,
    this.padding = const EdgeInsets.all(48),
  });

  final GeneratedRoute route;
  final bool showPaths;
  final bool showNames;

  /// The stop the traveller is on, drawn larger and in the accent fill. Null on
  /// the planning surfaces, where no stop is "current" yet.
  final int? activeStopIndex;

  final void Function(RouteStop stop)? onStopTap;

  /// False for a preview embedded in a scrolling page — a pannable map inside a
  /// scroll view steals every vertical drag, so the page can't be scrolled past
  /// it.
  final bool interactive;

  /// Inset for the initial fit, so pins near the edge aren't half off-screen.
  final EdgeInsets padding;

  @override
  State<RouteMap> createState() => _RouteMapState();
}

/// Walk legs are dashed. Not `const`: `StrokePattern.dashed` asserts on
/// `segments.length`, which const evaluation can't do, so a const call site is
/// a compile error.
final StrokePattern _walkDash = StrokePattern.dashed(segments: const [9, 7]);

class _RouteMapState extends State<RouteMap> {
  final MapController _controller = MapController();

  /// Every coordinate the route touches: stop positions plus every vertex of
  /// every leg. Legs matter — a drive that arcs around a bay leaves the box
  /// drawn from its endpoints alone, and the middle of the route would sit off
  /// screen.
  List<LatLng> get _allPoints => [
        for (final stop in widget.route.stops) stop.position,
        for (final segment in widget.route.segments) ...segment.geometry,
      ];

  LatLngBounds? get _bounds {
    final points = _allPoints;
    if (points.isEmpty) return null;
    // A single stop has no extent, and LatLngBounds of one point makes the fit
    // resolve to the maximum zoom — a street-level view of one pin with no
    // context. Give it a small box instead.
    if (points.length == 1) {
      final p = points.first;
      return LatLngBounds(
        LatLng(p.latitude - 0.004, p.longitude - 0.004),
        LatLng(p.latitude + 0.004, p.longitude + 0.004),
      );
    }
    return LatLngBounds.fromPoints(points);
  }

  @override
  void didUpdateWidget(RouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refining a route changes its stops, and `initialCameraFit` only applies
    // once — without this the camera stays framed on the route that was
    // replaced.
    if (oldWidget.route.stops != widget.route.stops) {
      final bounds = _bounds;
      if (bounds == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _controller.fitCamera(
          CameraFit.bounds(bounds: bounds, padding: widget.padding),
        );
      });
    }
  }

  /// One polyline per leg rather than one for the whole route, because the
  /// stroke has to change at every mode change.
  List<Polyline> _buildPolylines() {
    final lines = <Polyline>[];

    for (final segment in widget.route.segments) {
      final isDrive = segment.mode == SegmentMode.drive;
      final points = segment.geometry.length >= 2
          ? segment.geometry
          : _fallbackGeometry(segment);
      if (points.length < 2) continue;

      final hasRealGeometry = segment.geometry.length >= 2;

      lines.add(
        Polyline(
          points: points,
          color: isDrive ? AppTheme.driveColor : AppTheme.walkColor,
          strokeWidth: isDrive ? 5 : 4,
          // A dotted stroke reads as "approximate" without needing a legend,
          // which is exactly the claim being made about a leg we had to
          // reconstruct from its endpoints.
          pattern: hasRealGeometry
              ? (isDrive ? const StrokePattern.solid() : _walkDash)
              : const StrokePattern.dotted(),
          // A casing keeps the line legible over dark map features; without it
          // a blue route across a blue bay disappears.
          borderStrokeWidth: 2.5,
          borderColor: Colors.white.withValues(alpha: 0.9),
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
      );
    }

    return lines;
  }

  /// The endpoints of a leg the provider gave no geometry for.
  List<LatLng> _fallbackGeometry(RouteSegment segment) {
    LatLng? find(String? poiId) {
      if (poiId == null) return null;
      for (final stop in widget.route.stops) {
        if (stop.poiId == poiId) return stop.position;
      }
      return null;
    }

    final from = find(segment.fromPoiId);
    final to = find(segment.toPoiId);
    if (from == null || to == null) return const [];
    return [from, to];
  }

  List<Marker> _buildMarkers() {
    return [
      for (var i = 0; i < widget.route.stops.length; i++)
        Marker(
          point: widget.route.stops[i].position,
          width: 200,
          height: 100,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              _StopPin(
                index: i,
                stop: widget.route.stops[i],
                isActive: widget.activeStopIndex == i,
                isVisited:
                    widget.activeStopIndex != null && i < widget.activeStopIndex!,
                onTap: widget.onStopTap == null
                    ? null
                    : () => widget.onStopTap!(widget.route.stops[i]),
              ),
              if (widget.showNames)
                Positioned(
                  top: 50 + 18, // 50 is center height, 18 is slightly more than pin radius
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.surface.withValues(alpha: 0.9),
                        borderRadius: AppTheme.brSm,
                        boxShadow: AppTheme.shadowSm,
                      ),
                      child: Text(
                        widget.route.stops[i].name,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.text,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final bounds = _bounds;
    if (bounds == null) {
      return const ColoredBox(color: AppTheme.surfaceAlt);
    }

    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: bounds,
          padding: widget.padding,
          // Past this a two-stop route in the same square fills the screen with
          // roof outlines and no landmarks to orient by.
          maxZoom: 16.5,
        ),
        interactionOptions: InteractionOptions(
          flags: widget.interactive
              ? InteractiveFlag.all & ~InteractiveFlag.rotate
              : InteractiveFlag.none,
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
        if (widget.showPaths) PolylineLayer(polylines: _buildPolylines()),
        MarkerLayer(markers: _buildMarkers()),
        // Both CARTO's and OpenStreetMap's terms require visible credit. The
        // app's other map omitted it, which is a licence violation rather than
        // a style choice.
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

/// A numbered stop pin. Visited / current / upcoming are three different fills
/// so the map answers "where am I on this route" at a glance.
class _StopPin extends StatelessWidget {
  const _StopPin({
    required this.index,
    required this.stop,
    required this.isActive,
    required this.isVisited,
    this.onTap,
  });

  final int index;
  final RouteStop stop;
  final bool isActive;
  final bool isVisited;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch ((isActive, isVisited)) {
      (true, _) => (AppTheme.accent, AppTheme.onAccent),
      (_, true) => (AppTheme.success, Colors.white),
      _ => (AppTheme.surface, AppTheme.accentDark),
    };

    final size = isActive ? 34.0 : 28.0;

    return Semantics(
      button: onTap != null,
      label: 'Stop ${index + 1}, ${stop.name}'
          '${isActive ? ', current stop' : ''}${isVisited ? ', visited' : ''}',
      child: GestureDetector(
        onTap: onTap,
        // The pin is smaller than the minimum tap target, so the marker's full
        // 44dp box stays hittable around it rather than only the visible disc.
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: AnimatedContainer(
            duration: AppTheme.motionBase,
            curve: AppTheme.motionCurve,
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: AppTheme.shadowSm,
            ),
            child: isVisited
                ? Icon(Icons.check_rounded, size: size * 0.55, color: foreground)
                : Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: isActive ? 14 : 12.5,
                      fontWeight: FontWeight.w700,
                      color: foreground,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// The map's colour key.
///
/// Without it the two stroke colours are decoration; the drive/walk split is
/// the main thing the hybrid transport model produces, so it is worth six
/// millimetres of vertical space to make the map self-explanatory.
class RouteMapLegend extends StatelessWidget {
  const RouteMapLegend({super.key, required this.route});

  final GeneratedRoute route;

  @override
  Widget build(BuildContext context) {
    final hasDrive = route.segments.any((s) => s.mode == SegmentMode.drive);

    return Wrap(
      spacing: AppTheme.space3,
      runSpacing: AppTheme.space2,
      children: [
        if (hasDrive)
          _LegendEntry(
            color: AppTheme.driveColor,
            dashed: false,
            label: 'Drive · ${formatMinutes(route.driveMinutes)}',
          ),
        _LegendEntry(
          color: AppTheme.walkColor,
          dashed: true,
          label: 'Walk · ${formatMinutes(route.walkMinutes)}',
        ),
      ],
    );
  }
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({
    required this.color,
    required this.dashed,
    required this.label,
  });

  final Color color;
  final bool dashed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size(18, 3),
          painter: _LineSwatchPainter(color: color, dashed: dashed),
        ),
        const SizedBox(width: AppTheme.space2),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.text.withValues(alpha: 0.75),
          ),
        ),
      ],
    );
  }
}

/// Draws the legend's line sample in the same solid/dashed language the map
/// uses, so the key is the thing it describes rather than a coloured square.
class _LineSwatchPainter extends CustomPainter {
  const _LineSwatchPainter({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final y = size.height / 2;
    if (!dashed) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      return;
    }

    const dash = 5.0;
    const gap = 4.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, y),
        Offset((x + dash).clamp(0, size.width), y),
        paint,
      );
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_LineSwatchPainter old) =>
      old.color != color || old.dashed != dashed;
}
