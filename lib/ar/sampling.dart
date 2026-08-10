import 'proximity.dart';

/// GPS sampling settings for one proximity band, per §5.4 of the AR capture
/// plan. The distance filter — not the timer — does most of the battery work:
/// a stationary user generates almost no fixes.
class SamplingProfile {
  const SamplingProfile({
    required this.distanceFilterMeters,
    required this.minInterval,
    required this.highAccuracy,
  });

  final int distanceFilterMeters;
  final Duration minInterval;
  final bool highAccuracy;
}

/// The plan's adaptive sampling table. Sampling rate is a function of the
/// current band: cheap and infrequent while far away, tight and frequent once
/// the hunt is close.
const Map<ProximityBand, SamplingProfile> kSamplingTable = {
  ProximityBand.frozen: SamplingProfile(
    distanceFilterMeters: 0,
    minInterval: Duration(seconds: 10),
    highAccuracy: false,
  ),
  ProximityBand.cold: SamplingProfile(
    distanceFilterMeters: 0,
    minInterval: Duration(seconds: 5),
    highAccuracy: false,
  ),
  ProximityBand.warm: SamplingProfile(
    distanceFilterMeters: 0,
    minInterval: Duration(seconds: 3),
    highAccuracy: true,
  ),
  ProximityBand.hot: SamplingProfile(
    distanceFilterMeters: 0,
    minInterval: Duration(seconds: 2),
    highAccuracy: true,
  ),
  ProximityBand.burning: SamplingProfile(
    distanceFilterMeters: 0,
    minInterval: Duration(seconds: 1),
    highAccuracy: true,
  ),
};

SamplingProfile samplingFor(ProximityBand band) => kSamplingTable[band]!;
