import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A decimated gaussian splat, ready to draw.
///
/// The four arrays are *views onto the downloaded bytes*, not copies. That is
/// the whole reason the `.splatb` written by
/// `website/gaussian_splatting/lib/mobileSplat.ts` is laid out planar — all
/// positions, then all radii, then all colours — rather than as a 20-byte
/// interleaved stride: a planar file can be aliased by three typed-data views
/// in constant time, where an interleaved one would need 200 000 `getFloat32`
/// calls before the first frame could draw. Read that file's header for the
/// exact byte layout; this class is the other half of the contract.
class SplatCloud {
  const SplatCloud({
    required this.count,
    required this.source,
    required this.positions,
    required this.radii,
    required this.colors,
    required this.center,
    required this.extent,
  });

  /// Gaussians in this file.
  final int count;

  /// Gaussians in the trained `.ply` it was decimated from — shown in the
  /// viewer, because "200k of 1.9M" is the honest description of what is on
  /// screen.
  final int source;

  /// `count * 3` floats: x, y, z.
  final Float32List positions;

  /// `count` floats: world-space radius.
  final Float32List radii;

  /// `count * 4` bytes: r, g, b, a.
  final Uint8List colors;

  /// Centre of the cloud, and the radius that frames it — the 90th percentile
  /// of the distance from that centre, not the maximum, so an outdoor scene's
  /// far background seeds don't leave the subject a dot in the middle.
  final List<double> center;
  final double extent;

  static const int _headerBytes = 32;

  /// `"SPLB"` read as a little-endian uint32.
  static const int _magic = 0x424c5053;

  /// Parses a `.splatb`. Throws [FormatException] on anything else.
  factory SplatCloud.parse(Uint8List bytes) {
    if (bytes.length < _headerBytes) {
      throw const FormatException('not a splat file — too short for a header');
    }

    // A `Float32List.view` needs its offset to be 4-byte aligned *within the
    // backing buffer*, and `bytes.offsetInBytes` is not guaranteed to be zero —
    // a Uint8List handed over from a plugin can be a window into a larger
    // buffer. Re-copying when that happens costs one allocation once, and skips
    // an alignment crash that would only appear on some platforms.
    final aligned = bytes.offsetInBytes % 4 == 0 ? bytes : Uint8List.fromList(bytes);
    final base = aligned.offsetInBytes;
    final header = ByteData.view(aligned.buffer, base, _headerBytes);

    if (header.getUint32(0, Endian.little) != _magic) {
      throw const FormatException('not a splat file — bad magic');
    }
    final version = header.getUint32(4, Endian.little);
    if (version != 1) {
      throw FormatException('this build cannot read splat format v$version');
    }

    final count = header.getUint32(8, Endian.little);
    final source = header.getUint32(12, Endian.little);
    if (count == 0) throw const FormatException('this splat has no gaussians');

    final expected = _headerBytes + count * 20;
    if (aligned.length < expected) {
      throw FormatException(
        'truncated splat: $count gaussians need $expected bytes, got ${aligned.length}',
      );
    }

    final positionsAt = base + _headerBytes;
    final radiiAt = positionsAt + count * 12;
    final colorsAt = radiiAt + count * 4;

    return SplatCloud(
      count: count,
      source: source,
      positions: Float32List.view(aligned.buffer, positionsAt, count * 3),
      radii: Float32List.view(aligned.buffer, radiiAt, count),
      colors: Uint8List.view(aligned.buffer, colorsAt, count * 4),
      center: [
        header.getFloat32(16, Endian.little),
        header.getFloat32(20, Endian.little),
        header.getFloat32(24, Endian.little),
      ],
      extent: header.getFloat32(28, Endian.little),
    );
  }
}

/// Download progress, or the finished cloud.
class SplatProgress {
  const SplatProgress(this.received, this.total);

  final int received;

  /// Zero when the server did not say — Supabase Storage's download API does
  /// not stream, so this is the file's size only when it was already known.
  final int total;

  double? get fraction => total > 0 ? received / total : null;
}

/// Fetches a published splat out of the shared `splats` bucket, and keeps it.
///
/// The same disk-cache-then-serve shape as [MediaCache], and for the same
/// reason with one addition: a `.splatb` is ~4 MB and, unlike a GLB, is
/// *immutable under its key* — the object is named after the training step it
/// was exported at, so `bardo_museum/point_cloud_7000.splatb` never changes
/// content. Re-downloading it on every open would be four megabytes of a
/// traveller's data allowance spent to get the same bytes back.
class SplatLoader {
  const SplatLoader._();

  /// Loads the splat at [storagePath] (`splats/<scene>/<name>.splatb`).
  ///
  /// [onProgress] is called while downloading and not at all on a cache hit,
  /// which is the difference the caller wants to draw: a first open shows a
  /// progress bar, a second one opens.
  static Future<SplatCloud> load(
    String storagePath, {
    void Function(SplatProgress)? onProgress,
  }) async {
    final cached = await _cacheFile(storagePath);
    if (await cached.exists() && await cached.length() > 0) {
      return SplatCloud.parse(await cached.readAsBytes());
    }

    // `download` rather than a signed URL and an HTTP GET: the bucket is
    // private and this call already carries the session, so signing first would
    // be a round trip to obtain a URL the same client is about to fetch.
    // The cost is that it resolves in one go, so there is no byte-by-byte
    // progress — hence the two-step report below rather than a fake ramp.
    onProgress?.call(const SplatProgress(0, 0));
    final bytes = await Supabase.instance.client.storage
        .from('splats')
        .download(storagePath.replaceFirst('splats/', ''));
    if (bytes.isEmpty) {
      throw const FormatException('the splat came back empty');
    }
    onProgress?.call(SplatProgress(bytes.length, bytes.length));

    // Parse before caching, so a corrupt download is never written to disk as a
    // file every later open would accept.
    final cloud = SplatCloud.parse(bytes);

    // Beside the real path, then renamed: rename is atomic, so being killed
    // mid-write leaves a stray `.part` rather than a truncated file.
    try {
      final partial = File('${cached.path}.part');
      await partial.writeAsBytes(bytes, flush: true);
      await partial.rename(cached.path);
    } catch (_) {
      // A full disk should not stop the scene the traveller is waiting for from
      // opening; it only means the next open downloads again.
    }

    return cloud;
  }

  static Future<File> _cacheFile(String storagePath) async {
    final dir = await getApplicationCacheDirectory();
    final safe = storagePath.replaceAll(RegExp(r'[\\/\s]'), '_');
    return File('${dir.path}/$safe');
  }
}
