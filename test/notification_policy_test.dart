import 'package:flutter_test/flutter_test.dart';
import 'package:massar/services/notification_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// docs/mascot_plan.md §5.6's rate limits, which
/// `backend/server-node/src/notifications/index.ts` enforces the other half of.
/// The two have to agree — a traveller who gets a proximity alert from the
/// phone and a completion push from the server has still had two
/// notifications, and only one of the two policies is counting.
void main() {
  setUp(() {
    // Every case starts from an empty store; `claim` both reads and writes it,
    // so leaking state between tests would make them order-dependent.
    SharedPreferences.setMockInitialValues({});
  });

  // A time comfortably outside the 22:00-07:00 quiet window, so cases that are
  // not about quiet hours are never accidentally suppressed by them.
  DateTime midday(int minuteOffset) =>
      DateTime(2026, 8, 11, 12).add(Duration(minutes: minuteOffset));

  group('quiet hours', () {
    test('suppresses inside a window that wraps past midnight', () {
      expect(NotificationPolicy.isQuietHours(DateTime(2026, 8, 11, 23)), isTrue);
      expect(NotificationPolicy.isQuietHours(DateTime(2026, 8, 11, 3)), isTrue);
      expect(NotificationPolicy.isQuietHours(DateTime(2026, 8, 11, 22)), isTrue);
    });

    test('allows outside it, with the end hour itself already awake', () {
      expect(NotificationPolicy.isQuietHours(DateTime(2026, 8, 11, 7)), isFalse);
      expect(NotificationPolicy.isQuietHours(DateTime(2026, 8, 11, 12)), isFalse);
      expect(NotificationPolicy.isQuietHours(DateTime(2026, 8, 11, 21, 59)), isFalse);
    });

    test('a zero-width window means never quiet', () {
      expect(
        NotificationPolicy.isQuietHours(DateTime(2026, 8, 11, 3), start: 0, end: 0),
        isFalse,
      );
    });

    test('a non-wrapping window works too', () {
      expect(
        NotificationPolicy.isQuietHours(DateTime(2026, 8, 11, 10), start: 9, end: 17),
        isTrue,
      );
      expect(
        NotificationPolicy.isQuietHours(DateTime(2026, 8, 11, 20), start: 9, end: 17),
        isFalse,
      );
    });

    test('claim refuses during quiet hours', () async {
      final allowed = await NotificationPolicy.claim(
        kind: NotificationKind.mascotNearby,
        subject: 'spawn-1',
        now: DateTime(2026, 8, 11, 2),
      );
      expect(allowed, isFalse);
    });
  });

  group('cooldown', () {
    test('a second claim inside 15 minutes is refused', () async {
      expect(
        await NotificationPolicy.claim(
          kind: NotificationKind.mascotNearby,
          subject: 'spawn-1',
          now: midday(0),
        ),
        isTrue,
      );
      expect(
        await NotificationPolicy.claim(
          kind: NotificationKind.mascotNearby,
          subject: 'spawn-1',
          now: midday(14),
        ),
        isFalse,
      );
    });

    test('and is allowed again once it has elapsed', () async {
      await NotificationPolicy.claim(
        kind: NotificationKind.mascotNearby,
        subject: 'spawn-1',
        now: midday(0),
      );
      expect(
        await NotificationPolicy.claim(
          kind: NotificationKind.mascotNearby,
          subject: 'spawn-1',
          now: midday(16),
        ),
        isTrue,
      );
    });

    test('is per subject, so a second mascot on the same walk still alerts', () async {
      await NotificationPolicy.claim(
        kind: NotificationKind.mascotNearby,
        subject: 'spawn-1',
        now: midday(0),
      );
      expect(
        await NotificationPolicy.claim(
          kind: NotificationKind.mascotNearby,
          subject: 'spawn-2',
          now: midday(1),
        ),
        isTrue,
      );
    });

    test('BURNING speaks over HOT\'s cooldown for the same spawn', () async {
      // §5.6's upgrade: "you're getting warm" and "open the camera" are
      // different messages, and the second is the one that matters. The call
      // site distinguishes them by suffixing the subject.
      await NotificationPolicy.claim(
        kind: NotificationKind.mascotNearby,
        subject: 'spawn-1',
        now: midday(0),
      );
      expect(
        await NotificationPolicy.claim(
          kind: NotificationKind.mascotNearby,
          subject: 'spawn-1:burning',
          now: midday(1),
        ),
        isTrue,
      );
    });

    test('forget clears it', () async {
      await NotificationPolicy.claim(
        kind: NotificationKind.mascotNearby,
        subject: 'spawn-1',
        now: midday(0),
      );
      await NotificationPolicy.forget(NotificationKind.mascotNearby, 'spawn-1');
      expect(
        await NotificationPolicy.claim(
          kind: NotificationKind.mascotNearby,
          subject: 'spawn-1',
          now: midday(1),
        ),
        isTrue,
      );
    });
  });

  group('daily cap', () {
    test('stops at six, counting across subjects', () async {
      for (var i = 0; i < NotificationPolicy.maxPerDay; i++) {
        expect(
          await NotificationPolicy.claim(
            kind: NotificationKind.mascotNearby,
            subject: 'spawn-$i',
            now: midday(i * 20),
          ),
          isTrue,
          reason: 'claim ${i + 1} of ${NotificationPolicy.maxPerDay}',
        );
      }
      expect(
        await NotificationPolicy.claim(
          kind: NotificationKind.mascotNearby,
          subject: 'spawn-over',
          now: midday(200),
        ),
        isFalse,
      );
    });

    test('resets on the next local day', () async {
      for (var i = 0; i < NotificationPolicy.maxPerDay; i++) {
        await NotificationPolicy.claim(
          kind: NotificationKind.mascotNearby,
          subject: 'spawn-$i',
          now: midday(i * 20),
        );
      }
      expect(
        await NotificationPolicy.claim(
          kind: NotificationKind.mascotNearby,
          subject: 'spawn-tomorrow',
          now: midday(0).add(const Duration(days: 1)),
        ),
        isTrue,
      );
    });

    test('what the traveller asked for does not spend the budget', () async {
      // A route they pressed a button and waited for, or a model they
      // photographed, is not the app volunteering something — being over cap
      // is not a reason to leave them waiting on it.
      for (var i = 0; i < NotificationPolicy.maxPerDay; i++) {
        await NotificationPolicy.claim(
          kind: NotificationKind.mascotNearby,
          subject: 'spawn-$i',
          now: midday(i * 20),
        );
      }
      expect(
        await NotificationPolicy.claim(
          kind: NotificationKind.modelReady,
          subject: 'job-1',
          countsTowardDailyCap: false,
          now: midday(200),
        ),
        isTrue,
      );
    });

    test('an uncapped claim does not consume the budget either', () async {
      for (var i = 0; i < 3; i++) {
        await NotificationPolicy.claim(
          kind: NotificationKind.modelReady,
          subject: 'job-$i',
          countsTowardDailyCap: false,
          now: midday(i * 20),
        );
      }
      // All six hunt alerts should still be available.
      for (var i = 0; i < NotificationPolicy.maxPerDay; i++) {
        expect(
          await NotificationPolicy.claim(
            kind: NotificationKind.mascotNearby,
            subject: 'spawn-$i',
            now: midday(100 + i * 20),
          ),
          isTrue,
        );
      }
    });
  });

  test('kinds are namespaced, so a job id and a spawn id cannot collide', () async {
    expect(
      await NotificationPolicy.claim(
        kind: NotificationKind.modelReady,
        subject: 'shared-id',
        now: midday(0),
      ),
      isTrue,
    );
    expect(
      await NotificationPolicy.claim(
        kind: NotificationKind.routeReady,
        subject: 'shared-id',
        now: midday(1),
      ),
      isTrue,
    );
  });

  test('wire values match the server\'s NotificationKind', () {
    expect(NotificationKind.routeReady.wire, 'route_ready');
    expect(NotificationKind.modelReady.wire, 'model_ready');
    expect(NotificationKind.mascotNearby.wire, 'mascot_nearby');
  });
}
