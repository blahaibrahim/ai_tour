import 'dart:math' as math;

import 'package:massar/ar/ar_session_host.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

/// The shape Android's ArView sends back for `getCameraPose`.
Map<String, dynamic> _androidPose({
  vm.Vector3? position,
  List<double> quaternion = const [0, 0, 0, 1],
}) {
  final p = position ?? vm.Vector3.zero();
  return {
    'position': {'x': p.x, 'y': p.y, 'z': p.z},
    'rotation': {
      'x': quaternion[0],
      'y': quaternion[1],
      'z': quaternion[2],
      'w': quaternion[3],
    },
  };
}

void main() {
  test('decodes the map Android sends', () {
    // The plugin's own getCameraPose asks for a List and so throws on this,
    // swallows the error, and returns null — which is why it is decoded here.
    final pose = decodeArCameraPose(
      _androidPose(position: vm.Vector3(1, 2, 3)),
    );

    expect(pose, isNotNull);
    expect(pose!.position.x, 1);
    expect(pose.position.y, 2);
    expect(pose.position.z, 3);
    // Identity rotation: the lens looks down -Z.
    expect(pose.forward.z, closeTo(-1, 1e-9));
    expect(pose.right.x, closeTo(1, 1e-9));
    expect(pose.up.y, closeTo(1, 1e-9));
  });

  test('decodes the column-major matrix iOS sends', () {
    final pose = decodeArCameraPose(<double>[
      1, 0, 0, 0, //
      0, 1, 0, 0,
      0, 0, 1, 0,
      4, 5, 6, 1,
    ]);

    expect(pose, isNotNull);
    expect(pose!.position, vm.Vector3(4, 5, 6));
    expect(pose.forward.z, closeTo(-1, 1e-9));
  });

  test('rejects anything else rather than guessing', () {
    expect(decodeArCameraPose(null), isNull);
    expect(decodeArCameraPose('nonsense'), isNull);
    expect(decodeArCameraPose(<double>[1, 2, 3]), isNull);
  });

  test('a quarter turn left swings the lens onto -X', () {
    // Right-handed rotation of +90° about +Y (world up).
    final half = math.sqrt(0.5);
    final pose = decodeArCameraPose(
      _androidPose(quaternion: [0, half, 0, half]),
    );

    // Facing -Z, turning left by 90° means now facing -X.
    expect(pose!.forward.x, closeTo(-1, 1e-9));
    expect(pose.forward.z, closeTo(0, 1e-9));
    expect(pose.right.z, closeTo(-1, 1e-9));
  });

  group('camera space', () {
    test('puts a point straight ahead on the negative Z axis', () {
      final pose = decodeArCameraPose(_androidPose())!;
      final local = pose.toCameraSpace(vm.Vector3(0, 0, -2));

      expect(local.x, closeTo(0, 1e-9));
      expect(local.y, closeTo(0, 1e-9));
      expect(local.z, closeTo(-2, 1e-9));
    });

    test('puts a point off to the right on the positive X axis', () {
      final pose = decodeArCameraPose(_androidPose())!;
      final local = pose.toCameraSpace(vm.Vector3(1.5, 0, -2));

      expect(local.x, closeTo(1.5, 1e-9));
      expect(local.z, closeTo(-2, 1e-9));
    });

    test('accounts for where the camera has walked to', () {
      final pose = decodeArCameraPose(
        _androidPose(position: vm.Vector3(1, 0, 0)),
      )!;
      // Stepping right moves a fixed point to the left of the frame — the
      // parallax that makes walking around the mascot work.
      final local = pose.toCameraSpace(vm.Vector3(0, 0, -2));

      expect(local.x, closeTo(-1, 1e-9));
      expect(local.z, closeTo(-2, 1e-9));
    });

    test('reports a point behind the camera with positive Z', () {
      final pose = decodeArCameraPose(_androidPose())!;
      final local = pose.toCameraSpace(vm.Vector3(0, 0, 3));

      expect(local.z, greaterThan(0));
    });
  });
}
