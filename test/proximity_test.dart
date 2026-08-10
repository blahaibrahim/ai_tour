import 'package:massar/ar/proximity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('rawBand', () {
    const t = BandThresholds();

    test('matches the plan\'s table at representative distances', () {
      expect(rawBand(500, t), ProximityBand.frozen);
      expect(rawBand(200, t), ProximityBand.cold);
      expect(rawBand(100, t), ProximityBand.warm);
      expect(rawBand(40, t), ProximityBand.hot);
      expect(rawBand(10, t), ProximityBand.burning);
    });

    test('boundaries are inclusive on the hotter side', () {
      expect(rawBand(300, t), ProximityBand.cold);
      expect(rawBand(150, t), ProximityBand.warm);
      expect(rawBand(60, t), ProximityBand.hot);
      expect(rawBand(25, t), ProximityBand.burning);
    });
  });

  group('ProximityBandCalculator.classify', () {
    const t = BandThresholds();

    test('moving hotter is immediate', () {
      final band = ProximityBandCalculator.classify(40, t, ProximityBand.warm);
      expect(band, ProximityBand.hot);
    });

    test('moving colder needs to clear the old boundary by a margin', () {
      // Was HOT (<=60). Drifting just past 60 shouldn't demote yet — the
      // margin is max(8, 15% of 60) = 9, so the boundary to clear is 69.
      final justPast = ProximityBandCalculator.classify(65, t, ProximityBand.hot);
      expect(justPast, ProximityBand.hot, reason: 'stays HOT inside the margin');

      final clearedMargin = ProximityBandCalculator.classify(70, t, ProximityBand.hot);
      expect(clearedMargin, ProximityBand.warm);
    });

    test('a stationary user near a boundary does not flap band to band', () {
      // Noisy fixes oscillating either side of the WARM/HOT boundary (60 m).
      final readings = [58.0, 62.0, 59.0, 63.0, 57.0];
      var band = ProximityBand.hot;
      for (final d in readings) {
        band = ProximityBandCalculator.classify(d, t, band);
        expect(band, ProximityBand.hot);
      }
    });
  });

  group('HuntBandTracker', () {
    test('starts FROZEN and requires two consecutive fixes to commit a change', () {
      final tracker = HuntBandTracker();
      expect(tracker.band, ProximityBand.frozen);

      // One HOT-range fix isn't enough on its own.
      expect(tracker.onFix(40), ProximityBand.frozen);
      // A second, agreeing fix commits it.
      expect(tracker.onFix(40), ProximityBand.hot);
    });

    test('a single blip does not commit', () {
      final tracker = HuntBandTracker();
      tracker.onFix(500); // settle at FROZEN implicitly (already there)
      expect(tracker.onFix(10), ProximityBand.frozen); // pending BURNING
      expect(tracker.onFix(500), ProximityBand.frozen); // blip gone, back to FROZEN raw
      expect(tracker.onFix(10), ProximityBand.frozen); // pending again, first of two
      expect(tracker.onFix(10), ProximityBand.burning); // second agreeing fix commits
    });

    test('moving hotter still needs two fixes even though classify is immediate', () {
      final tracker = HuntBandTracker();
      expect(tracker.onFix(100), ProximityBand.frozen);
      expect(tracker.onFix(100), ProximityBand.warm);
    });
  });
}
