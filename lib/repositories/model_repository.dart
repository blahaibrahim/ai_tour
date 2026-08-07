import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/api_client.dart';

class GenerationResult {
  const GenerationResult({
    this.cached = false,
    this.outputPath,
    this.jobId,
  });
  final bool cached;
  final String? outputPath;
  final String? jobId;
}

/// Handles image upload and 3D generation job submission.
///
/// The Flask route POST /api/models/generate validates the image_path
/// against the authenticated user's captures/ prefix, so the path format
/// must be exactly "captures/{userId}/{artifactId}.jpg".
class ModelRepository {
  ModelRepository._();

  /// Uploads the compressed JPEG to the Supabase `captures` bucket.
  /// Returns the storage path used (needed by the generation request).
  static Future<String> uploadCapture({
    required String userId,
    required String artifactId,
    required List<int> bytes,
  }) async {
    final supabase = Supabase.instance.client;
    final storagePath = '$userId/$artifactId.jpg';
    final fullPath = 'captures/$storagePath';

    final uint8Bytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

    await supabase.storage.from('captures').uploadBinary(
      storagePath,
      uint8Bytes,
      fileOptions: const FileOptions(
        contentType: 'image/jpeg',
        upsert: true,     // idempotent retry
        cacheControl: '3600',
      ),
    );

    // Also upload thumbnail in parallel (fire and forget — failure is non-fatal)
    _uploadThumbnail(userId, artifactId, uint8Bytes);

    return fullPath;
  }

  static void _uploadThumbnail(
      String userId, String artifactId, Uint8List fullBytes) {
    // Thumbnail is generated in the capture flow via FlutterImageCompress
    // and passed through here. For now we re-use the full image as the thumb
    // until the AR screen passes a separate thumb buffer.
    Supabase.instance.client.storage.from('thumbnails').uploadBinary(
      '$userId/$artifactId.webp',
      fullBytes,
      fileOptions: const FileOptions(
        contentType: 'image/jpeg',
        upsert: true,
        cacheControl: '3600',
      ),
    );
  }

  /// Creates the `artifacts` row the generation job hangs off.
  ///
  /// This is not optional bookkeeping: `model_jobs.artifact_id` is a uuid with
  /// a foreign key to `artifacts.id`, so POST /api/models/generate cannot
  /// insert its job until this row exists. The app previously only built an
  /// Artifact in bloc state, which is why every camera capture failed server
  /// side while the test script — which does insert the row — worked.
  ///
  /// RLS ("own artifacts") lets the signed-in user insert their own row
  /// directly, so this needs no backend round trip.
  static Future<void> createArtifact({
    required String userId,
    required String artifactId,
    required String storagePath,
    String? title,
  }) async {
    await Supabase.instance.client.from('artifacts').insert({
      'id': artifactId,
      'user_id': userId,
      'kind': 'model',
      'title': ?title,
      'image_path': storagePath,
      // Lets a retry of the same capture reconcile to one row rather than
      // duplicating (there is a unique index on user_id + local_id).
      'local_id': artifactId,
    });
  }

  /// Submits the generation job to the Flask backend.
  static Future<GenerationResult> requestGeneration({
    required String userId,
    required String artifactId,
    required String imagePath,  // e.g. "captures/{userId}/{artifactId}.jpg"
    required String sha256,
  }) async {
    final data = await ApiClient.post('/api/models/generate', body: {
      'artifact_id': artifactId,
      'image_path': imagePath,
      'image_sha256': sha256,
    });

    if (data['cached'] == true) {
      return GenerationResult(
        cached: true,
        outputPath: data['output_path'] as String?,
      );
    }
    return GenerationResult(jobId: data['job_id'] as String?);
  }
}
