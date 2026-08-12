import 'dart:convert';
import 'dart:developer' as developer;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The traveller's score: what they have earned, where it is kept, and how it
/// gets there when the network is not cooperating.
///
/// Three storage layers, each doing one job:
///
///  * `public.task_completions` is the ledger — one row per task finished, with
///    a client-supplied idempotency key. It is the truth.
///  * `public.profiles.total_points` is a counter kept in step by a trigger, so
///    reading a score is one column and not a sum over history.
///  * SharedPreferences holds a cached total and an outbox of completions that
///    have not reached the server yet.
///
/// The outbox is the reason the ledger has an idempotency key. A completion
/// queued offline gets retried on the next launch, and a retry can easily be a
/// duplicate — the request may well have succeeded and only the response been
/// lost. The unique constraint absorbs that; without it every flaky moment
/// would inflate the score.
///
/// Nothing here throws. Points are a reward, not a transaction: failing to
/// record one must never take down the screen the traveller is looking at.
class PointsRepository {
  const PointsRepository._();

  static SupabaseClient get _db => Supabase.instance.client;
  static String? get _userId => _db.auth.currentUser?.id;

  // Keyed per user, not globally. Sign-out and sign-in swap identities, and a
  // shared key would show the previous traveller's score to the next one.
  static String _totalKey(String userId) => 'massar_points_total_$userId';
  static String _outboxKey(String userId) => 'massar_points_outbox_$userId';

