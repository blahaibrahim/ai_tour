import 'dart:async';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

import '../models/route.dart';

/// GPS-based stop arrival detection — works entirely offline.
///
/// Subscribes to the device's position stream and checks each fix against the
/// current stop's coordinates and [RouteStop.checkpointRadiusMeters]. When the
/// traveller enters the radius, [onArrival] fires with the stop's index and
/// POI id.
///
/// Lifecycle:
///   * [start] when the route is accepted (overview screen).
///   * [updateCurrentStop] when the traveller advances to the next stop.
///   * [stop] when the tour is left or the bloc is closed.
///
/// GPS does not require internet connectivity, so arrival detection keeps
/// working through tunnels, dead zones, and airplane-mode-with-GPS scenarios.
class ArrivalDetector {
  ArrivalDetector({required this.onArrival});

  /// Called when the traveller enters a stop's checkpoint radius.
  /// Parameters: `(int stopIndex, String poiId)`.
  final void Function(int stopIndex, String poiId) onArrival;

  StreamSubscription<Position>? _positionSub;
  List<RouteStop> _stops = const [];
  int _currentStopIdx = 0;
  bool _arrivedAtCurrent = false;

  /// Starts listening to GPS. Safe to call multiple times — restarts if
  /// already running.
  Future<void> start({
    required List<RouteStop> stops,
    required int currentStopIdx,
  }) async {
    await stop();
    _stops = stops;
    _currentStopIdx = currentStopIdx;
    _arrivedAtCurrent = false;

    // Don't start if permissions are missing — arrival detection is a bonus,
    // not a requirement. The tour still works without it.
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) return;
    } catch (_) {
      return;
    }

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        // Only wake up when the device has moved at least 10 m — cuts GPS
        // power consumption to a fraction of a continuous stream while still
        // detecting arrivals promptly. A checkpoint radius is typically 40 m,
        // so a 10 m filter gives 3–4 updates inside the zone.
        distanceFilter: 10,
      ),
    ).listen(_onPosition);
  }

  /// Updates which stop to check against, without restarting the GPS stream.
  void updateCurrentStop(int index) {
    _currentStopIdx = index;
    _arrivedAtCurrent = false;
  }

  /// Stops GPS listening. Idempotent.
  Future<void> stop() async {
    await _positionSub?.cancel();
    _positionSub = null;
  }

  void _onPosition(Position pos) {
    if (_arrivedAtCurrent) return;
    if (_currentStopIdx >= _stops.length) return;

    final stop = _stops[_currentStopIdx];
    final distanceM = _haversineMeters(
      pos.latitude, pos.longitude,
      stop.lat, stop.lng,
    );

    if (distanceM <= stop.checkpointRadiusMeters) {
      _arrivedAtCurrent = true;
      onArrival(_currentStopIdx, stop.poiId);
    }
  }

  /// Great-circle distance in metres, inlined to avoid an allocation per fix.
  static double _haversineMeters(
    double lat1, double lng1,
    double lat2, double lng2,
  ) {
    const earthRadiusM = 6371000.0;
    final dLat = _radians(lat2 - lat1);
    final dLng = _radians(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_radians(lat1)) * math.cos(_radians(lat2)) *
        math.sin(dLng / 2) * math.sin(dLng / 2);
    return 2 * earthRadiusM * math.asin(math.min(1, math.sqrt(a)));
  }

  static double _radians(double deg) => deg * math.pi / 180;
}
