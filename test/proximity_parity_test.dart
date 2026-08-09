import 'dart:convert';
import 'dart:io';

import 'package:ai_tour/ar/proximity.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cross-language parity for the proximity band classifier — AR capture plan
/// §5.3 and §11: "Server and client disagreeing about what 'hot' means is the
/// most likely silent bug in this module."
///
/// `shared/ar/band-fixtures.json` is the one file both sides execute — see
/// `backend/server-node/src/testArCapture.ts` for the TypeScript half. Do not
/// hand-edit expected values in one language without re-running the other.
void main() {
  test('classify() agrees with the shared band-fixtures.json cases', () {
    final file = File('shared/ar/band-fixtures.json');
    final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

    final rawThresholds = data['thresholds'] as Map<String, dynamic>;
    final thresholds = BandThresholds(
      coldMeters: (rawThresholds['coldMeters'] as num).toDouble(),
      warmMeters: (rawThresholds['warmMeters'] as num).toDouble(),
      hotMeters: (rawThresholds['hotMeters'] as num).toDouble(),
      burningMeters: (rawThresholds['burningMeters'] as num).toDouble(),
    );

    final cases = data['cases'] as List<dynamic>;
    expect(cases, isNotEmpty);

    for (final raw in cases) {
      final testCase = raw as Map<String, dynamic>;
      final label = testCase['label'] as String;
      final distance = (testCase['distanceMeters'] as num).toDouble();
      final previous = ProximityBand.values.byName(testCase['previousBand'] as String);
      final expected = ProximityBand.values.byName(testCase['expectedBand'] as String);

      final got = ProximityBandCalculator.classify(distance, thresholds, previous);
      expect(
        got,
        expected,
        reason:
            'band parity: $label (d=${distance}m, prev=${previous.name}) — expected ${expected.name}, got ${got.name}',
      );
    }
  });
}
