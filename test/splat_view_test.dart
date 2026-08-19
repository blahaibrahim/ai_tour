import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massar/screens/splat_viewer/widgets/splat_view.dart';
import 'package:massar/services/splat_loader.dart';

/// That the splat actually paints.
///
/// The renderer's whole hot path is one `drawRawAtlas` call, and that API takes
/// three parallel arrays whose lengths have to agree — transforms of `4n`, rects
/// of `4n`, colours of `n`, with `n` inferred from the first. Get any of that
/// wrong and it is an assertion at paint time, not a compile error, which no
/// amount of reading the code reliably catches. These tests pump the widget and
/// let the framework's own error reporting be the assertion.
///
/// They are deliberately about *not throwing* rather than about pixels. What the
/// cloud looks like is a judgement call for a human with a phone; what cannot be
/// left to that is whether the buffers line up at every detail level, at every
/// camera angle a gesture can reach, and when every point is behind the camera.
void main() {
  /// A hollow sphere of gaussians around the origin, which is close enough to a
  /// reconstructed room to exercise the same code: some points in front of the
  /// camera, some behind, a spread of depths to bucket, and a spread of radii.
  SplatCloud sphere(int count) {
    final positions = Float32List(count * 3);
    final radii = Float32List(count);
    final colors = Uint8List(count * 4);
    final random = math.Random(7);

    for (var i = 0; i < count; i++) {
      final theta = random.nextDouble() * math.pi * 2;
      final phi = math.acos(2 * random.nextDouble() - 1);
      const r = 5.0;
      positions[i * 3] = r * math.sin(phi) * math.cos(theta);
      positions[i * 3 + 1] = r * math.cos(phi);
      positions[i * 3 + 2] = r * math.sin(phi) * math.sin(theta);
      radii[i] = 0.02 + random.nextDouble() * 0.3;
      colors[i * 4] = random.nextInt(256);
      colors[i * 4 + 1] = random.nextInt(256);
      colors[i * 4 + 2] = random.nextInt(256);
      colors[i * 4 + 3] = 40 + random.nextInt(216);
    }

    return SplatCloud(
      count: count,
      source: count * 9,
      positions: positions,
      radii: radii,
      colors: colors,
      center: const [0, 0, 0],
      extent: 5,
    );
  }

  Future<void> pumpView(
    WidgetTester tester,
    SplatCloud cloud,
    SplatDetail detail,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 700,
            child: SplatView(cloud: cloud, detail: detail),
          ),
        ),
      ),
    );
    // Explicit pumps, not `pumpAndSettle`: the view holds a permanent `Ticker`
    // for the idle auto-orbit, so the tree never goes quiet and settling would
    // wait for a frame that never stops coming.
    //
    // Three of them. The sprite is built asynchronously, so the first frame
    // paints an empty canvas, the microtask that stores it lands next, and only
    // the frame after that is the first one to actually draw a gaussian.
    for (var frame = 0; frame < 3; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  for (final detail in SplatDetail.values) {
    testWidgets('paints at ${detail.name} detail', (tester) async {
      // 4000 points against a `low` ceiling of 30 000 exercises the stride-of-1
      // path; the same cloud at every level checks that a ceiling larger than
      // the cloud does not walk off the end of it.
      await pumpView(tester, sphere(4000), detail);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('paints a cloud larger than the lowest ceiling', (tester) async {
    // Over `low`'s 30 000, so the stride is greater than one and `_sampled` is
    // the rounded-up quotient — the case where an off-by-one in the buffer sizes
    // would overrun.
    await pumpView(tester, sphere(40000), SplatDetail.low);
    expect(tester.takeException(), isNull);
  });

  testWidgets('survives being dragged, pinched and reset', (tester) async {
    await pumpView(tester, sphere(4000), SplatDetail.medium);

    // A drag past the pitch clamp in both directions, which is where the camera
    // basis would otherwise collapse and the projection divide by zero.
    for (final delta in const [Offset(120, 400), Offset(-260, -900)]) {
      await tester.drag(find.byType(SplatView), delta);
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }

    // Zoomed in far enough that most gaussians clamp to the maximum disc size
    // and most of the rest fall outside the canvas and are culled.
    final centre = tester.getCenter(find.byType(SplatView));
    final pinch = await tester.startGesture(centre - const Offset(20, 0));
    final pinch2 = await tester.startGesture(centre + const Offset(20, 0));
    await pinch.moveBy(const Offset(-150, 0));
    await pinch2.moveBy(const Offset(150, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await pinch.up();
    await pinch2.up();
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);

    // And back to the framing pose. The trailing pump is not decoration: the
    // double-tap recogniser arms a timer on the second tap, and a test that ends
    // with it still pending fails on the framework's own leak check.
    await tester.tap(find.byType(SplatView));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.byType(SplatView));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  });

  testWidgets('paints nothing rather than failing when the cloud is behind the camera',
      (tester) async {
    // Every gaussian at one point, which after the near-plane and sub-pixel
    // tests leaves the atlas call with zero sprites. `drawRawAtlas` with empty
    // views is the case the early return exists for.
    final degenerate = SplatCloud(
      count: 2,
      source: 2,
      positions: Float32List.fromList([0, 0, 0, 0, 0, 0]),
      radii: Float32List.fromList([1e-9, 1e-9]),
      colors: Uint8List.fromList([255, 255, 255, 255, 255, 255, 255, 255]),
      center: const [0, 0, 0],
      extent: 1,
    );

    await pumpView(tester, degenerate, SplatDetail.medium);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching detail re-sizes the buffers rather than reusing them',
      (tester) async {
    final cloud = sphere(40000);
    // Low first, so the buffers start smaller than `high` needs them. A
    // `reconfigure` that grew the stride but not the arrays would overrun here
    // and nowhere else.
    await pumpView(tester, cloud, SplatDetail.low);
    await pumpView(tester, cloud, SplatDetail.high);
    expect(tester.takeException(), isNull);
  });
}
