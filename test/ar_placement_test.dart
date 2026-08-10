import 'dart:io';
import 'dart:math' as math;

import 'package:massar/ar/glb_bounds.dart';
import 'package:massar/ar/mascot_placement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('glb bounds', () {
    late GlbBounds bounds;

    setUpAll(() {
      bounds = parseGlbBounds(File('assets/3d/fennec.glb').readAsBytesSync());
    });

    test('reads the mascot bounding box from the header alone', () {
      expect(bounds.min.x, lessThan(bounds.max.x));
      expect(bounds.min.y, lessThan(bounds.max.y));
      expect(bounds.min.z, lessThan(bounds.max.z));
      expect(bounds.longestExtent, greaterThan(0));
    });

    test('the model origin sits above its feet, so anchors need lifting', () {
      // The fennec is authored centred on its body: dropping an anchor on the
      // floor without this offset would bury half of it.
      expect(bounds.min.y, lessThan(0));
      expect(bounds.baseOffsetRatio, greaterThan(0));
      expect(bounds.baseOffsetRatio, lessThan(1));
    });

    test('height ratio scales the model to a believable animal', () {
      // Rendered at 0.7 m along its longest side, it should stand roughly
      // knee-high rather than towering over the room.
      final height = bounds.heightRatio * 0.7;
      expect(height, greaterThan(0.2));
      expect(height, lessThan(1.0));
    });

    test('rejects data that is not a glb', () {
      expect(
        () => parseGlbBounds(File('pubspec.yaml').readAsBytesSync()),
        throwsFormatException,
      );
    });
  });

  group('mascot spot', () {
    const floorY = -1.35;

    test('sits on the floor height it is given', () {
      for (final bearing in [0.0, 0.35, 1.9, -2.4]) {
        final spot = MascotSpot(bearing: bearing, distance: 1.6);
        // The measured floor has to come through untouched — the whole point
        // of probing for it.
        expect(spot.floorPosition(floorY).y, floorY);
      }
    });

    test('bearing zero is straight ahead of where the session started', () {
      // Both runtimes start with -Z pointing the way the camera faced.
      final ahead = const MascotSpot(bearing: 0, distance: 2).floorPosition(0);
      expect(ahead.x, closeTo(0, 1e-9));
      expect(ahead.z, closeTo(-2, 1e-9));
    });

    test('bearing turns clockwise, and pi puts it behind the visitor', () {
      final right =
          MascotSpot(bearing: math.pi / 2, distance: 2).floorPosition(0);
      expect(right.x, closeTo(2, 1e-9));
      expect(right.z, closeTo(0, 1e-9));

      final behind = MascotSpot(bearing: math.pi, distance: 2).floorPosition(0);
      expect(behind.z, closeTo(2, 1e-9));
    });

    test('stays at the requested distance whichever way it faces', () {
      for (final bearing in [0.0, 0.6, 2.2, 4.9]) {
        final spot = MascotSpot(bearing: bearing, distance: 1.6);
        final position = spot.floorPosition(floorY);
        final ground = math.sqrt(
          position.x * position.x + position.z * position.z,
        );
        expect(ground, closeTo(1.6, 1e-9));
      }
    });

    test('defaults to arm-and-a-bit range so it can be walked around', () {
      // Circling something four metres out is a twenty-five metre walk; close
      // in, one sidestep visibly swings it round.
      const spot = MascotSpot();
      expect(spot.distance, lessThanOrEqualTo(2.0));
      expect(spot.distance, greaterThan(0.8));
    });

    test('towardsBearing turns the true bearing into a yaw relative to heading',
        () {
      // Facing north (heading 0), target due east (bearing pi/2): the mascot
      // should sit to the right, i.e. yaw = pi/2.
      final spot = MascotSpot.towardsBearing(
        trueBearingRadians: math.pi / 2,
        headingRadians: 0,
      );
      expect(spot.bearing, closeTo(math.pi / 2, 1e-9));

      // Facing east (heading pi/2) with the same target: now it's dead ahead.
      final aligned = MascotSpot.towardsBearing(
        trueBearingRadians: math.pi / 2,
        headingRadians: math.pi / 2,
      );
      expect(aligned.bearing, closeTo(0, 1e-9));
    });

    test('towardsBearing clamps presentation distance to [2.5, 6] metres', () {
      final tooClose = MascotSpot.towardsBearing(
        trueBearingRadians: 0,
        headingRadians: 0,
        presentationDistance: 1.0,
      );
      expect(tooClose.distance, 2.5);

      final tooFar = MascotSpot.towardsBearing(
        trueBearingRadians: 0,
        headingRadians: 0,
        presentationDistance: 20,
      );
      expect(tooFar.distance, 6.0);

      final defaultSpot =
          MascotSpot.towardsBearing(trueBearingRadians: 0, headingRadians: 0);
      expect(defaultSpot.distance, 4.0);
    });

    test('anchor transform lifts the model onto the floor and nothing else',
        () {
      const spot = MascotSpot(bearing: 0.35, distance: 1.6);
      final transform = spot.anchorTransform(floorY: floorY, baseOffset: 0.3);
      final feet = spot.floorPosition(floorY);

      final translation = transform.getTranslation();
      expect(translation.x, closeTo(feet.x, 1e-9));
      expect(translation.y, closeTo(floorY + 0.3, 1e-9));
      expect(translation.z, closeTo(feet.z, 1e-9));

      // Rotation must stay identity: the plugin feeds this matrix's rotation
      // into an ARCore Pose without normalising it.
      final rotation = transform.getRotation();
      expect(rotation.entry(0, 0), closeTo(1, 1e-12));
      expect(rotation.entry(1, 1), closeTo(1, 1e-12));
      expect(rotation.entry(2, 2), closeTo(1, 1e-12));
      expect(rotation.entry(0, 1), closeTo(0, 1e-12));
      expect(rotation.entry(1, 2), closeTo(0, 1e-12));
    });
  });
}
