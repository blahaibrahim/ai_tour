import 'dart:convert';
import 'dart:developer' as developer;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A traveller's score and their wallet, which are two numbers and not one.
///
/// `total` is everything ever earned and never goes down — it is the figure a
/// rank or a level is computed from. `balance` is what is left to spend, and it
/// moves in both directions: up on a verified completion, down on a redemption.
///
/// They are not related by a subtraction. A task finished away from the stop it
/// belongs to still scores, at a third of the award, but does not reach the
/// wallet — so `balance` is its own counter maintained server-side, not
/// `total - spent`.
class PointsTotals {
  const PointsTotals({required this.total, required this.balance});

  final int total;
  final int balance;

  @override
  String toString() => 'PointsTotals(total: $total, balance: $balance)';
}

/// The traveller's score: what they have earned, where it is kept, and how it
/// gets there when the network is not cooperating.
///
/// Three storage layers, each doing one job:
///
///  * `public.task_completions` is the ledger — one row per task finished, with
///    a client-supplied idempotency key. It is the truth.
///  * `public.profiles.total_points` and `.points_balance` are counters kept in
///    step by a trigger, so reading a score is two columns and not a sum over
///    history.
///  * SharedPreferences holds cached counters and an outbox of completions that
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
/// Spending them is the opposite and lives in `RewardsRepository`, which
/// queues nothing.
class PointsRepository {
  const PointsRepository._();

  static SupabaseClient get _db => Supabase.instance.client;
  static String? get _userId => _db.auth.currentUser?.id;

  // Keyed per user, not globally. Sign-out and sign-in swap identities, and a
  // shared key would show the previous traveller's score to the next one.
  static String _totalKey(String userId) => 'massar_points_total_$userId';
  static String _balanceKey(String userId) => 'massar_points_balance_$userId';
  static String _outboxKey(String userId) => 'massar_points_outbox_$userId';

  /// The score to show right now, without waiting for the network.
  ///
  /// Returns null when this device has never seen a total for this user, which
  /// the caller should treat as "unknown" rather than as zero — showing 0 to
  /// someone with 400 points is worse than showing nothing for a moment.
  static Future<PointsTotals?> cachedTotals() async {
    final userId = _userId;
    if (userId == null) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final total = prefs.getInt(_totalKey(userId));
      if (total == null) return null;
      // A device that cached a total before the wallet existed has no balance
      // stored. Reporting the whole score as spendable would be the optimistic
      // direction and could show a reward as affordable when it is not; zero is
      // corrected by the fetch a moment later.
      return PointsTotals(
        total: total,
        balance: prefs.getInt(_balanceKey(userId)) ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// Reads the authoritative counters and refreshes the cache.
  ///
  /// Falls back to the cached values when the server cannot be reached, so a
  /// launch with no signal shows the score from last time rather than zero.
  static Future<PointsTotals?> fetchTotals() async {
    final userId = _userId;
    if (userId == null) return null;
    try {
      final row = await _db
          .from('profiles')
          .select('total_points, points_balance')
          .eq('id', userId)
          .maybeSingle();
      final total = (row?['total_points'] as num?)?.toInt();
      if (total == null) return await cachedTotals();
      final totals = PointsTotals(
        total: total,
        balance: (row?['points_balance'] as num?)?.toInt() ?? 0,
      );
      await _cache(userId, totals);
      return totals;
    } catch (error) {
      developer.log('Points fetch failed', name: 'PointsRepository', error: error);
      return await cachedTotals();
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
  /// [lat], [lng] and [accuracyMeters] are the fix the phone had at the moment
  /// the task was finished. The server checks them against the stop's own
  /// `checkpoint_radius_meters` and decides both the award and whether it is
  /// spendable; passing nothing is not an error, it just means the completion
  /// scores without reaching the wallet whenever the POI is one the catalogue
  /// knows. The client never decides any of that — it only reports where it was.
  ///
  /// Returns the new counters when they could be determined, or null when the
  /// write was queued for later.
  static Future<PointsTotals?> recordCompletion({
    required String completionKey,
    required int points,
    String? routeId,
    String? poiId,
    String taskType = 'unknown',
    double? lat,
    double? lng,
    double? accuracyMeters,
  }) async {
    final userId = _userId;
    if (userId == null) return null;

    final entry = _Completion(
      completionKey: completionKey,
      points: points,
      routeId: routeId,
      poiId: poiId,
      taskType: taskType,
      lat: lat,
      lng: lng,
      accuracyMeters: accuracyMeters,
    );

    final totals = await _award(entry);
    if (totals != null) {
      // The server returned the authoritative figures — no local arithmetic to
      // get wrong, and a replay returns the same numbers rather than larger
      // ones.
      await _cache(userId, totals);
      return totals;
    }

    await _enqueue(userId, entry);
    // Counted locally so the score moves the moment the task is finished. The
    // flush replaces this estimate with the server's own totals, and the RPC's
    // idempotency means a duplicated flush cannot inflate them.
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
    PointsTotals? latest;
    for (final entry in pending) {
      final totals = await _award(entry);
      if (totals == null) {
        stillPending.add(entry);
      } else {
        latest = totals;
      }
    }

    await _writeOutbox(userId, stillPending);
    // Whatever drained, the last call's return value is the current truth —
    // including the correction for any optimistic local bumps made offline.
    if (latest != null) await _cache(userId, latest);
  }

  /// Drops this user's cached score and queue. Called on sign-out: the next
  /// traveller on this device must not inherit the last one's total.
  static Future<void> clearFor(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_totalKey(userId));
      await prefs.remove(_balanceKey(userId));
      await prefs.remove(_outboxKey(userId));
    } catch (_) {
      // Nothing to do — a stale cache is re-keyed by user id anyway.
    }
  }

  /// Writes counters the caller obtained elsewhere — a redemption returns the
  /// balance from inside its own transaction, and the cache should not go stale
  /// waiting for the next fetch to notice.
  static Future<void> cache(PointsTotals totals) async {
    final userId = _userId;
    if (userId == null) return;
    await _cache(userId, totals);
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// Calls the one function permitted to award points.
  ///
  /// The client cannot insert into `task_completions` and cannot write
  /// `profiles.total_points` or `.points_balance` — those grants were revoked
  /// in migrations 20260812130000 and 20260817120000. `award_task_points` is
  /// `SECURITY DEFINER`, decides the award *and* the verification server-side
  /// (so [_Completion.points] is only ever an optimistic local estimate), and
  /// is idempotent on `(user, completion_key)`.
  ///
  /// Returns the caller's authoritative counters, or null when the write should
  /// be retried later. A server that answered with a rejection returns counters
  /// of sorts too — see below — because retrying it forever is worse than
  /// dropping it.
  static Future<PointsTotals?> _award(_Completion entry) async {
    try {
      final result = await _db.rpc<dynamic>('award_task_points', params: {
        'p_completion_key': entry.completionKey,
        'p_task_type': entry.taskType,
        'p_route_id': entry.routeId,
        'p_poi_id': entry.poiId,
        'p_lat': entry.lat,
        'p_lng': entry.lng,
        'p_accuracy_m': entry.accuracyMeters,
      });
      if (result is! Map) return null;
      final json = Map<String, dynamic>.from(result);
      return PointsTotals(
        total: (json['total_points'] as num?)?.toInt() ?? 0,
        balance: (json['points_balance'] as num?)?.toInt() ?? 0,
      );
    } on PostgrestException catch (error) {
      // The server answered and refused. Queuing would retry it on every
      // launch forever, so it is dropped — reported as "handled" with the
      // counters left to the next [fetchTotals] to establish.
      developer.log(
        'Award rejected: ${error.message}',
        name: 'PointsRepository',
        error: error,
      );
      return await cachedTotals() ?? const PointsTotals(total: 0, balance: 0);
    } catch (error) {
      // Anything else means the server was not reached at all.
      developer.log('Award deferred', name: 'PointsRepository', error: error);
      return null;
    }
  }

  static Future<void> _cache(String userId, PointsTotals totals) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_totalKey(userId), totals.total);
      await prefs.setInt(_balanceKey(userId), totals.balance);
    } catch (_) {
      // A missing cache costs a network read, nothing more.
    }
  }

