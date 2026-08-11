import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'demo_data.dart';

/// Local disk cache for downloaded GLB model files.
///
/// GLB files are large (2–15 MB), never change once generated, and the
/// flutter_3d_controller needs a local file path — not a URL. This cache
/// downloads once and serves from disk forever per the doc 05 recommendation.
class MediaCache {
  const MediaCache._();

  /// Returns the local [File] for [storagePath] (e.g. "models/{uid}/{id}.glb"),
  /// downloading from Supabase Storage if not already cached.
  ///
  /// [DemoData.demoModelPath] is special-cased to a bundled asset: it's what
  /// [ModelRepository.requestGeneration] hands back instead of a real
  /// storage key when the GPU backend can't be reached, so there is never a
  /// real object in Supabase Storage to download for it.
  static Future<File?> getModel(String storagePath) async {
    if (storagePath == DemoData.demoModelPath) {
      return _demoModelFile();
    }
    try {
      final cacheFile = await _cacheFile(storagePath);
      if (await cacheFile.exists()) {
        // A zero-length entry is a previous download that died between
        // creating the file and filling it. Left alone it would be served
        // forever, and the viewer renders an empty GLB as a blank screen —
        // so treat it as a miss and fetch again.
        if (await cacheFile.length() > 0) return cacheFile;
        await cacheFile.delete();
      }

      // Sign a short-lived URL and download
      final supabase = Supabase.instance.client;
      final bytes = await supabase.storage.from('models').download(
        // storagePath is "models/{uid}/{id}.glb" — strip the bucket prefix
        storagePath.replaceFirst('models/', ''),
      );
      if (bytes.isEmpty) return null;

      // Write beside the real path and rename into place. Rename is atomic, so
      // being killed mid-download leaves a stray .part rather than a truncated
      // file that every later launch would accept as a complete model.
      final partial = File('${cacheFile.path}.part');
      await partial.writeAsBytes(bytes, flush: true);
      await partial.rename(cacheFile.path);
      return cacheFile;
    } catch (_) {
      return null;
    }
  }

  static Future<File> _cacheFile(String storagePath) async {
    final dir = await getApplicationCacheDirectory();
    final safe = storagePath.replaceAll('/', '_').replaceAll(' ', '_');
    return File('${dir.path}/$safe');
  }

  /// Copies the bundled fennec GLB into the cache dir the first time it's
  /// asked for, so [ArtifactViewerScreen] can open it exactly like a
  /// downloaded model — [Flutter3DViewer] needs a real file path, not an
  /// asset key (see the comment at its call site).
  static Future<File?> _demoModelFile() async {
    try {
      final cacheFile = await _cacheFile(DemoData.demoModelPath);
      if (await cacheFile.exists() && await cacheFile.length() > 0) {
        return cacheFile;
      }
      final data = await rootBundle.load('assets/3d/rigged_animated_fennec.glb');
      final partial = File('${cacheFile.path}.part');
      await partial.writeAsBytes(data.buffer.asUint8List(), flush: true);
      await partial.rename(cacheFile.path);
      return cacheFile;
    } catch (_) {
      return null;
    }
  }

  /// Returns a signed URL for a capture photo (1-hour TTL).
  static Future<String?> captureSignedUrl(
      String userId, String artifactId) async {
    try {
      return await Supabase.instance.client.storage
          .from('captures')
          .createSignedUrl('$userId/$artifactId.jpg', 3600);
    } catch (_) {
      return null;
    }
  }

  /// Signs the `image_path` stored on an artifacts row (1-hour TTL).
  ///
  /// An artifact restored from Supabase carries a storage key, not a URL — the
  /// captures bucket is private, so the folder grid has to sign it before it
  /// can be shown.
  static Future<String?> captureSignedUrlForPath(String storagePath) async {
    if (storagePath.isEmpty) return null;
    try {
      return await Supabase.instance.client.storage
          .from('captures')
          .createSignedUrl(storagePath.replaceFirst('captures/', ''), 3600);
    } catch (_) {
      return null;
    }
  }
}
