import 'dart:math' as math;

import 'package:ai_tour/ar/geo_math.dart';
import 'package:ai_tour/ar/spawn_point.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('generateTestSpawnPoint', () {
    const origin = LatLng(36.7538, 3.0588);

    test('always lands within the requested ring', () {
      final random = math.Random(7);
      for (var i = 0; i < 200; i++) {
        final spawn = generateTestSpawnPoint(
          origin,
          minRadiusMeters: 30,
          maxRadiusMeters: 55,
          random: random,
        );
        final distance = geoOffset(origin, spawn).distanceMeters;
        expect(distance, greaterThanOrEqualTo(30 - 0.5));
        expect(distance, lessThanOrEqualTo(55 + 0.5));
      }
    });

    test('is deterministic for a given random source', () {
      final a = generateTestSpawnPoint(origin, random: math.Random(42));
      final b = generateTestSpawnPoint(origin, random: math.Random(42));
      expect(a.latitude, b.latitude);
      expect(a.longitude, b.longitude);
    });

    test('spreads across bearings rather than clustering', () {
      final random = math.Random(3);
      final bearings = [
        for (var i = 0; i < 100; i++)
          geoOffset(
            origin,
            generateTestSpawnPoint(origin, random: random),
          ).bearingRadians,
      ];
      // A crude spread check: at least one point lands in each compass
      // quadrant across 100 samples.
      final quadrants = bearings.map((b) => ((b % (2 * math.pi)) / (math.pi / 2)).floor()).toSet();
      expect(quadrants.length, 4);
    });
  });
}
