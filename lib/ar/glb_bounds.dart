import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:vector_math/vector_math_64.dart' as vm;

/// The bounding box of a model, read from a `.glb` without touching its
/// geometry.
///
/// glTF stores min/max on every POSITION accessor, and those live in the JSON
/// header — a few hundred bytes at the front of the file — so this costs
/// nothing even for a multi-megabyte model.
class GlbBounds {
  const GlbBounds(this.min, this.max);

  final vm.Vector3 min;
  final vm.Vector3 max;

  /// Longest side of the box. The AR renderer scales a model so that this
  /// dimension matches the size asked for, so every other measurement here has
  /// to be expressed relative to it.
  double get longestExtent => math.max(
        max.x - min.x,
        math.max(max.y - min.y, max.z - min.z),
      );

  /// How far the model's own origin sits above its lowest point, as a fraction
  /// of [longestExtent].
  ///
  /// Models are rarely authored with the origin at their feet — this one is
  /// centred on its body — so an anchor dropped on the floor would bury half
  /// the mascot in it. Raise the anchor by this much times the on-screen size
  /// and it stands on the floor instead.
  double get baseOffsetRatio {
    final extent = longestExtent;
    return extent > 0 ? -min.y / extent : 0;
  }

  /// Height of the model as a fraction of [longestExtent].
  double get heightRatio {
    final extent = longestExtent;
    return extent > 0 ? (max.y - min.y) / extent : 0;
  }
}

const int _kMagicGltf = 0x46546C67;
const int _kChunkJson = 0x4E4F534A;

/// Reads the bounds of the model in [assetPath] from the Flutter asset bundle.
Future<GlbBounds> readGlbBounds(String assetPath) async {
  final data = await rootBundle.load(assetPath);
  return parseGlbBounds(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
}

/// Extracts the model bounds from the JSON header of a binary glTF.
GlbBounds parseGlbBounds(Uint8List glb) {
  final head = ByteData.sublistView(glb);
  if (glb.length < 12 || head.getUint32(0, Endian.little) != _kMagicGltf) {
    throw const FormatException('Not a binary glTF (.glb) file');
  }

  Map<String, dynamic>? gltf;
  var offset = 12;
  while (offset + 8 <= glb.length) {
    final length = head.getUint32(offset, Endian.little);
    final type = head.getUint32(offset + 4, Endian.little);
    final start = offset + 8;
    if (type == _kChunkJson) {
      final end = math.min(start + length, glb.length);
      gltf = jsonDecode(utf8.decode(Uint8List.sublistView(glb, start, end)))
          as Map<String, dynamic>;
      break; // The header is the first chunk; the geometry after it is dead weight.
    }
    offset = start + length;
  }
  if (gltf == null) {
    throw const FormatException('glb is missing its JSON chunk');
  }

  final accessors = (gltf['accessors'] as List?) ?? const [];
  var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity, maxZ = -double.infinity;
  var found = false;

  // Union over every POSITION accessor. Node transforms are ignored: a mascot
  // exported as a single mesh sits at the identity, and the AR renderer scales
  // to fit regardless.
  for (final mesh in (gltf['meshes'] as List?) ?? const []) {
    for (final primitive in ((mesh as Map)['primitives'] as List?) ?? const []) {
      final index = ((primitive as Map)['attributes'] as Map?)?['POSITION'];
      if (index is! int || index < 0 || index >= accessors.length) continue;

      final accessor = accessors[index] as Map<String, dynamic>;
      final min = (accessor['min'] as List?)?.cast<num>();
      final max = (accessor['max'] as List?)?.cast<num>();
      if (min == null || max == null || min.length < 3 || max.length < 3) {
        continue;
      }

      found = true;
      minX = math.min(minX, min[0].toDouble());
      minY = math.min(minY, min[1].toDouble());
      minZ = math.min(minZ, min[2].toDouble());
      maxX = math.max(maxX, max[0].toDouble());
      maxY = math.max(maxY, max[1].toDouble());
      maxZ = math.max(maxZ, max[2].toDouble());
    }
  }

  if (!found) {
    throw const FormatException('glb declares no POSITION bounds');
  }
  return GlbBounds(vm.Vector3(minX, minY, minZ), vm.Vector3(maxX, maxY, maxZ));
}
