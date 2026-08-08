/// Route Generation domain models — the client half of the contract in
/// `backend/server-node/src/routeGeneration/types.ts`.
///
/// These replace the old itinerary shape, which was a flat `List<Location>`
/// with no notion of clusters, transport mode, duration or reachability. The
/// three things that are genuinely new and that the UI has to render:
///
///   * **Segments carry their own mode.** A route is drive legs between
///     clusters and walk legs inside them. The server tags every leg, and the
///     client must never infer the mode from cluster ids — a one-stop cluster
///     would break that inference immediately.
///   * **Duration is estimated up front**, from real travel times plus per-POI
///     dwell time, and is compared against a budget the traveller stated.
///   * **`dayCountFlag`** says the route does not fit that budget. It is not
///     `duration > budget`: it comes from an isochrone check on whether the
///     remaining stops are reachable at all in what's left.
library;

import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';

import 'location.dart';

/// What the traveller asked for. Distinct from [SegmentMode], which is what
/// one leg actually is.
enum TransportMode {
  walking,
  driving,
  hybrid;

  String get wire => name;

  static TransportMode fromWire(String? value) => switch (value) {
        'walking' => TransportMode.walking,
        'driving' => TransportMode.driving,
        _ => TransportMode.hybrid,
      };

  String get label => switch (this) {
        TransportMode.walking => 'Walking',
        TransportMode.driving => 'Driving',
        TransportMode.hybrid => 'Drive + walk',
      };
}

/// The mode of a single leg. A `hybrid` route is made of legs that are each
/// individually one of these.
enum SegmentMode {
  drive,
  walk;

  static SegmentMode fromWire(String? value) =>
      value == 'drive' ? SegmentMode.drive : SegmentMode.walk;
}

/// Whether a city can be routed yet. `planning` cities are listed in the
/// picker but refused by the generate call — the phased rollout, made visible
/// rather than hidden.
enum RolloutStatus {
  planning,
  pilot,
  active;

  static RolloutStatus fromWire(String? value) => switch (value) {
        'pilot' => RolloutStatus.pilot,
        'active' => RolloutStatus.active,
        _ => RolloutStatus.planning,
      };

  bool get isRoutable => this != RolloutStatus.planning;
}

class City extends Equatable {
  const City({
    required this.id,
    required this.name,
    this.nameFr,
    this.nameAr,
    this.centre,
    this.rolloutStatus = RolloutStatus.planning,
  });

  final String id;
  final String name;
  final String? nameFr;
  final String? nameAr;
  final LatLng? centre;
  final RolloutStatus rolloutStatus;

  factory City.fromJson(Map<String, dynamic> json) {
    final centre = json['centre'] as Map<String, dynamic>?;
    return City(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      nameFr: json['name_fr'] as String?,
      nameAr: json['name_ar'] as String?,
      centre: centre == null
          ? null
          : LatLng((centre['lat'] as num).toDouble(), (centre['lng'] as num).toDouble()),
      rolloutStatus: RolloutStatus.fromWire(json['rollout_status'] as String?),
    );
  }

  @override
  List<Object?> get props => [id, name, nameFr, nameAr, centre, rolloutStatus];
}

/// A POI category, as the filter chips render it.
class RouteCategory extends Equatable {
  const RouteCategory({
    required this.key,
    required this.labelEn,
    this.labelFr,
    this.labelAr,
    this.iconRef,
    this.colorHex,
  });

  final String key;
  final String labelEn;
  final String? labelFr;
  final String? labelAr;
  final String? iconRef;
  final String? colorHex;

  factory RouteCategory.fromJson(Map<String, dynamic> json) => RouteCategory(
        key: json['key'] as String,
        labelEn: json['label_en'] as String? ?? json['key'] as String,
        labelFr: json['label_fr'] as String?,
        labelAr: json['label_ar'] as String?,
        iconRef: json['icon_ref'] as String?,
        colorHex: json['color_hex'] as String?,
      );

  @override
  List<Object?> get props => [key, labelEn, labelFr, labelAr, iconRef, colorHex];
}

/// A theme, the primary filter the request is built around.
class RouteTheme extends Equatable {
  const RouteTheme({required this.key, required this.labelEn, this.labelFr, this.labelAr});

  final String key;
  final String labelEn;
  final String? labelFr;
  final String? labelAr;

  factory RouteTheme.fromJson(Map<String, dynamic> json) => RouteTheme(
        key: json['key'] as String,
        labelEn: json['label_en'] as String? ?? json['key'] as String,
        labelFr: json['label_fr'] as String?,
        labelAr: json['label_ar'] as String?,
      );

  @override
  List<Object?> get props => [key, labelEn, labelFr, labelAr];
}

