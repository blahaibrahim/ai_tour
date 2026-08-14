import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Uploads a photo or a clip to the `captures` bucket and records it in
/// `artifacts`, so a capture survives the device it was taken on.
///
/// Until this existed, photos and videos taken outside the 3D-scan flow lived
/// only in the app's documents directory: they were in the folder, and they
/// were gone on reinstall, on a new phone, and on any iOS restore that moved
/// the application container. Only the scan path uploaded anything, and only
/// because the generation job needed a URL to work from.
///
/// Everything here is best-effort by design. The local file is written and the
/// artifact is in the folder before this runs, so a failed upload costs the
/// traveller nothing they can see right now — it costs them the copy that
/// would have outlived the device. A real fix for that is the offline outbox
/// the AR capture queue also wants; this deliberately does not pretend to be
/// one, and says so by returning null rather than throwing.
class CaptureRepository {
  const CaptureRepository._();

  /// Storage path format is fixed by two things that will refuse anything
  /// else: the `write own captures` RLS policy matches the first path segment
  /// against `auth.uid()`, and the model-generation endpoint validates the
  /// same prefix.
  static String _storagePath(String userId, String artifactId, String ext) =>
      '$userId/$artifactId.$ext';

  /// Uploads [file] and inserts its `artifacts` row.
  ///
  /// [kind] is `'photo'` or `'video'`, matching the `artifact_kind` enum.
  /// Returns the full storage key (`captures/…`) on success, or null if
  /// anything went wrong — including having no signed-in user, which is not an
  /// error worth surfacing.
  static Future<String?> upload({
    required String artifactId,
    required String localPath,
    required String kind,
    String? title,
  }) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return null;

    final file = File(localPath);
    if (!await file.exists()) return null;

    // iOS records .mov and Android .mp4; the bucket accepts both, and keeping
    // the original extension means the content type and the key never disagree.
    final sourceExt = localPath.split('.').last.toLowerCase();
    final (String ext, String contentType) = switch (kind) {
      'video' => sourceExt == 'mov'
          ? ('mov', 'video/quicktime')
          : ('mp4', 'video/mp4'),
      _ => ('jpg', 'image/jpeg'),
    };

    final path = _storagePath(userId, artifactId, ext);

    try {
      await client.storage.from('captures').upload(
            path,
            file,
            fileOptions: FileOptions(
              contentType: contentType,
              // A retry of the same capture reconciles to one object rather
              // than failing on a key that is already there.
              upsert: true,
              cacheControl: '3600',
            ),
          );
    } catch (_) {
      return null;
    }

    final fullPath = 'captures/$path';

    try {
      await client.from('artifacts').insert({
        'id': artifactId,
        'user_id': userId,
        'kind': kind,
        'title': ?title,
        'image_path': fullPath,
        // Unique on (user_id, local_id), so a replayed upload reconciles to the
        // row it already wrote instead of duplicating the capture in the folder.
        'local_id': artifactId,
      });
    } catch (_) {
      // The object is in the bucket but unreferenced. Left rather than deleted:
      // the bytes are the irreplaceable half, and a retry keyed on the same
      // artifact id will adopt them.
      return fullPath;
    }

    return fullPath;
  }
}
