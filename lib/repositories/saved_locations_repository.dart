import 'package:supabase_flutter/supabase_flutter.dart';

/// Persistence for the user's saved (bookmarked) locations.
///
/// Talks to `public.saved_locations` directly rather than through the Flask
/// backend: the table's RLS policy ("own saved locations") already scopes every
/// row to `auth.uid()`, so there is nothing a server round trip would add.
///
/// Every method degrades to a no-op / empty result rather than throwing. A
/// bookmark failing to sync should never break the screen the user is on — the
/// bloc keeps its optimistic local state either way.
///
/// [save] and [remove] report success when the failure was Supabase being
/// unreachable rather than the write actually being rejected: the bloc rolls
/// an optimistic toggle back on `false`, and rolling it back because there is
/// no backend right now — rather than because the save was genuinely invalid
/// — would make bookmarking silently not work in demo mode.
class SavedLocationsRepository {
  const SavedLocationsRepository._();

  static SupabaseClient get _db => Supabase.instance.client;
  static String? get _userId => _db.auth.currentUser?.id;

  /// All location ids this user has saved.
  static Future<Set<String>> fetchAll() async {
    final userId = _userId;
    if (userId == null) return {};
    try {
      final rows = await _db
          .from('saved_locations')
          .select('location_id')
          .eq('user_id', userId);
      return {
        for (final row in rows) row['location_id'] as String,
      };
    } catch (_) {
      return {};
    }
  }

  /// Returns true if the write landed (or was assumed to, offline). Returns
  /// false only when a reachable server actually rejected it — `location_id`
  /// is a foreign key to `locations`, so saving one the catalogue doesn't
  /// know about (a locally-seeded one, say) is a real rejection.
  static Future<bool> save(String locationId) async {
    final userId = _userId;
    if (userId == null) return false;
    try {
      await _db.from('saved_locations').upsert(
        {'user_id': userId, 'location_id': locationId},
        onConflict: 'user_id,location_id',
      );
      return true;
    } catch (e) {
      return _isBackendUnreachable(e);
    }
  }

  static Future<bool> remove(String locationId) async {
    final userId = _userId;
    if (userId == null) return false;
    try {
      await _db
          .from('saved_locations')
          .delete()
          .eq('user_id', userId)
          .eq('location_id', locationId);
      return true;
    } catch (e) {
      return _isBackendUnreachable(e);
    }
  }
}

/// True when [error] means Supabase couldn't be reached at all, as opposed to
/// answering with a genuine rejection (e.g. a `PostgrestException` from a
/// constraint violation).
bool _isBackendUnreachable(Object error) =>
    error is! PostgrestException && error is! AuthException;