/// One stop in a generated route.
class RouteStop extends Equatable {
  const RouteStop({
    required this.poiId,
    required this.sequenceOrder,
    required this.clusterId,
    required this.name,
    required this.categoryKey,
    required this.lat,
    required this.lng,
    required this.dwellMinutes,
    required this.checkpointRadiusMeters,
    this.description,
    this.openingHoursRaw,
    this.photoUrl,
    this.photoAttribution,
    this.photoLicense,
    this.photoSourceUrl,
    this.arContentId,
    this.stampId,
  });

  final String poiId;
  final int sequenceOrder;

  /// Which walkable group this stop belongs to. Stops sharing a cluster are
  /// walked between; a change of cluster means a drive leg sits in between.
  final int clusterId;

  final String name;
  final String? description;
  final String categoryKey;
  final double lat;
  final double lng;

  /// Expected time spent here, from `pois.avg_visit_duration_minutes`. Part of
  /// the total duration alongside travel time.
  final int dwellMinutes;

  /// Per-POI, never global: GPS drift in dense old-city streets makes one
  /// global radius wrong in both directions. The AR trigger service uses this
  /// to decide arrival.
  final int checkpointRadiusMeters;

  final String? openingHoursRaw;
  final String? photoUrl;
  final String? photoAttribution;
  final String? photoLicense;
  final String? photoSourceUrl;
  final String? arContentId;
  final String? stampId;

  LatLng get position => LatLng(lat, lng);

