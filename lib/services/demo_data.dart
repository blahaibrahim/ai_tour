import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../models/location.dart';
import '../models/location_data.dart';
import '../models/route.dart';
import '../repositories/mascot_repository.dart';
import '../utils/uuid.dart';

/// Fake data served by every repository when [BackendMonitor] says the
/// backend can't be reached — so the app is always demoable, never a blank
/// screen or a spinner with nowhere to go.
///
/// Built from [allLocations] rather than invented copy: those eight places
/// are real, curated Algeria POIs already shipped in the app for exactly
/// this "no server" situation (see the old itinerary module they used to
/// back), so demo mode looks like the real thing instead of Lorem Ipsum.
class DemoData {
  DemoData._();

  /// One demo city per region in [allLocations], all marked routable so
  /// [AppState.canGenerate] is true offline. Ids are prefixed `demo-` so
  /// nothing ever collides with a real server id if connectivity returns
  /// mid-session.
  static final List<City> cities = [
    for (final region in regions) _cityForRegion(region),
  ];

  static City _cityForRegion(String region) {
    final first = allLocations.firstWhere((l) => l.region == region);
    return City(
      id: 'demo-${_slug(region)}',
      name: region,
      centre: LatLng(first.lat, first.lng),
      rolloutStatus: RolloutStatus.active,
    );
  }

  static const themes = [
    RouteTheme(key: 'history', labelEn: 'History'),
    RouteTheme(key: 'culture', labelEn: 'Culture & arts'),
    RouteTheme(key: 'nature', labelEn: 'Nature & views'),
    RouteTheme(key: 'food', labelEn: 'Food & markets'),
  ];

  static const categories = [
    RouteCategory(key: 'heritage', labelEn: 'Heritage & ruins'),
    RouteCategory(key: 'religious', labelEn: 'Religious sites'),
    RouteCategory(key: 'museum', labelEn: 'Museums & galleries'),
    RouteCategory(key: 'viewpoint', labelEn: 'Viewpoints'),
    RouteCategory(key: 'market', labelEn: 'Markets & food'),
  ];

  /// Builds a route from whichever curated locations sit in [cityId]'s
  /// region. Real generation clusters and orders by travel time; there is no
  /// routing engine to ask offline, so stops are taken in catalogue order and
  /// joined by a straight line — plausible enough for a route nobody can
  /// actually be told to go walk right now.
  static GeneratedRoute route({
    required String cityId,
    required String theme,
    required int timeBudgetMinutes,
    required TransportMode transportMode,
    List<String>? categoryKeys,
    List<String> excludePoiIds = const [],
  }) {
    final city = cities.where((c) => c.id == cityId).firstOrNull ?? cities.first;
    final locations = allLocations
        .where((l) => l.region == city.name && !excludePoiIds.contains(l.id))
        .toList();
    return _buildRoute(
      city: city,
      theme: theme,
      timeBudgetMinutes: timeBudgetMinutes,
      transportMode: transportMode,
      locations: locations.isEmpty ? allLocations.take(1).toList() : locations,
    );
  }

  static GeneratedRoute _buildRoute({
    required City city,
    required String theme,
    required int timeBudgetMinutes,
    required TransportMode transportMode,
    required List<Location> locations,
    String? id,
  }) {
    final stops = <RouteStop>[
      for (var i = 0; i < locations.length; i++)
        RouteStop(
          poiId: locations[i].id,
          sequenceOrder: i,
          clusterId: 0,
          name: locations[i].name,
          description: locations[i].blurb,
          categoryKey: theme,
          lat: locations[i].lat,
          lng: locations[i].lng,
          dwellMinutes: 45,
          checkpointRadiusMeters: 40,
        ),
    ];

    final segments = <RouteSegment>[
      for (var i = 1; i < stops.length; i++)
        RouteSegment(
          mode: transportMode == TransportMode.driving ? SegmentMode.drive : SegmentMode.walk,
          fromPoiId: stops[i - 1].poiId,
          toPoiId: stops[i].poiId,
          clusterId: 0,
          durationMinutes: 12,
          distanceMeters: _metersBetween(stops[i - 1].position, stops[i].position).round(),
          geometry: [stops[i - 1].position, stops[i].position],
        ),
    ];

    final travelMinutes = segments.length * 12;
    final dwellMinutes = stops.fold(0, (sum, s) => sum + s.dwellMinutes);

    return GeneratedRoute(
      id: id ?? 'demo-route-${uuidV4()}',
      cityId: city.id,
      theme: theme,
      timeBudgetMinutes: timeBudgetMinutes,
      transportMode: transportMode,
      stops: stops,
      segments: segments,
      estimatedTotalDurationMinutes: travelMinutes + dwellMinutes,
      dayCountFlag: 1,
      generatedAt: DateTime.now(),
    );
  }

