import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart' as vm;

/// Height the phone is assumed to be held at, in metres.
///
/// Only used when the floor can't be measured from a tracked plane. ARCore and
/// ARKit put their world origin at the device's pose when the session starts,
/// so the floor is this far below y = 0.
const double kAssumedPhoneHeight = 1.4;

/// Where the mascot stands, relative to where the AR session started.
///
/// Both AR runtimes place their world origin at the device's pose when the
/// session begins, with Y along gravity and -Z pointing the way the camera was
/// facing. A spot is therefore a bearing and a distance from that starting
/// point — which is the shape a backend-supplied location collapses to once
/// one exists, after converting from whatever the backend speaks (a geo
/// coordinate, a venue-relative offset) into metres from the visitor.
class MascotSpot {
  const MascotSpot({this.bearing = 0.35, this.distance = 1.6});

  /// Builds a spot from the real-world geometry instead of the placeholder
  /// default: the true bearing from the visitor to the spawn point, and the
  /// device's compass heading when the AR session started.
  ///
  /// This is §5.5's "bearing-preserving AR placement, not survey-grade
  /// geo-anchoring" — `yaw = θ − H₀`. Only the bearing survives the transition
  /// into AR-world coordinates: consumer GPS is ±5–15 m and urban compass
  /// error is ±10–15°, so placing the mascot at its true geographic distance
  /// would put it inside a wall as often as not. [presentationDistance] is
  /// deliberately fixed and clamped to the plan's `[2.5 m, 6 m]` range instead.
  factory MascotSpot.towardsBearing({
    required double trueBearingRadians,
    required double headingRadians,
    double presentationDistance = 4.0,
  }) {
    return MascotSpot(
      bearing: trueBearingRadians - headingRadians,
      distance: presentationDistance.clamp(2.5, 6.0),
    );
  }

  /// Radians clockwise from the direction the camera faced at session start.
  /// Zero is dead ahead; pi puts the mascot behind the visitor.
  final double bearing;

  /// Metres from the session origin, along the floor.
  ///
  /// Keep this short. Circling something to see its far side means walking a
  /// ring of this radius, so at four metres "walk around it" is a twenty-five
  /// metre hike, and a sidestep barely changes the angle you see it from. At
  /// roughly a metre and a half, one step to the side visibly swings it round.
  /// Close placement also lands the anchor in the part of the room the camera
  /// has actually mapped, which is what keeps it from drifting.
  final double distance;

  /// Position of the mascot's feet, given the floor height in world metres.
  vm.Vector3 floorPosition(double floorY) => vm.Vector3(
        math.sin(bearing) * distance,
        floorY,
        -math.cos(bearing) * distance,
      );

  /// World transform for the anchor holding the mascot.
  ///
  /// [baseOffset] lifts the anchor by the gap between the model's origin and
  /// its lowest point, so the mascot rests on the floor rather than sinking
  /// halfway into it.
  ///
  /// Translation only, deliberately: the plugin decomposes this matrix and
  /// feeds the rotation straight into an ARCore `Pose` quaternion without
  /// normalising it, so anything other than identity arrives skewed.
  vm.Matrix4 anchorTransform({
    required double floorY,
    required double baseOffset,
  }) {
    final feet = floorPosition(floorY);
    return vm.Matrix4.translation(
      vm.Vector3(feet.x, feet.y + baseOffset, feet.z),
    );
  }
}
