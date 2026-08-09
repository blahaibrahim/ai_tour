import 'dart:math' as math;

import 'package:ai_tour/services/heading_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('headingToRadians', () {
    test('converts degrees clockwise from north to radians', () {
      expect(headingToRadians(0), closeTo(0, 1e-9));
      expect(headingToRadians(90), closeTo(math.pi / 2, 1e-9));
      expect(headingToRadians(180), closeTo(math.pi, 1e-9));
      expect(headingToRadians(360), closeTo(2 * math.pi, 1e-9));
    });
  });
}