  factory RouteStop.fromJson(Map<String, dynamic> json) => RouteStop(
        poiId: json['poi_id'] as String,
        sequenceOrder: (json['sequence_order'] as num?)?.toInt() ?? 0,
        clusterId: (json['cluster_id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
        categoryKey: json['category_key'] as String? ?? '',
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        dwellMinutes: (json['dwell_minutes'] as num?)?.toInt() ?? 15,
        checkpointRadiusMeters: (json['checkpoint_radius_meters'] as num?)?.toInt() ?? 40,
        openingHoursRaw: json['opening_hours_raw'] as String?,
        photoUrl: json['photo_url'] as String?,
        photoAttribution: json['photo_attribution'] as String?,
        photoLicense: json['photo_license'] as String?,
        photoSourceUrl: json['photo_source_url'] as String?,
        arContentId: json['ar_content_id'] as String?,
        stampId: json['stamp_id'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'poi_id': poiId,
        'sequence_order': sequenceOrder,
        'cluster_id': clusterId,
        'name': name,
        'description': description,
        'category_key': categoryKey,
        'lat': lat,
        'lng': lng,
        'dwell_minutes': dwellMinutes,
        'checkpoint_radius_meters': checkpointRadiusMeters,
        'opening_hours_raw': openingHoursRaw,
        'photo_url': photoUrl,
      };

  /// Adapts a stop to the app's general "a place, displayable" model, so the
  /// detail overlay, the folder, the AR screen and the saved-locations flow
  /// keep working unchanged. Those screens are about places, not about routes;
  /// only the route-generation surfaces need to know a [RouteStop] exists.
  Location toLocation({String? regionLabel}) => Location(
        id: poiId,
        name: name,
        region: regionLabel ?? '',
        category: categoryKey,
        distanceKm: 0,
        blurb: description ?? '',
        lat: lat,
        lng: lng,
        remotePhotoUrl: photoUrl,
        task: const Task(type: 'photo', label: 'Take a photo of this location.'),
      );

  @override
  List<Object?> get props => [poiId, sequenceOrder, clusterId, name, lat, lng];
}

/// One leg of the route, with the mode tag the map and the overview render.
class RouteSegment extends Equatable {
  const RouteSegment({
    required this.mode,
    required this.durationMinutes,
    required this.distanceMeters,
    required this.geometry,
    this.fromPoiId,
    this.toPoiId,
    this.clusterId,
  });

  final SegmentMode mode;
  final String? fromPoiId;
  final String? toPoiId;

  /// Null for an inter-cluster drive leg — it belongs to no cluster.
  final int? clusterId;

  final int durationMinutes;
  final int distanceMeters;
  final List<LatLng> geometry;

  factory RouteSegment.fromJson(Map<String, dynamic> json) => RouteSegment(
        mode: SegmentMode.fromWire(json['mode'] as String?),
        fromPoiId: json['from_poi_id'] as String?,
        toPoiId: json['to_poi_id'] as String?,
        clusterId: (json['cluster_id'] as num?)?.toInt(),
        durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 0,
        distanceMeters: (json['distance_meters'] as num?)?.toInt() ?? 0,
        geometry: (json['geometry'] as List<dynamic>? ?? [])
            .whereType<List<dynamic>>()
            .map((p) => LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()))
            .toList(),
      );

  String get distanceLabel => distanceMeters >= 1000
      ? '${(distanceMeters / 1000).toStringAsFixed(1)} km'
      : '$distanceMeters m';

  @override
  List<Object?> get props => [mode, fromPoiId, toPoiId, clusterId, durationMinutes];
}

/// A generated route, exactly as `POST /api/routes` returns it.
class GeneratedRoute extends Equatable {
  const GeneratedRoute({
    required this.id,
    required this.cityId,
    required this.theme,
    required this.timeBudgetMinutes,
    required this.transportMode,
    required this.stops,
    required this.segments,
    required this.estimatedTotalDurationMinutes,
    required this.dayCountFlag,
    this.generatedAt,
  });

  final String id;
  final String cityId;
  final String theme;
  final int timeBudgetMinutes;
  final TransportMode transportMode;
  final List<RouteStop> stops;
  final List<RouteSegment> segments;
  final int estimatedTotalDurationMinutes;

  /// 1 when the route fits the budget; 2+ when the remaining stops aren't
  /// reachable in what's left of it.
  final int dayCountFlag;

  final DateTime? generatedAt;

  factory GeneratedRoute.fromJson(Map<String, dynamic> json) => GeneratedRoute(
        id: json['id'] as String,
        cityId: json['city_id'] as String? ?? '',
        theme: json['theme'] as String? ?? '',
        timeBudgetMinutes: (json['time_budget_minutes'] as num?)?.toInt() ?? 0,
        transportMode: TransportMode.fromWire(json['transport_mode'] as String?),
        stops: (json['stops'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(RouteStop.fromJson)
            .toList(),
        segments: (json['segments'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(RouteSegment.fromJson)
            .toList(),
        estimatedTotalDurationMinutes:
            (json['estimated_total_duration_minutes'] as num?)?.toInt() ?? 0,
        dayCountFlag: (json['day_count_flag'] as num?)?.toInt() ?? 1,
        generatedAt: DateTime.tryParse(json['generated_at'] as String? ?? ''),
      );

  /// True when the route needs more than the stated budget — the signal the
  /// result screen warns on.
  bool get needsMoreThanOneDay => dayCountFlag > 1;

  /// Distinct clusters, in visiting order. One cluster means a single walking
  /// loop; more means the route drives between them.
  List<int> get clusterOrder {
    final seen = <int>{};
    return [
      for (final s in stops)
        if (seen.add(s.clusterId)) s.clusterId,
    ];
  }

  int get driveMinutes => segments
      .where((s) => s.mode == SegmentMode.drive)
      .fold(0, (sum, s) => sum + s.durationMinutes);

  int get walkMinutes => segments
      .where((s) => s.mode == SegmentMode.walk)
      .fold(0, (sum, s) => sum + s.durationMinutes);

  int get dwellMinutes => stops.fold(0, (sum, s) => sum + s.dwellMinutes);

  /// The leg that leads *into* [stop], or null for the first stop.
  RouteSegment? segmentInto(RouteStop stop) {
    for (final segment in segments) {
      if (segment.toPoiId == stop.poiId) return segment;
    }
    return null;
  }

  GeneratedRoute copyWith({List<RouteStop>? stops, List<RouteSegment>? segments}) =>
      GeneratedRoute(
        id: id,
        cityId: cityId,
        theme: theme,
        timeBudgetMinutes: timeBudgetMinutes,
        transportMode: transportMode,
        stops: stops ?? this.stops,
        segments: segments ?? this.segments,
        estimatedTotalDurationMinutes: estimatedTotalDurationMinutes,
        dayCountFlag: dayCountFlag,
        generatedAt: generatedAt,
      );

  @override
  List<Object?> get props => [
        id,
        cityId,
        theme,
        timeBudgetMinutes,
        transportMode,
        stops,
        segments,
        estimatedTotalDurationMinutes,
        dayCountFlag,
      ];
}

/// Progress through a route being walked. Mutable state, deliberately separate
/// from the immutable [GeneratedRoute] — the route never changes as you walk.
class RouteProgress extends Equatable {
  const RouteProgress({
    required this.id,
    required this.routeId,
    required this.status,
    required this.visitedPoiIds,
  });

  final String id;
  final String routeId;
  final String status;
  final List<String> visitedPoiIds;

  factory RouteProgress.fromJson(Map<String, dynamic> json) => RouteProgress(
        id: json['id'] as String,
        routeId: json['route_id'] as String? ?? '',
        status: json['status'] as String? ?? 'in_progress',
        visitedPoiIds: (json['visited_poi_ids'] as List<dynamic>? ?? [])
            .whereType<String>()
            .toList(),
      );

  @override
  List<Object?> get props => [id, routeId, status, visitedPoiIds];
}

/// Formats a duration in minutes the way the route surfaces show it.
String formatMinutes(int minutes) {
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
}
