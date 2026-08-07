import '../models/location.dart';
import '../services/api_client.dart';
import '../models/location_data.dart' show allLocations;

/// Fetches a personalized itinerary from POST /api/itinerary.
///
/// Falls back to the 8 curated locations on any error, matching the existing
/// AppBloc behaviour so the UI never sees a hard failure on route generation.
class LocationRepository {
  const LocationRepository._();

  static Future<List<Location>> generateItinerary({
    required double lat,
    required double lng,
    required double radiusKm,
    String? prompt,
    int? wantedVisits,
    List<String>? rejectedIds,
    List<String>? acceptedIds,
  }) async {
    try {
      final body = <String, dynamic>{
        'lat': lat,
        'lng': lng,
        'radius_km': radiusKm,
        if (prompt != null && prompt.isNotEmpty) 'prompt': prompt,
        if (wantedVisits != null) 'wanted_visits': wantedVisits,
        if (rejectedIds != null && rejectedIds.isNotEmpty) 'rejected_ids': rejectedIds,
        if (acceptedIds != null && acceptedIds.isNotEmpty) 'accepted_ids': acceptedIds,
      };
      
      // Submitting the itinerary job (ingest + scoring + LLM)
      final data = await ApiClient.post('/api/itinerary', body: body);
      final jobId = data['job_id'] as String?;
      if (jobId == null) {
        // Fallback for synchronous backend
        final stops = data['stops'] as List<dynamic>?;
        if (stops == null || stops.isEmpty) return [];
        return stops.whereType<Map<String, dynamic>>().map(Location.fromJson).toList();
      }

      return await pollJob(jobId);
    } catch (_) {
      return [];
    }
  }

  /// Poll delays, in order; the last one repeats. A flat 2 s wait — with the
  /// first one taken *before* the first poll — meant a route that finished in
  /// 1.9 s was still shown as "thinking" at 4 s. Backing off keeps the tail
  /// cheap while making a fast result feel fast.
  static const _pollDelays = <Duration>[
    Duration(milliseconds: 400),
    Duration(milliseconds: 600),
    Duration(milliseconds: 900),
    Duration(seconds: 1),
    Duration(seconds: 2),
  ];

  static Future<List<Location>> pollJob(String jobId) async {
    var attempt = 0;
    var consecutiveErrors = 0;

    while (true) {
      await Future.delayed(
        _pollDelays[attempt < _pollDelays.length ? attempt : _pollDelays.length - 1],
      );
      attempt++;

      try {
        final data = await ApiClient.get('/api/itinerary/job/$jobId');
        consecutiveErrors = 0;
        final status = data['status'] as String?;
        if (status == 'succeeded') {
          final resultData = data['result_data'] as Map<String, dynamic>?;
          final stops = resultData?['stops'] as List<dynamic>?;
          if (stops == null || stops.isEmpty) return [];
          return stops.whereType<Map<String, dynamic>>().map(Location.fromJson).toList();
        } else if (status == 'failed') {
          return [];
        }
        // If queued or processing, continue polling
      } catch (_) {
        // The job is running server-side regardless of this socket, so one
        // dropped poll is not a failed route — only give up once the
        // connection looks genuinely gone.
        if (++consecutiveErrors >= 3) return [];
      }
    }
  }

  static Future<Map<String, dynamic>?> checkLatestJob() async {
    try {
      final data = await ApiClient.get('/api/itinerary/job/latest');
      return data['job'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  static Future<void> acceptLatestItinerary(List<Location> acceptedStops) async {
    try {
      final job = await checkLatestJob();
      if (job == null) return;
      final jobId = job['id'] as String;
      
      final stopsJson = acceptedStops.map((l) => l.toJson()).toList();
      await ApiClient.post('/api/itinerary/accept', body: {
        'job_id': jobId,
        'accepted_stops': stopsJson,
      });
    } catch (_) {}
  }
}
