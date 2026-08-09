import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Mean Earth radius, metres — matches the AR capture plan's §5.2 constant.
const double kEarthRadiusMeters = 6371000;

/// The metric offset from one geographic point to another, plus the distance
/// and true bearing it collapses to.
///
/// Uses the equirectangular approximation the plan specifies for the hunt
/// loop: exact enough under a few hundred metres (< 0.1% error) and cheap
/// enough to run on every GPS fix on a mid-range phone.
class GeoOffset {
  const GeoOffset({
    required this.east,
    required this.north,
    required this.distanceMeters,
    required this.bearingRadians,
  });

  /// Metres east of the origin (negative is west).
  final double east;

  /// Metres north of the origin (negative is south).
  final double north;

  /// Ground distance, metres.
  final double distanceMeters;

  /// True bearing from the origin to the target, radians clockwise from
  /// north.
  final double bearingRadians;
}

/// The offset from [from] to [to] — dE, dN, distance and true bearing, per
/// §5.2 of the AR capture plan. Reused unchanged by the AR placement step
/// (§5.5): the hunt loop and the AR loop share this one piece of math.
GeoOffset geoOffset(LatLng from, LatLng to) {
  final phiU = _radians(from.latitude);
  final north = kEarthRadiusMeters * _radians(to.latitude - from.latitude);
  final east = kEarthRadiusMeters *
      _radians(to.longitude - from.longitude) *
      math.cos(phiU);
  final distance = math.sqrt(east * east + north * north);
  final bearing = math.atan2(east, north);
  return GeoOffset(
    east: east,
    north: north,
    distanceMeters: distance,
    bearingRadians: bearing,
  );
}

/// The inverse of [geoOffset]: the point [distanceMeters] away from [origin]
/// at true [bearingRadians] (clockwise from north).
///
/// Used to generate a nearby spawn point for AR-hunt testing mode — see
/// `ar/spawn_point.dart`.
LatLng destinationPoint(
  LatLng origin,
  double bearingRadians,
  double distanceMeters,
) {
  final north = distanceMeters * math.cos(bearingRadians);
  final east = distanceMeters * math.sin(bearingRadians);
  final dLat = north / kEarthRadiusMeters;
  final dLng = east / (kEarthRadiusMeters * math.cos(_radians(origin.latitude)));
  return LatLng(
    origin.latitude + dLat * 180 / math.pi,
    origin.longitude + dLng * 180 / math.pi,
  );
}

double _radians(double degrees) => degrees * math.pi / 180;
