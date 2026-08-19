import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_notification.dart';

/// The notification inbox: reads and the traveller's own deletes.
///
/// Talks to `public.user_notifications` directly rather than through the Node
/// backend, for the same reason [SavedLocationsRepository] does: every policy
/// there is to enforce is already in the table's RLS — select, update and delete
/// are each scoped to `auth.uid()` — so a server round trip would add a hop and
/// no guarantee. Inserts are the exception and are *not* here at all: the
/// migration grants the client no insert, because an inbox the app can write to
/// is an app that can post itself a notification.
///
/// Every method degrades rather than throwing. A notifications screen that
/// cannot reach Supabase should say it is empty and offer to retry, not take
/// down the screen that opened it.
class NotificationInboxRepository {
  const NotificationInboxRepository._();

  static SupabaseClient get _db => Supabase.instance.client;
  static String? get _userId => _db.auth.currentUser?.id;

  /// How many rows the screen holds. A traveller with more than this has months
  /// of history and is not scrolling to the bottom of it; the cap is what keeps
  /// one query from growing without limit.
  static const int _pageSize = 200;

  /// Newest first. Empty when signed out or unreachable.
  static Future<List<AppNotification>> fetchAll() async {
    if (_userId == null) return const [];
    try {
      final rows = await _db
          .from('user_notifications')
          // No `.eq('user_id', …)`: the select policy already restricts this to
          // the caller's own rows, and a filter that repeats it would be a
          // second place to get it wrong.
          .select('id, kind, title, body, data, dedupe_key, read_at, created_at')
          .order('created_at', ascending: false)
          .limit(_pageSize);
      return [
        for (final row in rows) AppNotification.fromRow(Map<String, dynamic>.from(row)),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Unread count, without the rows — for the badge on the home header.
  static Future<int> unreadCount() async {
    if (_userId == null) return 0;
    try {
      final rows = await _db
          .from('user_notifications')
          .select('id')
          .isFilter('read_at', null)
          .limit(_pageSize);
      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  /// Marks everything currently unread as read.
  ///
  /// Called when the screen opens, not per row as they scroll past: the whole
  /// list is on screen at once and "read" here means "you have seen your
  /// notifications", which opening the screen is exactly what does.
  static Future<void> markAllRead() async {
    if (_userId == null) return;
    try {
      await _db
          .from('user_notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .isFilter('read_at', null);
    } catch (_) {
      // The badge is optimistically cleared by the caller either way. Being
      // told twice about something already seen is a small cost; a screen that
      // refuses to open because a bookkeeping write failed is not.
    }
  }

  /// Deletes one. Returns false when a reachable server refused it.
  static Future<bool> remove(String id) async {
    if (_userId == null) return false;
    try {
      await _db.from('user_notifications').delete().eq('id', id);
      return true;
    } catch (e) {
      return _isBackendUnreachable(e);
    }
  }

  /// Empties the inbox.
  ///
  /// `neq('id', …)` on an impossible uuid rather than a bare `delete()`:
  /// PostgREST rejects an unfiltered delete outright, which is a good default —
  /// it is the one that stops a forgotten `.eq` from emptying a table. The
  /// filter is a formality here because RLS scopes the statement to this
  /// traveller's rows regardless of what it matches.
  static Future<bool> clearAll() async {
    if (_userId == null) return false;
    try {
      await _db
          .from('user_notifications')
          .delete()
          .neq('id', '00000000-0000-0000-0000-000000000000');
      return true;
    } catch (e) {
      return _isBackendUnreachable(e);
    }
  }
}

/// True when [error] means Supabase could not be reached at all, as opposed to
/// answering with a genuine rejection.
bool _isBackendUnreachable(Object error) =>
    error is! PostgrestException && error is! AuthException;
