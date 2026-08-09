import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'geo_math.dart';
import 'proximity.dart';
import 'sampling.dart';

/// Why the hunt can't start, mirroring the checks `LocationSearchBar` already
/// makes before reading a position.
enum HuntAvailability {
  ready,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
}

/// One tick of the hunt: how hot it is, and everything the C1 presentation
/// layer needs to render it.
class HuntState {
  const HuntState({
    required this.band,
    required this.distanceMeters,
    required this.bearingRadians,
    required this.accuracyMeters,
  });

  final ProximityBand band;
  final double distanceMeters;

  /// True bearing from the visitor to the mascot, radians clockwise from
  /// north. Independent of which way the phone is pointing — combine with a
  /// live compass heading to draw a direction arrow.
  final double bearingRadians;
  final double accuracyMeters;

  bool get canCapture => band == ProximityBand.burning;
}

/// C2 — "the single source of truth for which mascot am I hunting and how hot
/// am I", per the AR capture plan. The pure hysteresis/debounce state machine
/// lives in [HuntBandTracker] (`ar/proximity.dart`) so it's unit-testable
/// without a location plugin; this class is the impure shell around it — the
/// GPS stream, the accuracy gate, and the adaptive resampling from §5.4.
class HuntSessionController {
  HuntSessionController({
    required this.target,
    this.thresholds = const BandThresholds(),
  }) : _tracker = HuntBandTracker(thresholds: thresholds);

  /// Where the mascot is.
  final LatLng target;
  final BandThresholds thresholds;
  final HuntBandTracker _tracker;

  final StreamController<HuntState> _controller =
      StreamController<HuntState>.broadcast();

  Stream<HuntState> get stream => _controller.stream;
  HuntState? lastState;

  StreamSubscription<Position>? _sub;
  ProximityBand _subscribedBand = ProximityBand.frozen;
  bool _disposed = false;

  /// Requests permission, takes one immediate fix, and starts the adaptive
  /// stream. Safe to call once; returns why the hunt can't proceed if it
  /// can't.
  Future<HuntAvailability> start() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return HuntAvailability.serviceDisabled;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      return HuntAvailability.permissionDenied;
    }
    if (permission == LocationPermission.deniedForever) {
      return HuntAvailability.permissionDeniedForever;
    }

    // Seed immediately rather than waiting on the stream's first
    // distance-filtered update, which can take a while at FROZEN's 100 m
    // filter if the visitor hasn't moved yet.
    try {
      final first = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      _onPosition(first);
    } catch (_) {
      // Fall through to the stream — a slow/failed first fix isn't fatal.
    }

    _resubscribe(_tracker.band);
    return HuntAvailability.ready;
  }

  void _resubscribe(ProximityBand band) {
    final profile = samplingFor(band);
    _sub?.cancel();
    _sub = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy:
            profile.highAccuracy ? LocationAccuracy.high : LocationAccuracy.medium,
        distanceFilter: profile.distanceFilterMeters,
      ),
    ).listen(_onPosition);
    _subscribedBand = band;
  }

  void _onPosition(Position position) {
    if (_disposed) return;

    // Drop outright rather than mis-score (§5.3) — the previous band and
    // reading simply hold.
    if (position.accuracy > kAccuracyGateMeters) return;

    final offset =
        geoOffset(LatLng(position.latitude, position.longitude), target);
    final band = _tracker.onFix(offset.distanceMeters);

    final state = HuntState(
      band: band,
      distanceMeters: offset.distanceMeters,
      bearingRadians: offset.bearingRadians,
      accuracyMeters: position.accuracy,
    );
    lastState = state;
    _controller.add(state);

    if (band != _subscribedBand) _resubscribe(band);
  }

  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _controller.close();
  }
}
