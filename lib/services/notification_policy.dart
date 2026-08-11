import 'package:shared_preferences/shared_preferences.dart';

/// What a notification is about. The wire values match
/// `NotificationKind` in `backend/server-node/src/notifications/types.ts` and
/// the `notification_log.kind` column, so a client-side send and a server-side
/// one are countable against the same rules.
enum NotificationKind {
  routeReady('route_ready'),
  modelReady('model_ready'),
  mascotNearby('mascot_nearby');

  const NotificationKind(this.wire);
  final String wire;
}

/// docs/mascot_plan.md §5.6's rate limits, enforced on the device.
///
/// The plan specifies these for the hunt and says they are "enforced
/// client-side in `HuntSessionController` and mirrored server-side in
/// `Notification Policy` for any push". Both halves exist:
/// `backend/server-node/src/notifications/index.ts` applies them to push, this
/// applies them to the local notifications the device fires itself — and the
/// two must agree, because a traveller who gets a proximity alert from the
/// phone and a completion push from the server has still had two
/// notifications, and only one policy is counting.
///
/// State is persisted rather than held in memory: an app that has been killed
/// and relaunched has not earned a fresh six-per-day budget, and the hunt's
/// whole point is that it survives being backgrounded.
class NotificationPolicy {
  NotificationPolicy._();

  /// Max one notification per subject per 15 minutes (§5.6).
  static const Duration cooldown = Duration(minutes: 15);

  /// Max six hunt notifications per day (§5.6).
  static const int maxPerDay = 6;

  static const String _sentAtPrefix = 'notif_sent_at_';
  static const String _dayCountKey = 'notif_day_count';
  static const String _dayStampKey = 'notif_day_stamp';

  /// True if `now` falls in the traveller's quiet window, in local time.
  /// [start] == [end] means "never quiet".
  static bool isQuietHours(DateTime now, {int start = 22, int end = 7}) {
    if (start == end) return false;
    final hour = now.hour;
    return start < end ? hour >= start && hour < end : hour >= start || hour < end;
  }

  /// Decides whether a notification about [subject] may be shown, and records
  /// it if so.
  ///
  /// This both asks and claims, in one call, for the same reason the server's
  /// `notification_log.claim` does: two hunt fixes can arrive a millisecond
  /// apart, and a check that does not also consume the budget lets both
  /// through.
  ///
  /// [subject] identifies what the notification is about — a spawn id, a job
  /// id — so the cooldown is per-mascot rather than per-app, which is what
  /// makes walking past two spawns in ten minutes produce two alerts and
  /// hovering at the edge of one produce a single alert.
  ///
  /// [countsTowardDailyCap] is false for the things the traveller explicitly
  /// asked to be told about exactly once — a route they are waiting on, a
  /// model they photographed. Only the ones the app volunteers unprompted (a
  /// fennec nearby) spend from the six-per-day budget the plan sets.
  static Future<bool> claim({
    required NotificationKind kind,
    required String subject,
    bool countsTowardDailyCap = true,
    int quietHoursStart = 22,
    int quietHoursEnd = 7,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    if (isQuietHours(at, start: quietHoursStart, end: quietHoursEnd)) return false;

    final prefs = await SharedPreferences.getInstance();
    final key = '$_sentAtPrefix${kind.wire}_$subject';

    final lastMs = prefs.getInt(key);
    if (lastMs != null &&
        at.difference(DateTime.fromMillisecondsSinceEpoch(lastMs)) < cooldown) {
      return false;
    }

    if (countsTowardDailyCap) {
      final today = _dayStamp(at);
      final storedDay = prefs.getString(_dayStampKey);
      final count = storedDay == today ? (prefs.getInt(_dayCountKey) ?? 0) : 0;
      if (count >= maxPerDay) return false;
      await prefs.setString(_dayStampKey, today);
      await prefs.setInt(_dayCountKey, count + 1);
    }

    await prefs.setInt(key, at.millisecondsSinceEpoch);
    return true;
  }

  /// Forgets the cooldown for one subject — called when a mascot is captured,
  /// so a *different* spawn reusing the id space later isn't silenced by a
  /// stale entry, and so re-hunting after a failed capture can alert again.
  static Future<void> forget(NotificationKind kind, String subject) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_sentAtPrefix${kind.wire}_$subject');
  }

  /// Local calendar day, as `yyyy-mm-dd`. Local rather than UTC on purpose:
  /// "six per day" means six per the traveller's day.
  static String _dayStamp(DateTime at) =>
      '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
}
