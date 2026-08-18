import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/reward.dart';
import '../utils/uuid.dart';

/// The catalogue, what the traveller already owns, and the one call that spends
/// points.
///
/// Talks to Supabase directly, like [SavedLocationsRepository] and
/// [PointsRepository]: `rewards` is readable to any signed-in user by policy,
/// `redemptions` is scoped to `auth.uid()`, and the spend itself is an RPC that
/// decides everything server-side. A round trip through the Node backend would
/// add a hop and no safety.
///
/// **Nothing here is queued offline, and that is the point.** [PointsRepository]
/// has an outbox because a task finished in the Tassili with no signal must not
/// be lost — earning replays safely, since a duplicate hits the ledger's unique
/// constraint. Spending does not have that property in the way that matters: two
/// redemptions queued against one balance both look affordable when they are
/// written and only one of them is, and by the time the flush discovers that,
/// the traveller has been shown two rewards. So a redemption attempted without a
/// connection fails immediately and says so.
class RewardsRepository {
  const RewardsRepository._();

  static SupabaseClient get _db => Supabase.instance.client;
  static String? get _userId => _db.auth.currentUser?.id;

  /// Everything on sale, in the order the catalogue wants it shown.
  ///
  /// Returns an empty list rather than throwing when Supabase cannot be
  /// reached: the rewards screen has its own empty state and an exception here
  /// would only turn a quiet screen into a red one.
  static Future<List<Reward>> fetchCatalogue() async {
    try {
      final rows = await _db
          .from('rewards')
          .select(
            'id, title, blurb, kind, cost_points, fulfillment, '
            'grant_model_credits, repeatable, stock, pickup_note, sort_order',
          )
          .order('sort_order');
      return [
        for (final row in rows) Reward.fromJson(row),
      ];
    } catch (error) {
      developer.log('Catalogue fetch failed',
          name: 'RewardsRepository', error: error);
      return const [];
    }
  }

  /// The ids of every non-repeatable reward this traveller has bought.
  ///
  /// There is no entitlements table: a redemption row *is* the entitlement, so
  /// this one query answers "which cosmetics do I own" for the whole screen.
  static Future<Set<String>> ownedRewardIds() async {
    final userId = _userId;
    if (userId == null) return {};
    try {
      final rows = await _db
          .from('redemptions')
          .select('reward_id')
          .eq('user_id', userId);
      return {
        for (final row in rows) row['reward_id'] as String,
      };
    } catch (_) {
      return {};
    }
  }

  /// Everything this traveller has redeemed, newest first.
  static Future<List<Redemption>> history() async {
    final userId = _userId;
    if (userId == null) return const [];
    try {
      final rows = await _db
          .from('redemptions')
          .select('id, reward_id, cost_points, code, status, expires_at, created_at')
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return [
        for (final row in rows) Redemption.fromJson(row),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Spends [reward.costPoints] and hands back what was bought.
  ///
  /// [idempotencyKey] defaults to a fresh UUID, which is right for a repeatable
  /// reward: each press is a distinct purchase. Pass a stable key to make a
  /// specific attempt retryable — a caller that wants "this exact press, once"
  /// generates the key before the first try and reuses it.
  ///
  /// The balance in [RedeemSuccess] comes out of the same transaction that made
  /// the debit, so the screen never has to do the arithmetic and can never show
  /// a figure the server disagrees with.
  static Future<RedeemResult> redeem(
    Reward reward, {
    String? idempotencyKey,
  }) async {
    if (_userId == null) {
      return const RedeemRejected(RedeemFailure.notSignedIn);
    }

    try {
      final result = await _db.rpc<dynamic>('spend_points', params: {
        'p_reward_id': reward.id,
        'p_idempotency_key': idempotencyKey ?? uuidV4(),
      });

      if (result is! Map) {
        // A shape we do not recognise. The spend may well have happened, so
        // this is not reported as a rejection that leaves points untouched —
        // the caller refreshes the balance either way.
        developer.log('Unexpected spend_points result: $result',
            name: 'RewardsRepository');
        return const RedeemRejected(RedeemFailure.unknown);
      }

      final json = Map<String, dynamic>.from(result);
      return RedeemSuccess(
        redemption: Redemption.fromJson(json),
        balance: (json['points_balance'] as num?)?.toInt() ?? 0,
      );
    } on PostgrestException catch (error) {
      // The server answered and refused. Every refusal it can make carries its
      // own SQLSTATE, so this is a decision and not a guess.
      developer.log('Redemption refused: ${error.code} ${error.message}',
          name: 'RewardsRepository');
      return RedeemRejected(RedeemFailure.fromSqlState(error.code));
    } catch (error) {
      // Anything else means Supabase was not reached. Unlike an earned point,
      // this is not queued — see the note on the class.
      developer.log('Redemption unreachable',
          name: 'RewardsRepository', error: error);
      return const RedeemRejected(RedeemFailure.offline);
    }
  }
}
