import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../services/splat_loader.dart';
import '../../../theme.dart';

/// How many gaussians are drawn, of however many the file holds.
///
/// The point cloud is fully in memory either way — this only changes how many of
/// it reach the canvas each frame. It exists because the honest answer to "how
/// many points can a phone draw" is "it depends on the phone", and the
/// traveller's own eyes are a better judge of the trade than a hardware
/// heuristic would be.
enum SplatDetail {
  /// Every phone, comfortably.
  low(30000),

  /// The default. Smooth on a mid-range device.
  medium(75000),

  /// Everything published, which is 200k. Expect a slower drag.
  high(1 << 30);

  const SplatDetail(this.points);

  /// Ceiling on gaussians per frame. [high] is deliberately larger than any
  /// file, so it means "all of them" rather than a number to keep in step with
  /// the publisher's decimation target.
  final int points;
}

/// An orbitable view of a gaussian splat.
///
/// Each gaussian is drawn as a screen-space disc with a gaussian alpha falloff,
/// blended back to front. That is the cheap half of 3D Gaussian Splatting, and
/// the same half `website/gaussian_splatting/components/SplatCanvas.tsx` draws:
/// the real rasteriser projects each gaussian's 3D covariance to an *oriented
/// ellipse*, so a thin surface reads as thin rather than as a round dab. The
/// difference shows on flat walls and at grazing angles. Doing it properly needs
/// a fragment shader per gaussian; this is a "walk around the place you helped
/// reconstruct" view, and a circular kernel is enough for that.
///
/// Everything expensive is a `drawRawAtlas` call — one draw for the whole cloud,
/// with a per-gaussian transform and colour — over scratch buffers that are
/// allocated once and refilled in place. A per-point `drawCircle` loop would be
/// tens of thousands of draw calls a frame.
class SplatView extends StatefulWidget {
  const SplatView({super.key, required this.cloud, required this.detail});

  final SplatCloud cloud;
  final SplatDetail detail;

  @override
  State<SplatView> createState() => _SplatViewState();
}

