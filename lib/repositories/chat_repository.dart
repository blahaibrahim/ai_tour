import '../blocs/app/app_state.dart';
import '../services/api_client.dart';
import '../services/backend_monitor.dart';
import '../services/demo_data.dart';

/// Wraps /api/chat — grounded place chat.
///
/// `modifyRoute` (POST /api/itinerary/modify) is gone with the rest of the old
/// itinerary module. Route changes now go through the Route Generation
/// module's refine call in [RouteRepository], which re-runs clustering and
/// ordering rather than asking an LLM to re-pick stops.
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

    try {
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
    } catch (e) {
      if ((e is ApiException && e.isTransport) || isConnectivityError(e)) {
        return DemoData.chatAnswer(
          locationName: locationName,
          blurb: blurb,
          question: question,
        );
      }
      rethrow;
    }
  }
}
