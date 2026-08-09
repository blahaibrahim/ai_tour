import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_compass/flutter_compass.dart';

/// Degrees clockwise from true north to radians clockwise from true north —
/// the convention `ar/geo_math.dart` and `ar/mascot_placement.dart` use
/// throughout. Pure, so the conversion is testable without a compass sensor.
double headingToRadians(double degrees) => degrees * math.pi / 180;

/// Wraps the device compass (magnetometer + gyro fusion, done by the plugin)
/// as the fused true heading `H₀` §5.5 of the AR capture plan calls for.
///
/// Declination correction and an explicit calibration-quality signal are
/// listed in the plan but not implemented here — `flutter_compass`'s
/// `accuracy` field means different things on different plugin versions and
/// platforms, so surfacing it as a calibration prompt is deferred rather than
/// asserted on shaky ground. At the plan's default 4 m presentation distance,
/// a 15° heading error only displaces the mascot about a step either way.
class HeadingService {
  HeadingService._();

  static bool get isSupported => FlutterCompass.events != null;

  /// True heading, radians clockwise from north. Empty if the device has no
  /// compass.
  static Stream<double> get radiansStream {
    final events = FlutterCompass.events;
    if (events == null) return const Stream.empty();
    return events
        .map((event) => event.heading)
        .where((heading) => heading != null)
        .map((heading) => headingToRadians(heading!));
  }

  /// One reading, or null if the compass never reports one within [timeout].
  static Future<double?> currentHeading({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    try {
      return await radiansStream.first.timeout(timeout);
    } catch (_) {
      return null;
    }
  }
}
