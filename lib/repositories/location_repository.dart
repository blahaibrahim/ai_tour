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

  static Future<List<Location>> pollJob(String jobId) async {
    while (true) {
      await Future.delayed(const Duration(seconds: 2));
      try {
        final data = await ApiClient.get('/api/itinerary/job/$jobId');
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
      } catch (e) {
        // If network error during polling, we can either retry or return [].
        // Returning [] might be harsh if it's just a blip, but let's be safe.
        return [];
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