class _SplatViewState extends State<SplatView>
    with SingleTickerProviderStateMixin {
  late _Camera _camera;
  late final Ticker _ticker;
  late final _SplatRenderer _renderer;

  /// Bumped to repaint. A plain `setState` would rebuild the subtree for what is
  /// only ever a new frame of the same painting.
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);

  Duration _lastElapsed = Duration.zero;
  DateTime _lastTouch = DateTime.now();

  /// COLMAP's cameras look down +y, so +y is *down* in a reconstructed scene and
  /// the world's up vector is negative. Getting this wrong renders the whole
  /// scene upside down, which — with a symmetric-looking museum interior — is
  /// not obviously wrong until you notice the floor is the ceiling.
  static const _worldUp = [0.0, -1.0, 0.0];

  @override
  void initState() {
    super.initState();
    _renderer = _SplatRenderer(widget.cloud, widget.detail);
    _camera = _Camera.framing(widget.cloud);
    _ticker = createTicker(_onTick)..start();
    _loadSprite();
  }

  Future<void> _loadSprite() async {
    final sprite = await _buildSprite();
    if (!mounted) {
      sprite.dispose();
      return;
    }
    setState(() => _renderer.sprite = sprite);
  }

  @override
  void didUpdateWidget(SplatView old) {
    super.didUpdateWidget(old);
    if (old.detail != widget.detail || old.cloud != widget.cloud) {
      _renderer.reconfigure(widget.cloud, widget.detail);
      if (old.cloud != widget.cloud) _camera = _Camera.framing(widget.cloud);
      _frame.value++;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _renderer.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;

    // A slow drift once the traveller stops touching it, so a scene opened and
    // left alone shows itself off rather than sitting still. Same idle delay as
    // the artifact viewer's cube, for consistency.
    if (DateTime.now().difference(_lastTouch) >
        const Duration(milliseconds: 1400)) {
      _camera.yaw += dt * 0.18;
      _frame.value++;
    }
  }

  void _touched() => _lastTouch = DateTime.now();

  double _pinchStart = 1;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // One finger orbits, two pan and pinch. `onScale*` covers both — a
      // separate pan recogniser would fight the pinch for the same pointers.
      onScaleStart: (details) {
        _touched();
        _pinchStart = _camera.distance;
      },
      onScaleUpdate: (details) {
        _touched();
        if (details.pointerCount >= 2) {
          _camera.zoomTo(_pinchStart / details.scale, widget.cloud);
          _camera.pan(details.focalPointDelta, _worldUp);
        } else {
          _camera.orbit(details.focalPointDelta);
        }
        _frame.value++;
      },
      onDoubleTap: () {
        _touched();
        setState(() => _camera = _Camera.framing(widget.cloud));
      },
      child: ValueListenableBuilder<int>(
        valueListenable: _frame,
        builder: (context, _, _) => CustomPaint(
          painter: _SplatPainter(
            renderer: _renderer,
            camera: _camera,
            worldUp: _worldUp,
            revision: _frame.value,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// Where the camera is looking from.
///
/// Orbit coordinates rather than a matrix: the only motions on offer are the
/// three a touchscreen can express — swing around the subject, slide the subject
/// across, move closer — and holding yaw/pitch/distance means none of them can
/// drift into a state the traveller cannot undo. A free 6-DoF camera on a phone
/// gets lost within seconds.
class _Camera {
  _Camera({
    required this.target,
    required this.yaw,
    required this.pitch,
    required this.distance,
  });

  /// Framed on the cloud's 90th-percentile extent, from slightly above — the
  /// same starting pose the studio dashboard uses, so a scene looks the same in
  /// both viewers.
  factory _Camera.framing(SplatCloud cloud) => _Camera(
        target: [...cloud.center],
        yaw: 0.6,
        pitch: 0.25,
        distance: cloud.extent * 2.6,
      );

  final List<double> target;
  double yaw;
  double pitch;
  double distance;

  void orbit(Offset delta) {
    yaw -= delta.dx * 0.008;
    // Stopped just short of the poles: at exactly ±π/2 the view direction is
    // parallel to the up vector and the right-hand basis vector collapses to
    // zero, which makes the whole scene vanish.
    pitch = (pitch - delta.dy * 0.008).clamp(-1.5, 1.5);
  }

  void zoomTo(double next, SplatCloud cloud) {
    distance = next.clamp(cloud.extent * 0.05, cloud.extent * 12);
  }

  /// Slides the subject across the screen, in the camera's own plane, at a rate
  /// proportional to how far away it is — so a pan feels the same whether the
  /// traveller is inside the scene or looking at all of it.
  void pan(Offset delta, List<double> worldUp) {
    final basis = _basis(worldUp);
    final speed = distance * 0.0022;
    for (var axis = 0; axis < 3; axis++) {
      target[axis] -= basis.right[axis] * delta.dx * speed;
      target[axis] -= basis.up[axis] * delta.dy * speed;
    }
  }

  List<double> eye() {
    final cosPitch = math.cos(pitch);
    return [
      target[0] + distance * cosPitch * math.sin(yaw),
      target[1] + distance * math.sin(pitch),
      target[2] + distance * cosPitch * math.cos(yaw),
    ];
  }

  /// The camera's right/up/forward axes, in world space.
  _Basis _basis(List<double> worldUp) {
    final from = eye();
    var fx = target[0] - from[0];
    var fy = target[1] - from[1];
    var fz = target[2] - from[2];
    final flen = math.sqrt(fx * fx + fy * fy + fz * fz);
    if (flen > 0) {
      fx /= flen;
      fy /= flen;
      fz /= flen;
    }

    // right = normalize(forward x worldUp)
    var rx = fy * worldUp[2] - fz * worldUp[1];
    var ry = fz * worldUp[0] - fx * worldUp[2];
    var rz = fx * worldUp[1] - fy * worldUp[0];
    final rlen = math.sqrt(rx * rx + ry * ry + rz * rz);
    if (rlen > 0) {
      rx /= rlen;
      ry /= rlen;
      rz /= rlen;
    }

    // up = right x forward. Recomputed rather than reusing worldUp, so the
    // basis stays orthogonal at every pitch.
    final ux = ry * fz - rz * fy;
    final uy = rz * fx - rx * fz;
    final uz = rx * fy - ry * fx;

    return _Basis(
      eye: from,
      right: [rx, ry, rz],
      up: [ux, uy, uz],
      forward: [fx, fy, fz],
    );
  }
}

class _Basis {
  const _Basis({
    required this.eye,
    required this.right,
    required this.up,
    required this.forward,
  });

  final List<double> eye;
  final List<double> right;
  final List<double> up;
  final List<double> forward;
}

/// The scratch buffers one cloud is drawn through, and the sprite it is drawn
/// with.
///
/// Owned by the widget's state rather than by the painter: a `CustomPainter` is
/// rebuilt on every frame, and reallocating four arrays of 75 000 entries per
/// frame is exactly the kind of garbage that turns a smooth drag into a stutter.
class _SplatRenderer {
  _SplatRenderer(this.cloud, SplatDetail detail) {
    reconfigure(cloud, detail);
  }

  SplatCloud cloud;
  ui.Image? sprite;

  /// Gaussians considered per frame, and the stride through the cloud that picks
  /// them. Striding rather than taking the first N: the `.splatb` is written in
  /// the order the optimiser held the gaussians, which correlates with position,
  /// so the first N would be one corner of the room in full detail and the rest
  /// of it missing.
  late int _sampled;
  late int _stride;

  late Float32List _screenX;
  late Float32List _screenY;
  late Float32List _radius;
  late Float32List _depth;
  late Int32List _sourceIndex;
  late Int32List _bucket;
  late Float32List _rst;
  late Float32List _rects;
  late Int32List _colors;

  /// Depth buckets for the back-to-front ordering.
  ///
  /// A counting sort, not a comparison sort. Splatting needs the cloud drawn far
  /// to near for the alpha blending to be right, and that order changes every
  /// time the camera moves — so it is re-derived every frame, and an
  /// `O(n log n)` sort of 75 000 doubles per frame in Dart is tens of
  /// milliseconds of jank. Quantising depth into 1024 buckets and counting them
  /// is one linear pass, and 1024 steps is finer than the eye can resolve in a
  /// blend of overlapping translucent discs.
  static const int _buckets = 1024;
  final Int32List _counts = Int32List(_buckets + 1);

  void reconfigure(SplatCloud next, SplatDetail detail) {
    cloud = next;
    _stride = math.max(1, (next.count / detail.points).ceil());
    _sampled = (next.count / _stride).ceil();

    _screenX = Float32List(_sampled);
    _screenY = Float32List(_sampled);
    _radius = Float32List(_sampled);
    _depth = Float32List(_sampled);
    _sourceIndex = Int32List(_sampled);
    _bucket = Int32List(_sampled);
    _rst = Float32List(_sampled * 4);
    _colors = Int32List(_sampled);

    // Every sprite is the whole atlas image, so the source rects are identical
    // and filled once here instead of 75 000 times a frame.
    _rects = Float32List(_sampled * 4);
    for (var i = 0; i < _sampled; i++) {
      _rects[i * 4 + 2] = _spriteSize;
      _rects[i * 4 + 3] = _spriteSize;
    }
  }

  void dispose() => sprite?.dispose();

  /// Projects, sorts and draws. Returns the number of gaussians that landed on
  /// screen, which the caller shows so an empty canvas is explainable.
  int paint(Canvas canvas, Size size, _Camera camera, List<double> worldUp) {
    final image = sprite;
    if (image == null || size.isEmpty) return 0;

    final basis = camera._basis(worldUp);
    final eye = basis.eye;
    final right = basis.right;
    final up = basis.up;
    final forward = basis.forward;

    // 45°, matching the dashboard's viewer, expressed as the focal length in
    // pixels that a screen of this height implies.
    final focal = size.height / (2 * math.tan(math.pi / 8));
    final halfWidth = size.width / 2;
    final halfHeight = size.height / 2;
    // A disc larger than this is a gaussian so close to the camera that it is
    // fog rather than geometry.
    final maxRadius = math.min(64.0, size.height / 8);
    final near = math.max(cloud.extent * 0.002, 1e-3);

    final positions = cloud.positions;
    final radii = cloud.radii;

    var visible = 0;
    var minDepth = double.infinity;
    var maxDepth = 0.0;

    for (var i = 0; i < _sampled; i++) {
      final source = i * _stride;
      if (source >= cloud.count) break;

      final dx = positions[source * 3] - eye[0];
      final dy = positions[source * 3 + 1] - eye[1];
      final dz = positions[source * 3 + 2] - eye[2];

      final depth = forward[0] * dx + forward[1] * dy + forward[2] * dz;
      if (depth <= near) continue; // behind the camera, or inside it

      final radius = radii[source] * focal / depth;
      if (radius < 0.4) continue; // sub-pixel: nothing the blend would show

      final x = halfWidth + focal * (right[0] * dx + right[1] * dy + right[2] * dz) / depth;
      final y = halfHeight + focal * (up[0] * dx + up[1] * dy + up[2] * dz) / depth;

      final clamped = radius > maxRadius ? maxRadius : radius;
      if (x < -clamped || x > size.width + clamped) continue;
      if (y < -clamped || y > size.height + clamped) continue;

      _screenX[visible] = x;
      _screenY[visible] = y;
      _radius[visible] = clamped;
      _sourceIndex[visible] = source;
      // Kept as a float and bucketed in a second pass: the range it has to be
      // quantised against is not known until every point has been projected.
      _depth[visible] = depth;
      if (depth < minDepth) minDepth = depth;
      if (depth > maxDepth) maxDepth = depth;
      visible++;
    }

    if (visible == 0) return 0;

    // --- counting sort, farthest bucket first ---
    _counts.fillRange(0, _buckets + 1, 0);
    final span = maxDepth - minDepth;
    // A scene seen from far enough away that every point rounds to one depth is
    // one where the order does not matter; guard the division rather than
    // special-casing the draw.
    final quantise = span > 1e-6 ? (_buckets - 1) / span : 0.0;
    for (var i = 0; i < visible; i++) {
      // Reversed, so bucket 0 holds the farthest gaussians and the prefix scan
      // below emits them first.
      final bucket =
          (_buckets - 1) - ((_depth[i] - minDepth) * quantise).round();
      final safe = bucket < 0 ? 0 : (bucket >= _buckets ? _buckets - 1 : bucket);
      _bucket[i] = safe;
      _counts[safe + 1]++;
    }
    for (var b = 0; b < _buckets; b++) {
      _counts[b + 1] += _counts[b];
    }

    final colors = cloud.colors;
    final half = _spriteSize / 2;
    for (var i = 0; i < visible; i++) {
      final at = _counts[_bucket[i]]++;
      final spriteScale = _radius[i] / half;

      // RSTransform, written by hand: scaled cosine, scaled sine, then the
      // translation that puts the sprite's *centre* — not its top-left corner —
      // at the projected point. No rotation, so ssin is zero.
      _rst[at * 4] = spriteScale;
      _rst[at * 4 + 1] = 0;
      _rst[at * 4 + 2] = _screenX[i] - spriteScale * half;
      _rst[at * 4 + 3] = _screenY[i] - spriteScale * half;

      final source = _sourceIndex[i];
      _colors[at] = (colors[source * 4 + 3] << 24) |
          (colors[source * 4] << 16) |
          (colors[source * 4 + 1] << 8) |
          colors[source * 4 + 2];
    }

    // Views, not copies: `drawRawAtlas` infers the sprite count from the length
    // of the transform list, so a partly-filled frame is expressed by narrowing
    // the window rather than by reallocating three arrays.
    canvas.drawRawAtlas(
      image,
      Float32List.view(_rst.buffer, 0, visible * 4),
      Float32List.view(_rects.buffer, 0, visible * 4),
      Int32List.view(_colors.buffer, 0, visible),
      // The sprite is white with a gaussian alpha falloff; modulate multiplies
      // it by the gaussian's own colour and opacity, which is what turns one
      // grey dab into 75 000 coloured ones.
      BlendMode.modulate,
      null,
      _paint,
    );

    return visible;
  }

  static final Paint _paint = Paint()
    // The falloff in the sprite is already smooth, and filtering 75 000 quads
    // costs more than it shows.
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.low;
}

const double _spriteSize = 32;

/// The disc every gaussian is stamped from.
///
/// White, with `exp(-4r²)` alpha — the same kernel the dashboard's fragment
/// shader uses. Sampled at five stops rather than evaluated per pixel: a radial
/// gradient is interpolated by the GPU anyway, and the difference between five
/// stops of a smooth curve and the curve itself is not visible in a 32-pixel
/// sprite that is usually drawn at four pixels across.
Future<ui.Image> _buildSprite() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const center = Offset(_spriteSize / 2, _spriteSize / 2);

  canvas.drawCircle(
    center,
    _spriteSize / 2,
    Paint()
      ..shader = ui.Gradient.radial(center, _spriteSize / 2, [
        const Color(0xFFFFFFFF),
        const Color(0xC7FFFFFF), // exp(-4 * 0.25²) = 0.78
        const Color(0x5EFFFFFF), // exp(-4 * 0.50²) = 0.37
        const Color(0x1BFFFFFF), // exp(-4 * 0.75²) = 0.11
        const Color(0x00FFFFFF),
      ], const [0.0, 0.25, 0.5, 0.75, 1.0]),
  );

  return recorder
      .endRecording()
      .toImage(_spriteSize.toInt(), _spriteSize.toInt());
}

class _SplatPainter extends CustomPainter {
  const _SplatPainter({
    required this.renderer,
    required this.camera,
    required this.worldUp,
    required this.revision,
  });

  final _SplatRenderer renderer;
  final _Camera camera;
  final List<double> worldUp;

  /// Only there to make two painters compare unequal when the camera has moved.
  /// [camera] is mutated in place — it has to be, so a drag does not allocate —
  /// so it cannot be the thing compared.
  final int revision;

  @override
  void paint(Canvas canvas, Size size) {
    // The scene's own ground. Deep navy rather than black: the app's dark
    // surfaces are navy, and a black rectangle in the middle of this screen
    // would read as a hole rather than as depth.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = AppTheme.deepNavy,
    );
    renderer.paint(canvas, size, camera, worldUp);
  }

  @override
  bool shouldRepaint(_SplatPainter old) =>
      old.revision != revision || old.renderer != renderer;
}
