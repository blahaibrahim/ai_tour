import '../models/route.dart';
import '../services/api_client.dart';

/// Client for the Route Generation module.
///
/// Replaces `LocationRepository`, which submitted an itinerary job and then
/// polled `/api/itinerary/job/:id` on a backoff until it finished. Generation
/// is synchronous now — the module's latency budget is under 800 ms on a cache
/// hit and 1.5 s cold — so there is no job, no polling and no resume-on-launch
/// path to maintain.
///
/// Failures are thrown, not swallowed. The old repository returned `[]` on any
/// error, which made "the backend is down", "this city isn't open yet" and
/// "nothing matched your theme" indistinguishable to the UI — and all three
/// look like an empty route to the traveller. The bloc turns each into its own
/// message instead.
class RouteRepository {
  const RouteRepository._();

  /// Cities, with the rollout status that says whether each can be routed.
  static Future<List<City>> fetchCities() async {
    final data = await ApiClient.get('/api/cities');
    return (data['cities'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(City.fromJson)
        .toList();
  }

  /// Themes and categories for the request builder, in one call — the picker
  /// needs both and they change at the same rate.
  static Future<({List<RouteTheme> themes, List<RouteCategory> categories})>
      fetchThemesAndCategories() async {
    final data = await ApiClient.get('/api/categories');
    return (
      themes: (data['themes'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(RouteTheme.fromJson)
          .toList(),
      categories: (data['categories'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(RouteCategory.fromJson)
          .toList(),
    );
  }

  /// Generates a route. One request, one response.
  static Future<GeneratedRoute> generateRoute({
    required String cityId,
    required String theme,
    required int timeBudgetMinutes,
    required TransportMode transportMode,
    List<String>? categoryKeys,
    String locale = 'en',
  }) async {
    final data = await ApiClient.post('/api/routes', body: {
      'city_id': cityId,
      'theme': theme,
      'time_budget_minutes': timeBudgetMinutes,
      'transport_mode': transportMode.wire,
      if (categoryKeys != null && categoryKeys.isNotEmpty) 'category_keys': categoryKeys,
      'locale': locale,
    });
    return GeneratedRoute.fromJson(data);
  }

  static Future<GeneratedRoute> fetchRoute(String routeId) async {
    final data = await ApiClient.get('/api/routes/$routeId');
    return GeneratedRoute.fromJson(data);
  }

  /// Re-generates a route without the given stops, after the review step.
  ///
  /// NOT IN THE DESIGN SPEC — routes are specified as immutable once
  /// generated, and there is no refinement concept in it. The server models
  /// this as "generate again, excluding these" rather than as an edit, so the
  /// immutability rule survives; the contract is provisional either way.
  static Future<GeneratedRoute> refineRoute({
    required String routeId,
    required List<String> dropPoiIds,
    required String cityId,
    required String theme,
    required int timeBudgetMinutes,
    required TransportMode transportMode,
    List<String>? categoryKeys,
  }) async {
    final data = await ApiClient.post('/api/routes/$routeId/refine', body: {
      'drop_poi_ids': dropPoiIds,
      'city_id': cityId,
      'theme': theme,
      'time_budget_minutes': timeBudgetMinutes,
      'transport_mode': transportMode.wire,
      if (categoryKeys != null && categoryKeys.isNotEmpty) 'category_keys': categoryKeys,
    });
    return GeneratedRoute.fromJson(data);
  }

  // --- progress -------------------------------------------------------------
  // Mutable walk state, kept behind its own endpoints because it lives in its
  // own tables. Starting a walk never changes the route it walks.

  static Future<RouteProgress> startProgress(String routeId) async {
    final data = await ApiClient.post('/api/routes/$routeId/progress');
    return RouteProgress.fromJson(data);
  }

  static Future<RouteProgress?> fetchProgress(String progressId) async {
    try {
      final data = await ApiClient.get('/api/progress/$progressId');
      return RouteProgress.fromJson(data);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Records an arrival at a stop.
  ///
  /// Best-effort on purpose: whether the traveller was inside the stop's
  /// `checkpointRadiusMeters`, and for how long, is the AR trigger service's
  /// decision. A dropped checkpoint must not block the tour, so this swallows
  /// its own failures rather than surfacing them.
  static Future<bool> recordCheckpoint({
    required String progressId,
    required String poiId,
  }) async {
    try {
      await ApiClient.post('/api/progress/$progressId/checkpoint', body: {'poi_id': poiId});
      return true;
    } catch (_) {
      return false;
    }
  }
}