  /// Moves the cached *score* only.
  ///
  /// The balance is deliberately left where it is: whether an award is
  /// spendable depends on a check the server makes against the POI's real
  /// coordinates, and this device cannot know the answer while it is offline.
  /// Guessing high would let the rewards screen offer something the traveller
  /// cannot actually afford, and nothing can be redeemed offline anyway.
  static Future<PointsTotals?> _bumpCachedTotal(String userId, int delta) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getInt(_totalKey(userId));
      // Without a baseline, `delta` alone would claim this is the whole score.
      // Leave it unknown and let the next [fetchTotals] establish it.
      if (current == null) return null;
      final next = current + delta;
      await prefs.setInt(_totalKey(userId), next);
      return PointsTotals(
        total: next,
        balance: prefs.getInt(_balanceKey(userId)) ?? 0,
      );
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
    this.lat,
    this.lng,
    this.accuracyMeters,
  });

  final String completionKey;
  final int points;
  final String taskType;
  final String? routeId;
  final String? poiId;

  /// Where the phone was when the task was finished — carried through the
  /// outbox so a completion recorded in the Tassili and flushed three days
  /// later is still checked against where it actually happened, not against
  /// wherever the traveller is standing when the signal comes back.
  final double? lat;
  final double? lng;
  final double? accuracyMeters;

  Map<String, dynamic> toJson() => {
        'completion_key': completionKey,
        'points': points,
        'task_type': taskType,
        'route_id': routeId,
        'poi_id': poiId,
        'lat': lat,
        'lng': lng,
        'accuracy_m': accuracyMeters,
      };

  factory _Completion.fromJson(Map<String, dynamic> json) => _Completion(
        completionKey: json['completion_key'] as String? ?? '',
        points: (json['points'] as num?)?.toInt() ?? 0,
        taskType: json['task_type'] as String? ?? 'unknown',
        routeId: json['route_id'] as String?,
        poiId: json['poi_id'] as String?,
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
        accuracyMeters: (json['accuracy_m'] as num?)?.toDouble(),
      );
}