  static RouteProgress progress(String routeId) => RouteProgress(
        id: 'demo-progress-${uuidV4()}',
        routeId: routeId,
        status: 'in_progress',
        visitedPoiIds: const [],
      );

  /// A grounded-sounding answer built from the place's own blurb, since that
  /// is exactly what the real endpoint grounds its LLM answer on.
  static String chatAnswer({
    required String locationName,
    required String blurb,
    required String question,
  }) {
    final trimmedBlurb = blurb.trim();
    final basis = trimmedBlurb.isEmpty
        ? "I don't have more detail on $locationName than what's already on its card"
        : trimmedBlurb;
    return "$basis That's the best I can tell you about $locationName right now — "
        "reconnect to chat live with the guide for a more specific answer.";
  }

  static const List<_TaskTemplate> _taskTemplates = [
    _TaskTemplate('video', 'Record a quick panoramic video of your surroundings.'),
    _TaskTemplate('scan', 'Scan the surrounding area to uncover a hidden historical detail.'),
    _TaskTemplate(
        'mascot', 'A fennec is hiding somewhere here — find it and photograph it.'),
    _TaskTemplate('photo', 'Take a photo that captures what makes this stop worth the trip.'),
  ];

  static Task task({int seed = 0}) {
    final t = _taskTemplates[seed % _taskTemplates.length];
    return Task(type: t.type, label: t.label);
  }

  /// A spawn manifest covering every curated location, not just [routeId]'s
  /// stops — a demo [GeneratedRoute]'s `poiId`s are always drawn from
  /// [allLocations] (see [route]), so keying spawns off the whole catalogue
  /// rather than a passed-in stop list means this needs nothing from the
  /// caller but the id, and still resolves correctly for any demo route.
  /// Mascots sit a few metres from the POI itself — mirrors
  /// [generateTestSpawnPoint]'s testing zone, just centred on the POI instead
  /// of the device.
  static SpawnManifest manifestForRoute(String routeId) {
    final rng = math.Random(routeId.hashCode);
    return SpawnManifest(
      routeId: routeId,
      spawns: [
        for (final loc in allLocations)
          SpawnManifestEntry(
            spawnId: 'demo-spawn-${loc.id}',
            poiId: loc.id,
            location: _jitter(LatLng(loc.lat, loc.lng), rng),
            captureRadiusMeters: 25,
            hotRadiusMeters: 60,
            bandThresholds: const BandThresholds(),
            presentationDistanceMeters: 4.0,
            mascot: const MascotInfo(
              id: 'demo-fennec',
              key: 'fennec',
              name: 'Fennec',
              rarity: 'common',
              modelGlbUrl: 'assets/3d/rigged_animated_fennec.glb',
              modelUsdzUrl: '',
              modelChecksum: '',
              scaleMeters: 0.6,
            ),
          ),
      ],
    );
  }

  static LatLng _jitter(LatLng origin, math.Random rng) {
    const earthRadius = 6371000.0;
    final bearing = rng.nextDouble() * 2 * math.pi;
    final distance = 8 + rng.nextDouble() * 12;
    final lat1 = origin.latitudeInRad;
    final lng1 = origin.longitudeInRad;
    final angularDistance = distance / earthRadius;
    final lat2 = math.asin(math.sin(lat1) * math.cos(angularDistance) +
        math.cos(lat1) * math.sin(angularDistance) * math.cos(bearing));
    final lng2 = lng1 +
        math.atan2(
          math.sin(bearing) * math.sin(angularDistance) * math.cos(lat1),
          math.cos(angularDistance) - math.sin(lat1) * math.sin(lat2),
        );
    return LatLng(lat2 * 180 / math.pi, lng2 * 180 / math.pi);
  }

  static CaptureToken captureToken() => CaptureToken(
        token: 'demo-token-${uuidV4()}',
        expiresAt: DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
      );

  static const CaptureResult captureResult =
      CaptureResult(outcome: 'accepted', points: 30, isFirstCatch: true);

  /// Sentinel `modelPath` for a generated-3D-model artifact when the GPU
  /// backend can't be reached. [MediaCache.getModel] recognises this prefix
  /// and serves the bundled fennec GLB from assets instead of downloading
  /// from Supabase Storage.
  static const String demoModelPath = 'demo:fennec';

  static double _metersBetween(LatLng a, LatLng b) {
    const earthRadiusMeters = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.sin(dLng / 2) * math.sin(dLng / 2) * math.cos(lat1) * math.cos(lat2);
    return 2 * earthRadiusMeters * math.asin(math.min(1, math.sqrt(h)));
  }

  static String _slug(String s) =>
      s.toLowerCase().replaceAll(RegExp(r"[^a-z0-9]+"), '-').replaceAll(RegExp(r'^-+|-+$'), '');
}

class _TaskTemplate {
  const _TaskTemplate(this.type, this.label);
  final String type;
  final String label;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
