import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'geo_math.dart';

/// Default spawn ring around the tester, metres. Deliberately starts past the
/// default HOT/BURNING boundary (25 m) so the hunt loop — hysteresis, the
/// thermometer, the walk itself — actually gets exercised instead of the
/// mascot being caught the instant the screen opens.
const double kTestSpawnMinRadiusMeters = 5;
const double kTestSpawnMaxRadiusMeters = 10;

/// Generates a mascot spawn point near [origin], for AR-hunt testing mode.
///
/// The real design (§5.1 of the AR capture plan) draws spawn points from a
/// hand-authored, safety-reviewed polygon around each POI — isochrone minus
/// roads and water, never a raw radius, because a radius can drop a mascot in
/// traffic. There is no such polygon around an arbitrary tester's current
/// position, so this is a deliberately smaller substitute for testing away
/// from real POIs: a uniformly-random point between [minRadiusMeters] and
/// [maxRadiusMeters] of [origin]. It exists only to exercise the hunt loop
/// and AR placement without travelling to a curated POI — swap in the real
/// spawn-zone pipeline before this ever points at a live route.
LatLng generateTestSpawnPoint(
  LatLng origin, {
  double minRadiusMeters = kTestSpawnMinRadiusMeters,
  double maxRadiusMeters = kTestSpawnMaxRadiusMeters,
  math.Random? random,
}) {
  final rng = random ?? math.Random();
  final bearing = rng.nextDouble() * 2 * math.pi;

  // Uniform over the ring's area rather than its radius, so points don't
  // bunch up near the inner edge.
  final minSq = minRadiusMeters * minRadiusMeters;
  final maxSq = maxRadiusMeters * maxRadiusMeters;
  final radius = math.sqrt(minSq + rng.nextDouble() * (maxSq - minSq));

  return destinationPoint(origin, bearing, radius);
}
