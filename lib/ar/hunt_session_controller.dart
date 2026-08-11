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

/// The subset of a [SamplingProfile] that actually shapes a position
/// subscription. `minInterval` is deliberately excluded: the base
/// [LocationSettings] has nowhere to put it, so two bands that differ only in
/// their interval would otherwise trigger a pointless resubscribe.
class _SubscriptionKey {
  const _SubscriptionKey(this.accuracy, this.distanceFilter);

  _SubscriptionKey.of(SamplingProfile profile)
      : accuracy = profile.highAccuracy
            ? LocationAccuracy.high
            : LocationAccuracy.medium,
        distanceFilter = profile.distanceFilterMeters;

  final LocationAccuracy accuracy;
  final int distanceFilter;

  @override
  bool operator ==(Object other) =>
      other is _SubscriptionKey &&
      other.accuracy == accuracy &&
      other.distanceFilter == distanceFilter;

  @override
  int get hashCode => Object.hash(accuracy, distanceFilter);
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

  /// The most recent tick, kept so a listener that attaches after [start]
  /// can render immediately instead of waiting on the next fix. The seed fix
  /// is taken before anyone can subscribe to a broadcast stream, so without
  /// this it would be dropped on the floor.
  HuntState? lastState;

  StreamSubscription<Position>? _sub;

  /// The settings the live subscription was opened with, or null when there
  /// is none. Compared against the *effective* location settings rather than
  /// the band, because several bands map to the same subscription (only the
  /// medium→high accuracy step actually differs) and every needless
  /// resubscribe is a chance to lose the stream.
  _SubscriptionKey? _subscribedAs;

  /// Guards against stacking resubscribes while an earlier one is still
  /// awaiting `cancel()`.
  bool _resubscribing = false;

  /// Guards against stacking one-shot fixes — see [_pollOnce].
  bool _polling = false;

  Timer? _watchdog;
  DateTime? _lastFixAt;
  bool _disposed = false;

  /// How long the readout may go without a fix before the watchdog forces a
  /// one-shot poll and rebuilds the subscription. Comfortably longer than the
  /// slowest band's expected cadence, so a normal quiet stretch isn't treated
  /// as a stall.
  static const Duration _stallTimeout = Duration(seconds: 20);

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

    // Seed immediately rather than waiting on the stream's first update,
    // which can take several seconds to arrive even with no distance filter.
    await _pollOnce();
    if (_disposed) return HuntAvailability.ready;

    await _resubscribe(_tracker.band);
    _watchdog = Timer.periodic(const Duration(seconds: 5), (_) => _checkStall());
    return HuntAvailability.ready;
  }

  /// Takes a single high-accuracy fix outside the stream. Used to seed the
  /// session and to break a stall. Re-entrant calls are dropped so a run of
  /// stalled watchdog ticks can't stack up overlapping fix requests.
  Future<void> _pollOnce() async {
    if (_polling) return;
    _polling = true;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 8));
      _onPosition(position);
    } catch (_) {
      // A slow or failed fix isn't fatal — the stream is the primary source.
    } finally {
      _polling = false;
    }
  }

  /// Rebuilds the position subscription for [band]'s sampling profile.
  ///
  /// Never call this synchronously from inside [_onPosition] while the stream
  /// is dispatching: cancelling a subscription from within its own `onData`
  /// races the platform channel's teardown against the new listener's
  /// registration, and the replacement stream can come up dead — which
  /// silently freezes the distance readout at whatever the last fix said.
  /// Callers on the event path go through [_scheduleResubscribe] instead.
  Future<void> _resubscribe(ProximityBand band) async {
    if (_disposed || _resubscribing) return;
    final key = _SubscriptionKey.of(samplingFor(band));
    if (_sub != null && key == _subscribedAs) return;

    _resubscribing = true;
    try {
      // Awaited, so the native side has torn the old listener down before the
      // new one registers on the same channel.
      await _sub?.cancel();
      _sub = null;
      if (_disposed) return;

      _subscribedAs = key;
      _sub = Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: key.accuracy,
          distanceFilter: key.distanceFilter,
        ),
      ).listen(
        _onPosition,
        // Without this a transient platform error kills the stream as an
        // unhandled async error and the hunt freezes for good. Drop the dead
        // subscription and let the watchdog rebuild it.
        onError: (Object _) => _onStreamLost(),
        onDone: _onStreamLost,
        cancelOnError: true,
      );
    } catch (_) {
      _sub = null;
      _subscribedAs = null;
    } finally {
      _resubscribing = false;
    }
  }

  /// Resubscribes off the stream's own event stack — see [_resubscribe].
  void _scheduleResubscribe(ProximityBand band) {
    if (_disposed) return;
    scheduleMicrotask(() => _resubscribe(band));
  }

  void _onStreamLost() {
    if (_disposed) return;
    _sub = null;
    _subscribedAs = null;
    // The watchdog picks it back up on its next tick rather than retrying in
    // a tight loop against a provider that just failed.
  }

  /// Fires every 5 s: if fixes have dried up — a killed stream, a provider
  /// that stopped reporting, a resubscribe that came up dead — take a one-shot
  /// fix so the readout moves, and rebuild the subscription.
  void _checkStall() {
    if (_disposed) return;
    final last = _lastFixAt;
    final stalled =
        last == null || DateTime.now().difference(last) > _stallTimeout;
    if (!stalled) return;

    // The subscription may look alive while delivering nothing, so drop the
    // key too — that makes the rebuild unconditional rather than a no-op.
    _pollOnce();
    _subscribedAs = null;
    _resubscribe(_tracker.band);
  }

  void _onPosition(Position position) {
    if (_disposed) return;

    // Drop outright rather than mis-score (§5.3) — the previous band and
    // reading simply hold. Still counts as liveness: the stream is delivering,
    // it's the fix that's unusable, so the watchdog shouldn't tear it down.
    _lastFixAt = DateTime.now();
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
    if (!_controller.isClosed) _controller.add(state);

    if (_SubscriptionKey.of(samplingFor(band)) != _subscribedAs) {
      _scheduleResubscribe(band);
    }
  }

  void dispose() {
    _disposed = true;
    _watchdog?.cancel();
    _sub?.cancel();
    _controller.close();
  }
}
