import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/route.dart';
import '../services/api_client.dart';
import '../services/backend_monitor.dart';
import '../services/demo_data.dart';

/// Client for the Route Generation module.
///
/// Replaces `LocationRepository`, which submitted an itinerary job and then
/// polled `/api/itinerary/job/:id` on a backoff until it finished. Generation
/// is synchronous now — the module's latency budget is under 800 ms on a cache
/// hit and 1.5 s cold — so there is no job, no polling and no resume-on-launch
/// path to maintain.
///
/// Failures are thrown, not swallowed — except when the backend can't be
/// reached at all, in which case every method below serves [DemoData] instead
/// of throwing. That keeps "this city isn't open yet" and "nothing matched
/// your theme" — real answers from a server that's actually up — distinct
/// from "the backend is down", which the traveller should never have to see
/// as an error screen when there's a perfectly good demo route to show
/// instead. The bloc turns whatever does get thrown into its own message.
class RouteRepository {
  const RouteRepository._();

  static String? get _userId => Supabase.instance.client.auth.currentUser?.id;
  static String _checkpointOutboxKey(String userId) =>
      'massar_checkpoint_outbox_$userId';

  /// Cities, with the rollout status that says whether each can be routed.
  static Future<List<City>> fetchCities() async {
    try {
      final data = await ApiClient.get('/api/cities');
      return (data['cities'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(City.fromJson)
          .toList();
    } catch (e) {
      if (_isBackendUnreachable(e)) return DemoData.cities;
      rethrow;
    }
  }

  /// Themes and categories for the request builder, in one call — the picker
  /// needs both and they change at the same rate.
  static Future<({List<RouteTheme> themes, List<RouteCategory> categories})>
      fetchThemesAndCategories() async {
    try {
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
    } catch (e) {
      if (_isBackendUnreachable(e)) {
        return (themes: DemoData.themes, categories: DemoData.categories);
      }
      rethrow;
    }
  }

  /// Generates a route. One request, one response.
  ///
  /// [categoryKeys] is a hard filter — the request builder's own chip
  /// selection, narrowing eligibility. [preferredCategoryKeys] is a ranking
  /// preference — categories `PromptInterpretationRepository` read out of the
  /// free-text prompt — and never excludes a stop on its own; see
  /// `RouteRequest.preferredCategoryKeys` on the server for the reasoning.
  static Future<GeneratedRoute> generateRoute({
    required String cityId,
    required String theme,
    required int timeBudgetMinutes,
    required TransportMode transportMode,
    List<String>? categoryKeys,
    List<String>? preferredCategoryKeys,
    String locale = 'en',
  }) async {
    try {
      final data = await ApiClient.post('/api/routes', body: {
        'city_id': cityId,
        'theme': theme,
        'time_budget_minutes': timeBudgetMinutes,
        'transport_mode': transportMode.wire,
        if (categoryKeys != null && categoryKeys.isNotEmpty) 'category_keys': categoryKeys,
        if (preferredCategoryKeys != null && preferredCategoryKeys.isNotEmpty)
          'preferred_category_keys': preferredCategoryKeys,
        'locale': locale,
      });
      return GeneratedRoute.fromJson(data);
    } catch (e) {
      if (_isBackendUnreachable(e)) {
        return DemoData.route(
          cityId: cityId,
          theme: theme,
          timeBudgetMinutes: timeBudgetMinutes,
          transportMode: transportMode,
          categoryKeys: categoryKeys,
        );
      }
      rethrow;
    }
  }

  static Future<GeneratedRoute> fetchRoute(String routeId) async {
    final data = await ApiClient.get('/api/routes/$routeId');
    return GeneratedRoute.fromJson(data);
  }

  /// The traveller's own past routes, newest first.
  ///
  /// Returns an empty list rather than throwing on any failure — including a
  /// real one. This feeds a history list on the home screen, which has an empty
  /// state that reads perfectly well as "you have not made one yet"; an error
  /// banner on the first screen after launch would be a worse answer to a
  /// question nobody asked. There is deliberately no [DemoData] fallback
  /// either: inventing a past route a traveller never took, which then opens as
  /// something else, is worse than showing none.
  static Future<List<RouteSummary>> fetchMyRoutes({int limit = 20}) async {
    try {
      final data = await ApiClient.get('/api/routes/mine?limit=$limit');
      return (data['routes'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(RouteSummary.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
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
    List<String>? preferredCategoryKeys,
  }) async {
    try {
      final data = await ApiClient.post('/api/routes/$routeId/refine', body: {
        'drop_poi_ids': dropPoiIds,
        'city_id': cityId,
        'theme': theme,
        'time_budget_minutes': timeBudgetMinutes,
        'transport_mode': transportMode.wire,
        if (categoryKeys != null && categoryKeys.isNotEmpty) 'category_keys': categoryKeys,
        if (preferredCategoryKeys != null && preferredCategoryKeys.isNotEmpty)
          'preferred_category_keys': preferredCategoryKeys,
      });
      return GeneratedRoute.fromJson(data);
    } catch (e) {
      if (_isBackendUnreachable(e)) {
        // routeId here is either a real server id (backend just dropped
        // between the original generation and this refine — rare) or already
        // a `demo-route-` id from the fallback above. Either way there's no
        // server copy of the route to refine, so a fresh demo route rebuilt
        // straight from the request is the closest honest substitute.
        return DemoData.route(
          cityId: cityId,
          theme: theme,
          timeBudgetMinutes: timeBudgetMinutes,
          transportMode: transportMode,
          categoryKeys: categoryKeys,
          excludePoiIds: dropPoiIds,
        );
      }
      rethrow;
    }
  }

  // --- progress -------------------------------------------------------------
  // Mutable walk state, kept behind its own endpoints because it lives in its
  // own tables. Starting a walk never changes the route it walks.

  static Future<RouteProgress> startProgress(String routeId) async {
    try {
      final data = await ApiClient.post('/api/routes/$routeId/progress');
      return RouteProgress.fromJson(data);
    } catch (e) {
      if (_isBackendUnreachable(e)) return DemoData.progress(routeId);
      rethrow;
    }
  }

  static Future<RouteProgress?> fetchProgress(String progressId) async {
    try {
      final data = await ApiClient.get('/api/progress/$progressId');
      return RouteProgress.fromJson(data);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      if (_isBackendUnreachable(e)) return DemoData.progress(progressId);
      rethrow;
    } catch (e) {
      if (_isBackendUnreachable(e)) return DemoData.progress(progressId);
      rethrow;
    }
  }

  /// Records an arrival at a stop.
  ///
  /// Best-effort on purpose: whether the traveller was inside the stop's
  /// `checkpointRadiusMeters`, and for how long, is the AR trigger service's
  /// decision. A dropped checkpoint must not block the tour, so this swallows
  /// its own failures — but unlike before, failures are **queued** in a
  /// SharedPreferences outbox and retried when connectivity returns.
  static Future<bool> recordCheckpoint({
    required String progressId,
    required String poiId,
  }) async {
    try {
      await ApiClient.post('/api/progress/$progressId/checkpoint', body: {'poi_id': poiId});
      return true;
    } catch (e) {
      if (e is ApiException && !e.isRetryable) {
        // The server answered and explicitly rejected it (e.g. 400 or 409).
        // Queuing would retry it on every launch forever, so it is dropped.
        return false;
      }
      
      // Enqueue for later — the tour continues regardless.
      await _enqueueCheckpoint(_CheckpointEntry(
        progressId: progressId,
        poiId: poiId,
        timestamp: DateTime.now().toIso8601String(),
      ));
      return false;
    }
  }

  /// Retries all checkpoints queued while offline. Safe to call often — exits
  /// immediately when the outbox is empty.
  ///
  /// Returns the number of entries that were successfully flushed.
  static Future<int> flushCheckpointOutbox() async {
    final userId = _userId;
    if (userId == null) return 0;

    final pending = await _readCheckpointOutbox(userId);
    if (pending.isEmpty) return 0;

    final stillPending = <_CheckpointEntry>[];
    var flushed = 0;
    for (final entry in pending) {
      try {
        await ApiClient.post(
          '/api/progress/${entry.progressId}/checkpoint',
          body: {'poi_id': entry.poiId},
        );
        flushed++;
      } catch (e) {
        if (e is ApiException && !e.isRetryable) {
          // The server rejected it. Drop it.
        } else {
          // Network error or 5xx. Keep it in the outbox.
          stillPending.add(entry);
        }
      }
    }

    await _writeCheckpointOutbox(userId, stillPending);
    return flushed;
  }

  /// How many checkpoint entries are waiting to sync.
  static Future<int> pendingCheckpointCount() async {
    final userId = _userId;
    if (userId == null) return 0;
    return (await _readCheckpointOutbox(userId)).length;
  }

  // -- checkpoint outbox internals -------------------------------------------

  static Future<List<_CheckpointEntry>> _readCheckpointOutbox(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_checkpointOutboxKey(userId));
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map<String, dynamic>) _CheckpointEntry.fromJson(item),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _writeCheckpointOutbox(
      String userId, List<_CheckpointEntry> entries) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (entries.isEmpty) {
        await prefs.remove(_checkpointOutboxKey(userId));
        return;
      }
      await prefs.setString(
        _checkpointOutboxKey(userId),
        jsonEncode([for (final e in entries) e.toJson()]),
      );
    } catch (_) {
      // Losing the queue loses checkpoints — unfortunate but not tour-breaking.
    }
  }

  static Future<void> _enqueueCheckpoint(_CheckpointEntry entry) async {
    final userId = _userId;
    if (userId == null) return;
    final pending = await _readCheckpointOutbox(userId);
    // Deduplicate: same progress + POI means the same arrival.
    if (pending.any((e) =>
        e.progressId == entry.progressId && e.poiId == entry.poiId)) {
      return;
    }
    await _writeCheckpointOutbox(userId, [...pending, entry]);
  }
}

/// True when [error] means the backend couldn't be reached at all, as
/// opposed to a reachable server answering with a real error — the only
/// condition under which [RouteRepository] serves [DemoData] instead of
/// throwing.
bool _isBackendUnreachable(Object error) =>
    (error is ApiException && error.isTransport) || isConnectivityError(error);

/// A checkpoint recorded during the tour, queued for sync.
class _CheckpointEntry {
  const _CheckpointEntry({
    required this.progressId,
    required this.poiId,
    required this.timestamp,
  });

  final String progressId;
  final String poiId;
  final String timestamp;

  Map<String, dynamic> toJson() => {
        'progress_id': progressId,
        'poi_id': poiId,
        'timestamp': timestamp,
      };

  factory _CheckpointEntry.fromJson(Map<String, dynamic> json) =>
      _CheckpointEntry(
        progressId: json['progress_id'] as String? ?? '',
        poiId: json['poi_id'] as String? ?? '',
        timestamp: json['timestamp'] as String? ?? '',
      );
}

