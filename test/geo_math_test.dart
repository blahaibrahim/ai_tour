import 'dart:math' as math;

import 'package:ai_tour/ar/geo_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('geoOffset', () {
    const origin = LatLng(36.7538, 3.0588); // Algiers, roughly

    test('a point due north has bearing zero', () {
      final north = destinationPoint(origin, 0, 100);
      final offset = geoOffset(origin, north);
      expect(offset.bearingRadians, closeTo(0, 1e-6));
      expect(offset.distanceMeters, closeTo(100, 0.5));
    });

    test('a point due east has bearing pi/2', () {
      final east = destinationPoint(origin, math.pi / 2, 100);
      final offset = geoOffset(origin, east);
      expect(offset.bearingRadians, closeTo(math.pi / 2, 1e-6));
      expect(offset.distanceMeters, closeTo(100, 0.5));
    });

    test('the same point is zero distance away', () {
      final offset = geoOffset(origin, origin);
      expect(offset.distanceMeters, closeTo(0, 1e-9));
    });

    test('round-trips through destinationPoint at various bearings', () {
      for (final bearing in [0.0, 0.7, math.pi, 4.2, 2 * math.pi - 0.1]) {
        for (final distance in [10.0, 50.0, 250.0]) {
          final target = destinationPoint(origin, bearing, distance);
          final offset = geoOffset(origin, target);
          expect(offset.distanceMeters, closeTo(distance, distance * 0.001 + 0.05));
          // Bearings can wrap at +/- pi; compare via the shortest angular
          // difference rather than raw equality.
          final diff = (offset.bearingRadians - bearing).abs() % (2 * math.pi);
          final wrapped = math.min(diff, 2 * math.pi - diff);
          expect(wrapped, closeTo(0, 1e-3));
        }
      }
    });
  });
}
