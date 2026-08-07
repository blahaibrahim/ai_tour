import '../blocs/app/app_state.dart';
import '../models/location.dart';
import '../services/api_client.dart';

/// Wraps /api/chat and /api/itinerary/modify.
class ChatRepository {
  const ChatRepository._();

  /// Sends a question about a specific location and returns the AI response.
  ///
  /// The place details travel with the question because generated routes use
  /// live OSM ids (`osm-way-…`) that the server's `locations` catalogue has no
  /// row for — grounding the answer on the id alone gave a 404 for every stop.
  static Future<String> askAboutPlace({
    required String locationId,
    required String locationName,
    required String blurb,
    required String question,
    required List<ChatMessage> history,
    String? category,
    String? region,
  }) async {
    final historyPayload = history
        .map((m) => {'role': m.role == 'ai' ? 'assistant' : m.role, 'content': m.text})
        .toList();

    final data = await ApiClient.post('/api/chat', body: {
      'location_id': locationId,
      'location_name': locationName,
      'blurb': blurb,
      if (category != null && category.isNotEmpty) 'category': category,
      if (region != null && region.isNotEmpty) 'region': region,
      'question': question,
      'history': historyPayload,
    });
    return data['answer'] as String? ?? "I'm not sure — try asking differently.";
  }

  /// Modifies an existing route based on a user's change request.
  static Future<List<Location>> modifyRoute({
    required double lat,
    required double lng,
    required List<Location> existingStops,
    required String changeRequest,
    double radiusKm = 20,
  }) async {
    // Full stops, not just {id, name}: the backend re-offers the current route
    // as candidates so "keep these" is expressible, and it needs lat/lng to
    // order a kept stop and photo_url to avoid re-resolving one it already has.
    final stopsPayload = existingStops.map((l) => l.toJson()).toList();

    final data = await ApiClient.post('/api/itinerary/modify', body: {
      'lat': lat,
      'lng': lng,
      'radius_km': radiusKm,
      'existing_stops': stopsPayload,
      'change_request': changeRequest,
    });

    final stops = data['stops'] as List<dynamic>?;
    if (stops == null || stops.isEmpty) return existingStops;

    return stops
        .whereType<Map<String, dynamic>>()
        .map(Location.fromJson)
        .toList();
  }
}
