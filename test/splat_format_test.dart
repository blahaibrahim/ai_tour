import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:massar/services/splat_loader.dart';

/// The `.splatb` contract, from the reader's side.
///
/// The writer is `website/gaussian_splatting/lib/mobileSplat.ts` and it lives in
/// a different language, a different package and a different repository
/// directory — nothing type-checks the two against each other. What holds them
/// together is the byte layout, so these tests encode it the way the writer does
/// and assert the reader agrees: a header of 32 bytes, then positions, then
/// radii, then colours.
///
/// The planar layout is the load-bearing part. If either side ever "tidied" it
/// into a 20-byte interleaved stride, every test here would still describe a
/// valid file and the app would render nonsense — so the assertions below are
/// deliberately about *which bytes mean what*, not just about round-tripping.
void main() {
  /// Builds a file the same way the dashboard does.
  Uint8List write(
    List<List<double>> positions,
    List<double> radii,
    List<List<int>> colors, {
    int magic = 0x424c5053, // "SPLB", little-endian
    int version = 1,
    int? declaredCount,
    int source = 1887156,
    List<double> center = const [1, 2, 3],
    double extent = 12.5,
    int? truncateTo,
  }) {
    final count = positions.length;
    final bytes = Uint8List(32 + count * 20);
    final view = ByteData.view(bytes.buffer);

    view.setUint32(0, magic, Endian.little);
    view.setUint32(4, version, Endian.little);
    view.setUint32(8, declaredCount ?? count, Endian.little);
    view.setUint32(12, source, Endian.little);
    view.setFloat32(16, center[0], Endian.little);
    view.setFloat32(20, center[1], Endian.little);
    view.setFloat32(24, center[2], Endian.little);
    view.setFloat32(28, extent, Endian.little);

    const positionsAt = 32;
    final radiiAt = positionsAt + count * 12;
    final colorsAt = radiiAt + count * 4;

    for (var i = 0; i < count; i++) {
      view.setFloat32(positionsAt + i * 12, positions[i][0], Endian.little);
      view.setFloat32(positionsAt + i * 12 + 4, positions[i][1], Endian.little);
      view.setFloat32(positionsAt + i * 12 + 8, positions[i][2], Endian.little);
      view.setFloat32(radiiAt + i * 4, radii[i], Endian.little);
      for (var c = 0; c < 4; c++) {
        bytes[colorsAt + i * 4 + c] = colors[i][c];
      }
    }

    return truncateTo == null ? bytes : bytes.sublist(0, truncateTo);
  }

  final threePoints = write(
    [
      [1, 2, 3],
      [-4, 5.5, 6],
      [0, 0, -7],
    ],
    [0.25, 0.5, 1],
    [
      [255, 0, 0, 255],
      [0, 255, 0, 128],
      [10, 20, 30, 40],
    ],
  );

  group('a well-formed file', () {
    test('reads back every field, in the right section', () {
      final cloud = SplatCloud.parse(threePoints);

      expect(cloud.count, 3);
      expect(cloud.source, 1887156);
      expect(cloud.center, [1, 2, 3]);
      expect(cloud.extent, 12.5);

      // Positions are 3-per-point and contiguous — the property the renderer's
      // `positions[source * 3 + axis]` indexing depends on.
      expect(cloud.positions, hasLength(9));
      expect(cloud.positions.sublist(0, 3), [1, 2, 3]);
      expect(cloud.positions[3], -4);
      expect(cloud.positions[4], closeTo(5.5, 1e-6));
      expect(cloud.positions[8], -7);

      expect(cloud.radii, [0.25, 0.5, 1]);

      // RGBA, in that order. Getting this round the wrong way would tint the
      // whole scene and never throw.
      expect(cloud.colors.sublist(0, 4), [255, 0, 0, 255]);
      expect(cloud.colors.sublist(4, 8), [0, 255, 0, 128]);
      expect(cloud.colors.sublist(8, 12), [10, 20, 30, 40]);
    });

    test('aliases the downloaded bytes rather than copying them', () {
      // Its own copy: this case writes through the buffer, and sharing
      // `threePoints` would leak the edit into whichever test ran next.
      final bytes = Uint8List.fromList(threePoints);
      final cloud = SplatCloud.parse(bytes);

      // The offsets the layout specifies, and — the part that matters — the
      // same backing store. `ByteBuffer` identity is no use here (`.buffer`
      // hands back a fresh wrapper each call), so this writes through the raw
      // bytes and reads the change back out of the view. A copy would pass every
      // test above and fail this one, which is the whole reason it exists: the
      // planar layout is only worth having if it is actually aliased.
      expect(cloud.positions.offsetInBytes, 32);
      expect(cloud.radii.offsetInBytes, 32 + 3 * 12);
      expect(cloud.colors.offsetInBytes, 32 + 3 * 12 + 3 * 4);

      ByteData.view(bytes.buffer).setFloat32(32, 99, Endian.little);
      expect(cloud.positions[0], 99);
    });

    test('survives a buffer whose window does not start at zero', () {
      // A `Uint8List` handed over by a plugin can be a view into a larger
      // buffer, and `Float32List.view` throws on an offset that is not 4-byte
      // aligned. Three bytes of lead-in is the worst case.
      final padded = Uint8List(threePoints.length + 3)
        ..setRange(3, threePoints.length + 3, threePoints);
      final offset = Uint8List.view(padded.buffer, 3, threePoints.length);
      expect(offset.offsetInBytes % 4, isNot(0), reason: 'the case being tested');

      final cloud = SplatCloud.parse(offset);
      expect(cloud.count, 3);
      expect(cloud.positions.sublist(0, 3), [1, 2, 3]);
    });
  });

  group('a file that is not one', () {
    test('rejects a short buffer', () {
      expect(
        () => SplatCloud.parse(Uint8List(8)),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects the wrong magic — a .ply, say', () {
      expect(
        () => SplatCloud.parse(write([[0, 0, 0]], [1], [[0, 0, 0, 0]], magic: 0x796c70)),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a format version it does not know', () {
      expect(
        () => SplatCloud.parse(write([[0, 0, 0]], [1], [[0, 0, 0, 0]], version: 2)),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects an empty cloud instead of drawing nothing', () {
      expect(
        () => SplatCloud.parse(write(const [], const [], const [])),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a truncated download rather than reading past the end', () {
      // The header claims three points; the file holds two and a bit. Without
      // the length check this is an out-of-range view, which is a crash rather
      // than a message.
      expect(
        () => SplatCloud.parse(write(
          [
            [1, 2, 3],
            [4, 5, 6],
            [7, 8, 9],
          ],
          [1, 1, 1],
          [
            [0, 0, 0, 255],
            [0, 0, 0, 255],
            [0, 0, 0, 255],
          ],
          truncateTo: 32 + 2 * 20,
        )),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
