import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/location.dart';
import '../utils/artifact_naming.dart';

/// Reads the user's persisted artifacts back out of Supabase.
///
/// The write side lives in [ModelRepository] (upload → insert `artifacts` →
/// POST /api/models/generate); this is the cold-start counterpart. Without it
/// the folder was rebuilt from bloc state alone, so every generated model
/// vanished when the app was closed even though the row and the GLB were
/// sitting in the project the whole time.
class ArtifactRepository {
  ArtifactRepository._();

  /// The embedded `model_jobs` rows are what make a restored artifact show the
  /// right badge: a job still running comes back as "Generating 3D…" and stays
  /// hooked to Realtime through its job id, rather than looking like a failure.
  ///
  /// The `!model_jobs_artifact_id_fkey` hint is required, not decorative. The
  /// two tables reference each other (`model_jobs.artifact_id` and
  /// `artifacts.model_job_id`), so a bare `model_jobs(...)` embed is ambiguous
  /// and PostgREST rejects the whole request with PGRST201.
  static const String _columns = 'id, kind, title, image_path, model_path, '
      'captured_at, '
      'model_jobs!model_jobs_artifact_id_fkey(id, status, error_code, output_path, queued_at)';

  static Future<List<Artifact>> fetchAll() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return const [];

    try {
      final rows = await client
          .from('artifacts')
          .select(_columns)
          .eq('user_id', userId)
          .isFilter('deleted_at', null)
          .order('captured_at', ascending: false);

      return rows.map(_fromRow).toList();
    } catch (_) {
      // A cold start with no network shouldn't empty the folder — the caller
      // keeps whatever is already in state.
      return const [];
    }
  }

  static Artifact _fromRow(Map<String, dynamic> row) {
    final kind = row['kind'] as String? ?? 'photo';
    final title = (row['title'] as String?)?.trim();
    final name = (title == null || title.isEmpty) ? 'capture' : title;

    final job = _latestJob(row['model_jobs']);
    var modelPath = row['model_path'] as String?;
    ModelStatus? status;
    String? errorCode;

    if (kind == 'model') {
      final jobStatus = job?['status'] as String?;
      if (modelPath == null && jobStatus == 'succeeded') {
        modelPath = job?['output_path'] as String?;
      }

      if (modelPath != null) {
        status = ModelStatus.succeeded;
      } else if (job == null) {
        // The row was inserted but generation never got submitted — the app was
        // killed mid-capture. Surface it as retryable rather than as a model
        // that will never arrive.
        status = ModelStatus.failed;
        errorCode = 'internal';
      } else if (jobStatus == 'failed' || jobStatus == 'cancelled') {
        status = ModelStatus.failed;
        errorCode = job['error_code'] as String?;
      } else {
        status = ModelStatus.generating;
      }
    }

    return Artifact(
      id: row['id'] as String,
      name: name,
      region: artifactAreaLabel(name),
      kindLabel: switch (kind) {
        'model' => '3D Model',
        'video' => 'Video',
        'fennec' => 'Fennec',
        _ => 'Scan',
      },
      // The capture bucket is private, so this is a storage key, not a URL —
      // the folder grid signs it on demand.
      photoUrl: row['image_path'] as String? ?? '',
      isLocalFile: false,
      modelPath: modelPath,
      modelStatus: status,
      jobId: job?['id'] as String?,
      errorCode: errorCode,
      capturedAt: DateTime.tryParse(row['captured_at'] as String? ?? ''),
    );
  }

  /// A retried capture leaves more than one job on the artifact; the newest one
  /// is the one whose outcome the folder should show.
  static Map<String, dynamic>? _latestJob(Object? embedded) {
    final jobs = (embedded as List?)?.whereType<Map<String, dynamic>>().toList();
    if (jobs == null || jobs.isEmpty) return null;

    jobs.sort((a, b) => ((b['queued_at'] as String?) ?? '')
        .compareTo((a['queued_at'] as String?) ?? ''));
    return jobs.first;
  }
}
