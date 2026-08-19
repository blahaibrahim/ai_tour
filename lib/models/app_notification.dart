/// One entry in the traveller's notification inbox.
///
/// Backed by `public.user_notifications` (supabase/migrations/20260819120000).
/// The title and body are stored on the row rather than rebuilt here, and that
/// is deliberate: a notification is a record of what the traveller was actually
/// told, so re-deriving the sentence from [data] would silently rewrite history
/// every time the backend's copy changed. Localisation is the price — the copy
/// is whatever language the server wrote it in — and it is the right way round,
/// because a *translated* history of a message that was delivered in English
/// would be a different kind of lie.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.data,
    required this.createdAt,
    required this.readAt,
  });

  final String id;

  /// `route_ready` | `model_ready` | `mascot_nearby` | `splat_ready` — the same
  /// vocabulary as `NotificationKind` in the backend and as the per-category
  /// switches in Settings. Kept as a string rather than an enum so a kind the
  /// server learns to send before the app learns to route it still *appears*,
  /// with its own copy, instead of failing to parse.
  final String kind;

  final String title;
  final String body;

  /// Everything a tap needs: the same map FCM delivers as `RemoteMessage.data`,
  /// so [NotificationTap] and this row route through identical code.
  final Map<String, dynamic> data;

  final DateTime createdAt;

  /// Null until the traveller has seen it. Only the unread count is drawn from
  /// this; the row itself does not look different once read, because a list you
  /// opened is a list you have read.
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  /// Where a tap should go, if anywhere. Null for a notification whose subject
  /// no longer exists to be opened — a `mascot_nearby` alert, for instance, is
  /// about a fennec that has long since despawned.
  String? get deepLinkId => switch (kind) {
        'route_ready' => data['route_id'] as String?,
        'model_ready' => data['artifact_id'] as String? ?? data['job_id'] as String?,
        'splat_ready' => data['splat_path'] as String?,
        _ => null,
      };

  factory AppNotification.fromRow(Map<String, dynamic> row) => AppNotification(
        id: row['id'] as String,
        kind: row['kind'] as String? ?? 'unknown',
        title: row['title'] as String? ?? '',
        body: row['body'] as String? ?? '',
        // `jsonb` comes back decoded, but a row written before the column had a
        // default — or by anything that put a scalar there — would not be a map.
        data: row['data'] is Map
            ? Map<String, dynamic>.from(row['data'] as Map)
            : const {},
        createdAt:
            DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
        readAt: row['read_at'] == null
            ? null
            : DateTime.tryParse(row['read_at'] as String)?.toLocal(),
      );

  AppNotification copyWith({DateTime? readAt}) => AppNotification(
        id: id,
        kind: kind,
        title: title,
        body: body,
        data: data,
        createdAt: createdAt,
        readAt: readAt ?? this.readAt,
      );
}
