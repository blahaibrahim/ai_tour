import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Local disk cache for downloaded GLB model files.
///
/// GLB files are large (2–15 MB), never change once generated, and the
/// flutter_3d_controller needs a local file path — not a URL. This cache
/// downloads once and serves from disk forever per the doc 05 recommendation.
class MediaCache {
  const MediaCache._();

  /// Returns the local [File] for [storagePath] (e.g. "models/{uid}/{id}.glb"),
  /// downloading from Supabase Storage if not already cached.
  static Future<File?> getModel(String storagePath) async {
    try {
      final cacheFile = await _cacheFile(storagePath);
      if (await cacheFile.exists()) return cacheFile;

      // Sign a short-lived URL and download
      final supabase = Supabase.instance.client;
      final bytes = await supabase.storage.from('models').download(
        // storagePath is "models/{uid}/{id}.glb" — strip the bucket prefix
        storagePath.replaceFirst('models/', ''),
      );
      await cacheFile.writeAsBytes(bytes, flush: true);
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
}
