import 'dart:math' as math;

/// How hot the hunt is, per §5.3 of the AR capture plan. Ordered coldest to
/// hottest — `index` is used directly to compare "which band is closer".
enum ProximityBand { frozen, cold, warm, hot, burning }

/// Distance boundaries between bands, in metres. Defaults match the plan's
/// table; per-POI overrides would come from `ar_contents.band_thresholds` on
/// a real backend.
class BandThresholds {
  const BandThresholds({
    this.coldMeters = 300,
    this.warmMeters = 150,
    this.hotMeters = 60,
    this.burningMeters = 25,
  });

  /// FROZEN/COLD boundary.
  final double coldMeters;

  /// COLD/WARM boundary.
  final double warmMeters;

  /// WARM/HOT boundary.
  final double hotMeters;

  /// HOT/BURNING boundary — also the capture radius.
  final double burningMeters;

  /// The distance at which [band] gives way to the next-hotter one.
  /// `FROZEN` has no inner edge, so it reports infinity.
  double boundaryOf(ProximityBand band) => switch (band) {
        ProximityBand.frozen => double.infinity,
        ProximityBand.cold => coldMeters,
        ProximityBand.warm => warmMeters,
        ProximityBand.hot => hotMeters,
        ProximityBand.burning => burningMeters,
      };
}

/// Fixes worse than this are dropped outright rather than mis-scored (§5.3).
const double kAccuracyGateMeters = 500;

/// The band [distanceMeters] falls into on its own, ignoring hysteresis.
ProximityBand rawBand(double distanceMeters, BandThresholds thresholds) {
  if (distanceMeters <= thresholds.burningMeters) return ProximityBand.burning;
  if (distanceMeters <= thresholds.hotMeters) return ProximityBand.hot;
  if (distanceMeters <= thresholds.warmMeters) return ProximityBand.warm;
  if (distanceMeters <= thresholds.coldMeters) return ProximityBand.cold;
  return ProximityBand.frozen;
}

/// Pure classifier, mirrored line-for-line from §5.3 of the AR capture plan.
///
/// A user standing still with 8 m of GPS noise near a boundary would
/// otherwise flap between two bands several times a minute. Moving to a
/// hotter band is immediate ("false hope is cheaper than false despair");
/// moving to a colder one requires clearing the old boundary by a margin.
class ProximityBandCalculator {
  const ProximityBandCalculator._();

  static ProximityBand classify(
    double distanceMeters,
    BandThresholds thresholds,
    ProximityBand previousBand,
  ) {
    final raw = rawBand(distanceMeters, thresholds);
    if (raw.index >= previousBand.index) return raw;

    final margin =
        math.max(8.0, 0.15 * thresholds.boundaryOf(previousBand));
    if (distanceMeters < thresholds.boundaryOf(previousBand) + margin) {
      return previousBand;
    }
    return raw;
  }
}

/// Stateful wrapper around [ProximityBandCalculator] that adds the
/// 2-consecutive-fix debounce `HuntSessionController` (C2) is specified to
/// apply on top of the hysteresis: a new band only commits once two
/// successive fixes agree on it.
///
/// Pure and platform-free by design, so the state machine is testable without
/// a location plugin — the accuracy gate (§5.3) is a separate, simpler check
/// callers apply before ever calling [onFix].
class HuntBandTracker {
  HuntBandTracker({this.thresholds = const BandThresholds()});

  final BandThresholds thresholds;

  ProximityBand _band = ProximityBand.frozen;
  ProximityBand? _pendingBand;
  int _pendingCount = 0;

  ProximityBand get band => _band;

  /// Feeds one already-accepted fix's distance. Returns the committed band.
  ProximityBand onFix(double distanceMeters) {
    final raw = ProximityBandCalculator.classify(distanceMeters, thresholds, _band);
    if (raw == _band) {
      _pendingBand = null;
      _pendingCount = 0;
      return _band;
    }
    if (raw == _pendingBand) {
      _pendingCount++;
      if (_pendingCount >= 2) {
        _band = raw;
        _pendingBand = null;
        _pendingCount = 0;
      }
    } else {
      _pendingBand = raw;
      _pendingCount = 1;
    }
    return _band;
  }
}
