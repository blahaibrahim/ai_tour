import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:massar/models/reward.dart';
import 'package:massar/l10n/app_localizations.dart';

/// The reward model is where the server's answers become something the screen
/// can act on, and both directions are easy to get quietly wrong: a mistyped
/// SQLSTATE turns "you need 300 more points" into "something went wrong", and a
/// missing field in a catalogue row turns a free reward into a crash.
void main() {
  // The English strings, loaded once. These tests assert on wording, so they
  // need the same lookup the app uses rather than the literals that used to be
  // baked into the models.
  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('parsing a catalogue row', () {
    test('reads every field the migration writes', () {
      final reward = Reward.fromJson(const {
        'id': 'model_credit',
        'title': '3D scan credit',
        'blurb': 'One more object turned into a model you can keep.',
        'kind': 'digital',
        'cost_points': 150,
        'fulfillment': 'instant',
        'grant_model_credits': 1,
        'repeatable': true,
        'stock': null,
        'pickup_note': null,
        'sort_order': 10,
      });

      expect(reward.id, 'model_credit');
      expect(reward.kind, RewardKind.digital);
      expect(reward.costPoints, 150);
      expect(reward.grantModelCredits, 1);
      expect(reward.repeatable, isTrue);
      expect(reward.stock, isNull);
      expect(reward.isVoucher, isFalse);
    });

    test('an unknown kind falls back to digital rather than throwing', () {
      // A kind added server-side before the app knows about it must not take
      // down the whole catalogue — the row is shown in the least privileged
      // group instead. `physical` is the one that gates on having an account,
      // so guessing *that* would be the dangerous direction.
      final reward = Reward.fromJson(const {
        'id': 'mystery',
        'title': 'Something new',
        'blurb': '',
        'kind': 'experience',
        'cost_points': 500,
      });

      expect(reward.kind, RewardKind.digital);
    });

    test('missing optional fields take safe defaults', () {
      final reward = Reward.fromJson(const {
        'id': 'bare',
        'title': 'Bare',
        'blurb': '',
        'kind': 'digital',
        'cost_points': 1,
      });

      expect(reward.repeatable, isFalse, reason: 'one-time is the safe default');
      expect(reward.grantModelCredits, 0);
      expect(reward.fulfillment, 'instant');
      expect(reward.soldOut, isFalse, reason: 'no stock column means unlimited');
    });
  });

  group('stock', () {
    Reward withStock(int? stock) => Reward(
          id: 'pin',
          title: 'Pin',
          blurb: '',
          kind: RewardKind.physical,
          costPoints: 4000,
          stock: stock,
        );

    test('null stock is unlimited, not zero', () {
      expect(withStock(null).soldOut, isFalse);
    });

    test('zero is sold out', () {
      expect(withStock(0).soldOut, isTrue);
    });

    test('one left is not sold out', () {
      expect(withStock(1).soldOut, isFalse);
    });
  });

  group('mapping a refusal', () {
    // Each of these is raised by public.spend_points with exactly this
    // SQLSTATE. If the migration and this table ever disagree, every refusal
    // silently becomes the generic one — which is the failure this test exists
    // to catch.
    test('every MS code the function raises has its own case', () {
      expect(RedeemFailure.fromSqlState('MS001'), RedeemFailure.insufficientPoints);
      expect(RedeemFailure.fromSqlState('MS002'), RedeemFailure.unavailable);
      expect(RedeemFailure.fromSqlState('MS003'), RedeemFailure.outOfStock);
      expect(RedeemFailure.fromSqlState('MS004'), RedeemFailure.alreadyOwned);
      expect(RedeemFailure.fromSqlState('MS005'), RedeemFailure.accountRequired);
      expect(RedeemFailure.fromSqlState('MS006'), RedeemFailure.tooMany);
      expect(RedeemFailure.fromSqlState('28000'), RedeemFailure.notSignedIn);
    });

    test('anything else is unknown rather than a guess', () {
      expect(RedeemFailure.fromSqlState('23505'), RedeemFailure.unknown);
      expect(RedeemFailure.fromSqlState(null), RedeemFailure.unknown);
      expect(RedeemFailure.fromSqlState(''), RedeemFailure.unknown);
    });

    test('every failure says something a traveller can act on', () {
      for (final failure in RedeemFailure.values) {
        expect(failure.message(l10n), isNotEmpty);
        expect(
          failure.message(l10n).toLowerCase(),
          isNot(contains('error')),
          reason: '${failure.name} should say what happened, not that it failed',
        );
      }
    });

    test('the unknown case promises the points are untouched', () {
      // True by construction: every raise in spend_points happens before the
      // debit or rolls it back, so a rejection never costs anything. Worth
      // asserting because it is the sentence that stops a traveller redeeming
      // twice after one confusing failure.
      expect(RedeemFailure.unknown.message(l10n), contains('untouched'));
    });
  });

  group('parsing a redemption', () {
    test('an instant reward comes back fulfilled with no code', () {
      final redemption = Redemption.fromJson(const {
        'id': 'a1',
        'reward_id': 'model_credit',
        'cost_points': 150,
        'code': null,
        'status': 'fulfilled',
        'expires_at': null,
        'created_at': '2026-08-17T10:00:00Z',
      });

      expect(redemption.status, 'fulfilled');
      expect(redemption.code, isNull);
      expect(redemption.expiresAt, isNull);
      expect(redemption.createdAt, isNotNull);
    });

    test('a voucher carries its code and expiry', () {
      final redemption = Redemption.fromJson(const {
        'id': 'b2',
        'reward_id': 'cafe_tea',
        'cost_points': 700,
        'code': 'K7QM4RTP',
        'status': 'issued',
        'expires_at': '2026-08-31T10:00:00Z',
        'created_at': '2026-08-17T10:00:00Z',
      });

      expect(redemption.code, 'K7QM4RTP');
      expect(redemption.status, 'issued');
      expect(redemption.expiresAt, isNotNull);
      // No 0/O/1/I — the alphabet in spend_points exists because this gets read
      // aloud across a counter.
      expect(RegExp(r'^[A-HJ-NP-Z2-9]{8}$').hasMatch(redemption.code!), isTrue);
    });
  });
}
