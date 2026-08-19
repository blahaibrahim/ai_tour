import '../services/api_client.dart';

/// The server's view of what this traveller has agreed to be told about.
class NotificationPrefs {
  const NotificationPrefs({
    required this.enabled,
    required this.answered,
    required this.quietHoursStart,
    required this.quietHoursEnd,
    required this.routeReady,
    required this.modelReady,
    required this.mascotNearby,
    required this.splatReady,
    required this.pushConfigured,
  });

  /// The master switch — what the "Notify me" button turns on.
  final bool enabled;

  /// Whether the traveller has ever answered the prompt, either way. Distinct
  /// from [enabled] being false: the thinking screen offers "Notify me" only
  /// while this is false, so declining once is not asked again on every route.
  final bool answered;

  final int quietHoursStart;
  final int quietHoursEnd;
  final bool routeReady;
  final bool modelReady;
  final bool mascotNearby;

  /// Whether to be told when footage this traveller recorded is turned into a
  /// gaussian splat. Unlike the other three this one arrives days later and
  /// unprompted, so it is the one most worth being able to switch off alone.
  final bool splatReady;

  /// Whether the *server* can actually send a push — false when the backend
  /// has no Firebase service account. Local notifications still work; only
  /// the ones that have to arrive with the app closed don't.
  final bool pushConfigured;

  /// What a device that has never reached the server assumes. Opted out, so
  /// nothing fires on the strength of a guess.
  static const unknown = NotificationPrefs(
    enabled: false,
    answered: false,
    quietHoursStart: 22,
    quietHoursEnd: 7,
    routeReady: true,
    modelReady: true,
    mascotNearby: true,
    splatReady: true,
    pushConfigured: false,
  );

  NotificationPrefs copyWith({
    bool? enabled,
    bool? answered,
    bool? routeReady,
    bool? modelReady,
    bool? mascotNearby,
    bool? splatReady,
  }) =>
      NotificationPrefs(
        enabled: enabled ?? this.enabled,
        answered: answered ?? this.answered,
        quietHoursStart: quietHoursStart,
        quietHoursEnd: quietHoursEnd,
        routeReady: routeReady ?? this.routeReady,
        modelReady: modelReady ?? this.modelReady,
        mascotNearby: mascotNearby ?? this.mascotNearby,
        splatReady: splatReady ?? this.splatReady,
        pushConfigured: pushConfigured,
      );

  factory NotificationPrefs.fromJson(Map<String, dynamic> j) => NotificationPrefs(
        enabled: j['enabled'] as bool? ?? false,
        answered: j['answered'] as bool? ?? false,
        quietHoursStart: (j['quiet_hours_start'] as num?)?.toInt() ?? 22,
        quietHoursEnd: (j['quiet_hours_end'] as num?)?.toInt() ?? 7,
        routeReady: j['route_ready'] as bool? ?? true,
        modelReady: j['model_ready'] as bool? ?? true,
        mascotNearby: j['mascot_nearby'] as bool? ?? true,
        splatReady: j['splat_ready'] as bool? ?? true,
        pushConfigured: j['push_configured'] as bool? ?? false,
      );
}

/// Client for the notification endpoints in
/// `backend/server-node/src/routes/notifications.ts`.
///
/// Unlike [RouteRepository] there is no demo fallback here: with no backend
/// there is no server to hold a device token or a preference, and standing in
/// a fake "yes, you're subscribed" would be a promise nothing can keep. Every
/// method reports failure honestly and [NotificationService] decides what the
/// traveller is told.
class NotificationRepository {
  const NotificationRepository._();

  static Future<NotificationPrefs> fetchPrefs() async {
    final data = await ApiClient.get('/api/notifications/prefs');
    return NotificationPrefs.fromJson(data);
  }

  /// Partial update — only the fields passed are changed.
  static Future<NotificationPrefs> updatePrefs({
    bool? enabled,
    bool? routeReady,
    bool? modelReady,
    bool? mascotNearby,
    bool? splatReady,
    int? quietHoursStart,
    int? quietHoursEnd,
  }) async {
    final data = await ApiClient.put('/api/notifications/prefs', body: {
      'enabled': ?enabled,
      'route_ready': ?routeReady,
      'model_ready': ?modelReady,
      'mascot_nearby': ?mascotNearby,
      'splat_ready': ?splatReady,
      'quiet_hours_start': ?quietHoursStart,
      'quiet_hours_end': ?quietHoursEnd,
      'utc_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
    });
    return NotificationPrefs.fromJson(data);
  }

  /// Registers or refreshes this device's FCM token.
  ///
  /// [platform] must be `'android'`, `'ios'`, or `'web'`.
  /// [arCapability] is optional telemetry: `'full'`, `'limited'`, or `'none'`.
  static Future<void> registerPushToken({
    required String token,
    required String platform,
    String? arCapability,
  }) async {
    await ApiClient.post('/api/devices/push-token', body: {
      'token': token,
      'platform': platform,
      'ar_capability': ?arCapability,
      // Sent on every registration rather than once, so quiet hours follow a
      // traveller who crosses a timezone mid-trip.
      'utc_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
    });
  }

  /// Drops this device's token. Scoped to the one device — signing out of a
  /// phone must not silence the same account's other hardware.
  static Future<void> unregisterPushToken(String token) async {
    await ApiClient.delete('/api/devices/push-token', body: {'token': token});
  }
}
