import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A true 3D cube built from six independently-transformed faces (front,
/// back, left, right, top, bottom) — no external model/rendering package,
/// just [Transform] + [Matrix4] perspective. Faces are depth-sorted each
/// frame with a simple painter's algorithm so the cube reads correctly at
/// any rotation, including full turn-arounds.
class Cube3D extends StatelessWidget {
  final double size;
  final double rotateX;
  final double rotateY;
  final Widget front;
  final Widget back;
  final Widget left;
  final Widget right;
  final Widget top;
  final Widget bottom;
  final double perspective;

  const Cube3D({
    super.key,
    required this.size,
    required this.rotateX,
    required this.rotateY,
    required this.front,
    required this.back,
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
    this.perspective = 0.0022,
  });

  @override
  Widget build(BuildContext context) {
    final half = size / 2;
    final cx = math.cos(rotateX), sx = math.sin(rotateX);
    final cy = math.cos(rotateY), sy = math.sin(rotateY);

    // Facing score: how much each face's outward normal points toward the
    // viewer after the current rotation. Highest score = closest to camera.
    final faces = <_Face>[
      _Face('front', front, rx: 0, ry: 0, score: cx * cy),
      _Face('back', back, rx: 0, ry: math.pi, score: -(cx * cy)),
      _Face('left', left, rx: 0, ry: -math.pi / 2, score: cx * sy),
      _Face('right', right, rx: 0, ry: math.pi / 2, score: -(cx * sy)),
      _Face('top', top, rx: math.pi / 2, ry: 0, score: -sx),
      _Face('bottom', bottom, rx: -math.pi / 2, ry: 0, score: sx),
    ]..sort((a, b) => a.score.compareTo(b.score));

    return SizedBox(
      width: size,
      height: size,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, perspective)
          ..rotateX(rotateX)
          ..rotateY(rotateY),
        child: Stack(
          alignment: Alignment.center,
          children: faces.map((f) {
            final m = Matrix4.identity();
            if (f.rx != 0) m.rotateX(f.rx);
            if (f.ry != 0) m.rotateY(f.ry);
            m.translateByDouble(0.0, 0.0, half, 1.0);
            return Transform(
              alignment: Alignment.center,
              transform: m,
              child: SizedBox(width: size, height: size, child: f.widget),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _Face {
  final String name;
  final Widget widget;
  final double rx;
  final double ry;
  final double score;
  _Face(this.name, this.widget, {required this.rx, required this.ry, required this.score});
}