  /// The score to show right now, without waiting for the network.
  ///
  /// Returns null when this device has never seen a total for this user, which
  /// the caller should treat as "unknown" rather than as zero — showing 0 to
  /// someone with 400 points is worse than showing nothing for a moment.
  static Future<int?> cachedTotal() async {
    final userId = _userId;
    if (userId == null) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_totalKey(userId));
    } catch (_) {
      return null;
    }
  }

  /// Reads the authoritative total and refreshes the cache.
  ///
  /// Falls back to the cached value when the server cannot be reached, so a
  /// launch with no signal shows the score from last time rather than zero.
  static Future<int?> fetchTotal() async {
    final userId = _userId;
    if (userId == null) return null;
    try {
      final row = await _db
          .from('profiles')
          .select('total_points')
          .eq('id', userId)
          .maybeSingle();
      final total = (row?['total_points'] as num?)?.toInt();
      if (total == null) return await cachedTotal();
      await _cacheTotal(userId, total);
      return total;
    } catch (error) {
      developer.log('Points fetch failed', name: 'PointsRepository', error: error);
      return await cachedTotal();
    }
  }

  /// Records one finished task.
  ///
  /// [completionKey] must be derived from what is being recorded — the route
  /// and the stop — never from the clock or a random id. It is what makes a
  /// replay after a restored session, a retried outbox entry, or the two award
  /// paths in [AppBloc] firing for the same stop add up to one award instead of
  /// three.
  ///
  /// Returns the new total when it could be determined, or null when the write
  /// was queued for later.
  static Future<int?> recordCompletion({
    required String completionKey,
    required int points,
    String? routeId,
    String? poiId,
    String taskType = 'unknown',
  }) async {
    final userId = _userId;
    if (userId == null) return null;

    final entry = _Completion(
      completionKey: completionKey,
      points: points,
      routeId: routeId,
      poiId: poiId,
      taskType: taskType,
    );

    final total = await _award(entry);
    if (total != null) {
      // The server returned the authoritative figure — no local arithmetic to
      // get wrong, and a replay returns the same number rather than a larger
      // one.
      await _cacheTotal(userId, total);
      return total;
    }

    await _enqueue(userId, entry);
    // Counted locally so the score moves the moment the task is finished. The
    // flush replaces this estimate with the server's own total, and the RPC's
    // idempotency means a duplicated flush cannot inflate it.
    return await _bumpCachedTotal(userId, points);
  }

  /// Retries everything queued while offline. Safe to call often — it exits
  /// immediately when the outbox is empty, which is the normal case.
  static Future<void> flushOutbox() async {
    final userId = _userId;
    if (userId == null) return;

    final pending = await _readOutbox(userId);
    if (pending.isEmpty) return;

    final stillPending = <_Completion>[];
    int? latestTotal;
    for (final entry in pending) {
      final total = await _award(entry);
      if (total == null) {
        stillPending.add(entry);
      } else {
        latestTotal = total;
      }
    }

    await _writeOutbox(userId, stillPending);
    // Whatever drained, the last call's return value is the current truth —
    // including the correction for any optimistic local bumps made offline.
    if (latestTotal != null) await _cacheTotal(userId, latestTotal);
  }

  /// Drops this user's cached score and queue. Called on sign-out: the next
  /// traveller on this device must not inherit the last one's total.
  static Future<void> clearFor(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_totalKey(userId));
      await prefs.remove(_outboxKey(userId));
    } catch (_) {
      // Nothing to do — a stale cache is re-keyed by user id anyway.
    }
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// Calls the one function permitted to award points.
  ///
  /// The client cannot insert into `task_completions` and cannot write
  /// `profiles.total_points` — both grants were revoked in migration
  /// 20260812130000. `award_task_points` is `SECURITY DEFINER`, decides the
  /// award server-side (so [_Completion.points] is only ever an optimistic
  /// local estimate), and is idempotent on `(user, completion_key)`.
  ///
  /// Returns the caller's authoritative new total, or null when the write
  /// should be retried later. A server that answered with a rejection returns
  /// a total of sorts too — see below — because retrying it forever is worse
  /// than dropping it.
  static Future<int?> _award(_Completion entry) async {
    try {
      final result = await _db.rpc<dynamic>('award_task_points', params: {
        'p_completion_key': entry.completionKey,
        'p_task_type': entry.taskType,
        'p_route_id': entry.routeId,
        'p_poi_id': entry.poiId,
      });
      return (result as num?)?.toInt();
    } on PostgrestException catch (error) {
      // The server answered and refused. Queuing would retry it on every
      // launch forever, so it is dropped — reported as "handled" with the
      // total left to the next [fetchTotal] to establish.
      developer.log(
        'Award rejected: ${error.message}',
        name: 'PointsRepository',
        error: error,
      );
      return await cachedTotal() ?? 0;
    } catch (error) {
      // Anything else means the server was not reached at all.
      developer.log('Award deferred', name: 'PointsRepository', error: error);
      return null;
    }
  }

  static Future<void> _cacheTotal(String userId, int total) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_totalKey(userId), total);
    } catch (_) {
      // A missing cache costs a network read, nothing more.
    }
  }

  static Future<int?> _bumpCachedTotal(String userId, int delta) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getInt(_totalKey(userId));
      // Without a baseline, `delta` alone would claim this is the whole score.
      // Leave it unknown and let the next [fetchTotal] establish it.
      if (current == null) return null;
      final next = current + delta;
      await prefs.setInt(_totalKey(userId), next);
      return next;
    } catch (_) {
      return null;
    }
  }

  static Future<List<_Completion>> _readOutbox(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_outboxKey(userId));
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map<String, dynamic>) _Completion.fromJson(item),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _writeOutbox(String userId, List<_Completion> entries) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (entries.isEmpty) {
        await prefs.remove(_outboxKey(userId));
        return;
      }
      await prefs.setString(
        _outboxKey(userId),
        jsonEncode([for (final e in entries) e.toJson()]),
      );
    } catch (_) {
      // Losing the queue loses points that were never recorded server-side.
      // Unpleasant, but not worth crashing a tour over.
    }
  }

  static Future<void> _enqueue(String userId, _Completion entry) async {
    final pending = await _readOutbox(userId);
    // Deduplicated on the way in as well as on the server, so a stop completed
    // repeatedly while offline does not queue the same award several times.
    if (pending.any((e) => e.completionKey == entry.completionKey)) return;
    await _writeOutbox(userId, [...pending, entry]);
  }
}

class _Completion {
  const _Completion({
    required this.completionKey,
    required this.points,
    required this.taskType,
    this.routeId,
    this.poiId,
  });

  final String completionKey;
  final int points;
  final String taskType;
  final String? routeId;
  final String? poiId;

  Map<String, dynamic> toJson() => {
        'completion_key': completionKey,
        'points': points,
        'task_type': taskType,
        'route_id': routeId,
        'poi_id': poiId,
      };

  factory _Completion.fromJson(Map<String, dynamic> json) => _Completion(
        completionKey: json['completion_key'] as String? ?? '',
        points: (json['points'] as num?)?.toInt() ?? 0,
        taskType: json['task_type'] as String? ?? 'unknown',
        routeId: json['route_id'] as String?,
        poiId: json['poi_id'] as String?,
      );
}
