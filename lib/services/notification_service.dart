import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../repositories/notification_repository.dart';
import 'api_client.dart';
import 'notification_policy.dart';

/// Handles a push that arrives while the app is terminated or backgrounded.
///
/// Must be a top-level function with `@pragma('vm:entry-point')`: Android runs
/// it in a separate isolate with no access to anything this app has set up, so
/// a closure or a method would not survive tree-shaking in release builds.
///
/// It deliberately does almost nothing. Every message the backend sends
/// carries a `notification` block alongside its data, which means the OS has
/// already drawn the notification by the time this runs — showing another one
/// here is the classic way to get every push twice.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  developer.log(
    'Background push: ${message.data['type']}',
    name: 'NotificationService',
  );
}

/// One place for everything the app tells the traveller when they are not
/// looking at it.
///
/// **Three triggers, two mechanisms.** The app notifies about three things,
/// and they do not all arrive the same way — which is a design decision, not
/// an inconsistency:
///
///   * **A route is ready.** Local. Route generation is a single synchronous
///     request the client holds open (`RouteRepository.generateRoute`), so the
///     client is the first to know and the server never finds out at all. The
///     "Notify me" button on the thinking screen is what turns this on, and
///     because it writes a *user* preference rather than a per-route one, it
///     is asked once and then applies to every route after it.
///   * **A 3D model finished.** Push. This one genuinely happens on a server,
///     minutes later, with the app very possibly closed — the only case in the
///     app where FCM is the difference between the traveller finding out and
///     not. Delivered by the `model_jobs` trigger →
///     `POST /api/internal/model-job-notify` → FCM. When the app *is* running,
///     the existing Supabase realtime subscription usually wins the race, so
///     both paths dedupe through [NotificationPolicy] on the job id.
///   * **A fennec is nearby.** Local, from the hunt's own band tracker.
///     docs/mascot_plan.md §5.6 rules push out for this explicitly: it would
///     require streaming the traveller's live position to the backend, with
///     the battery, data and privacy cost that implies.
///
/// **Everything degrades.** With no Firebase configuration on the device
/// ([fcmAvailable] false) local notifications still work and only the
/// app-is-closed 3D completion is lost. With no backend reachable, the
/// preference cannot be stored and [enable] says so rather than pretending.
class NotificationService with WidgetsBindingObserver {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const String _defaultChannelId = 'massar_default';
  static const String _huntChannelId = 'massar_hunt';

  /// Mirrors the server preference so the UI can render a toggle without a
  /// round trip. Written by [enable], [disable] and [syncFromServer].
  final ValueNotifier<NotificationPrefs> prefs =
      ValueNotifier<NotificationPrefs>(NotificationPrefs.unknown);

  /// Set when a notification tap should take the traveller somewhere. The app
  /// shell watches this; it is a notifier rather than a callback so a tap that
  /// lands before the widget tree exists (a cold start from the tray) is not
  /// dropped.
  ///
  /// Consumers must call [consumeDeepLink] rather than reading it directly, so
  /// the same tap is not acted on twice when the shell rebuilds.
  final ValueNotifier<NotificationTap?> pendingDeepLink =
      ValueNotifier<NotificationTap?>(null);

  /// Takes the pending tap, clearing it. Returns null if there is none.
  NotificationTap? consumeDeepLink() {
    final tap = pendingDeepLink.value;
    pendingDeepLink.value = null;
    return tap;
  }

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _fcmAvailable = false;
  String? _token;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  /// True when Firebase initialised — i.e. `google-services.json` /
  /// `GoogleService-Info.plist` are present in the build. False is a supported
  /// state, not an error: see the class comment.
  bool get fcmAvailable => _fcmAvailable;

  /// True while the traveller can actually see the app. Every local
  /// notification checks this: §5.6's "suppressed entirely while the app is in
  /// the foreground (the UI is already saying it)".
  ///
  /// `inactive` counts as foreground, not background. It is the state during
  /// an incoming call, the app switcher, a pulled-down notification shade, or
  /// a system permission dialog — the app is still on screen underneath, and
  /// on the way to the background it is only ever a brief stop before
  /// `hidden`/`paused`. Treating it as background would post a notification
  /// over the top of the very screen that is about to show the same thing.
  bool get isForeground =>
      _lifecycle == AppLifecycleState.resumed ||
      _lifecycle == AppLifecycleState.inactive;

  // ---------------------------------------------------------------------------
  // Startup
  // ---------------------------------------------------------------------------

  /// Sets up local notifications and, if the platform is configured for it,
  /// Firebase. Safe to call once from `main`; never throws.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    WidgetsBinding.instance.addObserver(this);

    await _initLocalNotifications();
    await _initFirebase();
  }

  Future<void> _initLocalNotifications() async {
    try {
      await _local.initialize(
        const InitializationSettings(
          // The launcher icon doubles as the notification icon. A dedicated
          // monochrome asset would be better on Android — the platform masks
          // this to a silhouette — but a missing drawable makes the
          // notification fail to post entirely, which is worse.
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            // Permission is requested in `enable()`, at the moment the
            // traveller asks for notifications, rather than fired at a
            // stranger during the first frame of a cold start.
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload == null) return;
          // "<type>|<id>" — the plugin's payload is a single string, and the
          // id half is what makes a route tap able to find its route.
          final parts = payload.split('|');
          pendingDeepLink.value = NotificationTap(
            parts.first,
            id: parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null,
          );
        },
      );

      final android = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      // Two channels so the OS settings screen can silence "a fennec is
      // nearby" without also silencing "your model is ready" — the hunt is the
      // only one of the three that speaks unprompted, and it is the one a
      // traveller is most likely to want to turn down.
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        _defaultChannelId,
        'Routes and models',
        description: 'When a route is ready, or a 3D capture has finished.',
        importance: Importance.high,
      ));
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        _huntChannelId,
        'Fennec hunt',
        description: 'When you are getting close to a hidden fennec.',
        importance: Importance.high,
      ));
    } catch (error, stack) {
      developer.log('Local notifications unavailable',
          name: 'NotificationService', error: error, stackTrace: stack);
    }
  }

  Future<void> _initFirebase() async {
    try {
      // No `options:` argument on purpose. Reading the native config files
      // that `flutterfire configure` drops in means this file needs no
      // generated `firebase_options.dart` import — so the project still
      // compiles for anyone who has not run that command yet, and lights up
      // with no code change once they have.
      await Firebase.initializeApp();
      _fcmAvailable = true;
    } catch (error) {
      developer.log(
        'Firebase is not configured on this platform; push notifications are '
        'off and local notifications still work. See '
        'docs/backend/15-notifications-and-fcm.md.',
        name: 'NotificationService',
        error: error,
      );
      _fcmAvailable = false;
      return;
    }

    try {
      FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => _handleTap(message.data),
      );

      // A push that started the app from cold: `onMessageOpenedApp` never
      // fires for it, because there was no app listening when it was tapped.
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _handleTap(initial.data);

      // FCM rotates tokens on reinstall, restore, and occasionally on its own.
      // A registration that is never refreshed silently stops being delivered
      // to, and nothing about the app looks broken while it happens.
      FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        _token = token;
        if (prefs.value.enabled) unawaited(_registerToken(token));
      });
    } catch (error, stack) {
      developer.log('Could not wire FCM listeners',
          name: 'NotificationService', error: error, stackTrace: stack);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
  }

  // ---------------------------------------------------------------------------
  // The toggle
  // ---------------------------------------------------------------------------

  /// Why [enable] did not fully succeed, so the caller can say something
  /// truthful instead of a blanket "enabled!".
  ///
  /// [EnableOutcome.enabledLocalOnly] is the interesting one: permission was
  /// granted and the preference stored, but this build has no Firebase
  /// configuration, so notifications fire only while the app is running. That
  /// is most of the feature, and worth reporting as a qualified yes rather
  /// than a failure.
  Future<EnableOutcome> enable() async {
    final granted = await _requestPermission();
    if (!granted) return EnableOutcome.permissionDenied;

    // Store the preference first. It is the part that has to survive — the
    // token can be re-registered on any later launch, but a preference that
    // was never written means the traveller is asked again next time as if
    // they had never pressed anything.
    try {
      final updated = await NotificationRepository.updatePrefs(enabled: true);
      prefs.value = updated;
    } on ApiException catch (error) {
      developer.log('Could not store notification preference',
          name: 'NotificationService', error: error);
      return EnableOutcome.backendUnreachable;
    } catch (error) {
      developer.log('Could not store notification preference',
          name: 'NotificationService', error: error);
      return EnableOutcome.backendUnreachable;
    }

    await _cacheEnabledLocally(true);

    if (!_fcmAvailable) return EnableOutcome.enabledLocalOnly;

    final token = await _currentToken();
    if (token == null) return EnableOutcome.enabledLocalOnly;
    final registered = await _registerToken(token);
    return registered ? EnableOutcome.enabled : EnableOutcome.enabledLocalOnly;
  }

  /// Turns everything off and drops this device's token, so an opted-out
  /// traveller is not relying on every future call site remembering to check.
  Future<void> disable() async {
    try {
      final updated = await NotificationRepository.updatePrefs(enabled: false);
      prefs.value = updated;
    } catch (error) {
      developer.log('Could not store notification preference',
          name: 'NotificationService', error: error);
      prefs.value = prefs.value.copyWith(enabled: false, answered: true);
    }

    await _cacheEnabledLocally(false);

    final token = _token;
    if (token != null) {
      try {
        await NotificationRepository.unregisterPushToken(token);
      } catch (error) {
        developer.log('Could not unregister push token',
            name: 'NotificationService', error: error);
      }
    }
  }

  /// Flips one category without touching the master switch.
  Future<void> setCategory({
    bool? routeReady,
    bool? modelReady,
    bool? mascotNearby,
  }) async {
    // Optimistic, so the switch moves under the finger; the server's answer
    // replaces it a moment later either way.
    prefs.value = prefs.value.copyWith(
      routeReady: routeReady,
      modelReady: modelReady,
      mascotNearby: mascotNearby,
    );
    try {
      prefs.value = await NotificationRepository.updatePrefs(
        routeReady: routeReady,
        modelReady: modelReady,
        mascotNearby: mascotNearby,
      );
    } catch (error) {
      developer.log('Could not store notification category',
          name: 'NotificationService', error: error);
    }
  }

  /// Pulls the stored preference in at startup and after sign-in, and
  /// re-registers this device's token if it is meant to be on.
  ///
  /// The re-registration is the point: a token is not permanent, and a
  /// traveller who opted in three months ago has almost certainly been issued
  /// a new one since.
  Future<void> syncFromServer() async {
    try {
      final stored = await NotificationRepository.fetchPrefs();
      prefs.value = stored;
      await _cacheEnabledLocally(stored.enabled);

      if (!stored.enabled || !_fcmAvailable) return;
      final token = await _currentToken();
      if (token != null) await _registerToken(token);
    } catch (error) {
      // Offline at launch is ordinary. Fall back to the last known answer so
      // the toggle in Settings is not wrong until the network comes back.
      final cached = await _cachedEnabled();
      if (cached != null) {
        prefs.value = prefs.value.copyWith(enabled: cached, answered: true);
      }
      developer.log('Could not sync notification prefs',
          name: 'NotificationService', error: error);
    }
  }

  Future<bool> _requestPermission() async {
    // iOS and Android 13+ both gate notifications behind a runtime prompt, but
    // through different plugins — firebase_messaging owns it when FCM is
    // present, flutter_local_notifications when it is not.
    try {
      if (_fcmAvailable) {
        final settings = await FirebaseMessaging.instance.requestPermission();
        return settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
      }

      if (Platform.isIOS || Platform.isMacOS) {
        final ios = _local.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        return await ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
      }

      if (Platform.isAndroid) {
        final android = _local.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        return await android?.requestNotificationsPermission() ?? true;
      }
    } catch (error) {
      developer.log('Notification permission request failed',
          name: 'NotificationService', error: error);
    }
    return false;
  }

  Future<String?> _currentToken() async {
    if (!_fcmAvailable) return null;
    if (_token != null) return _token;
    try {
      // APNs has to have handed iOS a device token before FCM can mint one,
      // and that can take a moment after a cold start; the bound stops a
      // never-completing future from hanging the toggle.
      _token = await FirebaseMessaging.instance
          .getToken()
          .timeout(const Duration(seconds: 10));
    } catch (error) {
      developer.log('Could not obtain an FCM token',
          name: 'NotificationService', error: error);
    }
    return _token;
  }

  Future<bool> _registerToken(String token) async {
    try {
      await NotificationRepository.registerPushToken(
        token: token,
        platform: Platform.isIOS ? 'ios' : 'android',
      );
      return true;
    } catch (error) {
      developer.log('Could not register push token',
          name: 'NotificationService', error: error);
      return false;
    }
  }

  Future<void> _cacheEnabledLocally(bool enabled) async {
    try {
      final store = await SharedPreferences.getInstance();
      await store.setBool('notifications_enabled', enabled);
    } catch (_) {
      // A cache miss costs one extra round trip, nothing more.
    }
  }

  Future<bool?> _cachedEnabled() async {
    try {
      return (await SharedPreferences.getInstance()).getBool('notifications_enabled');
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Incoming push
  // ---------------------------------------------------------------------------

  /// A push that arrived while the traveller was looking at the app.
  ///
  /// Nothing is drawn. The screen is already showing whatever this would have
  /// said — the folder updates itself from the realtime subscription — and a
  /// notification for something visible on screen is noise. The message is
  /// still worth claiming in the policy so the realtime path and this one do
  /// not both count as an alert later.
  void _onForegroundMessage(RemoteMessage message) {
    developer.log('Foreground push suppressed: ${message.data['type']}',
        name: 'NotificationService');
  }

  void _handleTap(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    if (type == null) return;
    pendingDeepLink.value = NotificationTap(
      type,
      // Whichever key this kind of message carries; both are set by
      // `notifications/index.ts`.
      id: (data['route_id'] ?? data['artifact_id'] ?? data['job_id']) as String?,
    );
  }

  // ---------------------------------------------------------------------------
  // Outgoing local notifications
  // ---------------------------------------------------------------------------

  /// "Your route is ready" — trigger 1, for a backgrounded but living app.
  ///
  /// Ownership of this notification is split with the server, and the split is
  /// on a question only each side can answer for itself:
  ///
  ///   * **This device decides whether to show it at all.** Foreground, and
  ///     nothing is shown — the screen is already about to display the route.
  ///     Backgrounded, and this fires. The server cannot make that call: a
  ///     backgrounded app and a foreground one look identical from the far end
  ///     of an HTTP request.
  ///   * **The server handles the app being killed.** Generation keeps running
  ///     there after the client disconnects, and a push is then the only thing
  ///     that can reach the traveller — a local notification cannot be fired
  ///     by a process that no longer exists. `POST /api/routes` pushes if, and
  ///     only if, it could not deliver its response.
  ///
  /// So the two never overlap: this path runs exactly when the response
  /// arrived, and the push runs exactly when it did not. Unlike
  /// [showModelResult] there is no "push owns it" early return, because push
  /// is not sent for a client that is still listening.
  ///
  /// [routeTitle] names the city so a traveller with the phone in a pocket
  /// knows which of several things finished.
  Future<void> showRouteReady({String? routeTitle, String? routeId}) async {
    // The opt-in. `prefs` is `unknown` (opted out) until the server says
    // otherwise, so nothing fires before the traveller has pressed "Notify me"
    // — including on a cold start where the sync has not landed yet.
    if (!prefs.value.enabled || !prefs.value.routeReady) return;
    if (isForeground) return;

    final allowed = await NotificationPolicy.claim(
      kind: NotificationKind.routeReady,
      // The traveller pressed a button and is waiting; a route arriving is not
      // the app volunteering something, so it does not spend the daily budget.
      countsTowardDailyCap: false,
      subject: routeId ?? routeTitle ?? 'route',
    );
    if (!allowed) return;

    await _show(
      id: 1001,
      channelId: _defaultChannelId,
      title: 'Your route is ready',
      body: routeTitle == null
          ? 'Tap to see where you are going.'
          : '$routeTitle is planned and waiting for you.',
      payload: 'route_ready|${routeId ?? ''}',
    );
  }

  /// "Your 3D model is ready" / "that didn't work out" — trigger 2, on the
  /// path where the app is running and the Supabase realtime subscription
  /// noticed the finished job.
  ///
  /// **Exactly one of the two paths owns this notification, and push wins.**
  /// When FCM is working end to end the server has already sent a message
  /// carrying a `notification` block, which the OS draws itself the moment the
  /// app is not in the foreground — there is no hook that can call it back.
  /// So the choice is not "which do we prefer" but "which do we suppress", and
  /// it has to be this one: a local notification fired here would be the
  /// second copy of something already on screen. Deduping on the job id cannot
  /// help, because the two paths keep their records in different places (this
  /// one in [NotificationPolicy] on the device, the server's in
  /// `notification_log`) and the push never passes through Dart at all.
  ///
  /// That leaves this path doing the work whenever push cannot: a build with
  /// no Firebase configuration, or a backend with no service account. The
  /// trade is a job whose push is silently dropped — a token FCM pruned, say —
  /// going unannounced, rather than every finished job announcing itself
  /// twice.
  Future<void> showModelResult({
    required String jobId,
    required bool succeeded,
    String? errorCode,
  }) async {
    if (!prefs.value.enabled || !prefs.value.modelReady) return;
    if (isForeground) return;
    if (_fcmAvailable && prefs.value.pushConfigured) return;

    final allowed = await NotificationPolicy.claim(
      kind: NotificationKind.modelReady,
      subject: jobId,
      countsTowardDailyCap: false,
    );
    if (!allowed) return;

    await _show(
      id: jobId.hashCode & 0x7fffffff,
      channelId: _defaultChannelId,
      title: succeeded ? 'Your 3D model is ready' : "That capture didn't work out",
      body: succeeded
          ? 'Tap to see it in your folder.'
          : _modelFailureBody(errorCode),
      payload: 'model_ready|$jobId',
    );
  }

  /// "You're getting close" — trigger 3.
  ///
  /// Called from the hunt's band tracker on entering HOT and again on
  /// BURNING. [spawnId] is the dedupe subject, so the 15-minute cooldown is
  /// per mascot: two spawns on the same walk each get their alert, while
  /// hovering at the edge of one band gets a single one however much the
  /// reading flaps.
  Future<void> showMascotNearby({
    required String spawnId,
    required bool canCapture,
    String? stopName,
  }) async {
    if (!prefs.value.enabled || !prefs.value.mascotNearby) return;
    if (isForeground) return;

    final allowed = await NotificationPolicy.claim(
      kind: NotificationKind.mascotNearby,
      // BURNING is allowed to speak over HOT's cooldown — it is a different
      // message ("open the camera" rather than "keep walking") and it is the
      // one that matters. §5.6 specifies exactly this upgrade.
      subject: canCapture ? '$spawnId:burning' : spawnId,
      quietHoursStart: prefs.value.quietHoursStart,
      quietHoursEnd: prefs.value.quietHoursEnd,
    );
    if (!allowed) return;

    await _show(
      id: spawnId.hashCode & 0x7ffffffe | (canCapture ? 1 : 0),
      channelId: _huntChannelId,
      title: canCapture ? 'A fennec is right here!' : "You're getting warm",
      body: canCapture
          ? 'Tap to open the camera and catch it.'
          : stopName == null
              ? 'A fennec is hiding somewhere close by.'
              : 'A fennec is hiding near $stopName.',
      payload: 'mascot_nearby|$spawnId',
    );
  }

  Future<void> _show({
    required int id,
    required String channelId,
    required String title,
    required String body,
    required String payload,
  }) async {
    try {
      await _local.show(
        id,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelId == _huntChannelId ? 'Fennec hunt' : 'Routes and models',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        payload: payload,
      );
    } catch (error, stack) {
      developer.log('Could not show notification',
          name: 'NotificationService', error: error, stackTrace: stack);
    }
  }

  static String _modelFailureBody(String? errorCode) => switch (errorCode) {
        'no_subject' =>
          "We couldn't find a clear object — try filling more of the frame with it.",
        'timeout' => 'It took too long to build. Tap to try that photo again.',
        'quota_exceeded' => "You've used all your model credits for today.",
        _ => 'Something went wrong building it. Tap to try again.',
      };
}

/// A notification the traveller tapped.
///
/// [id] is whatever the notification was about — a route id for `route_ready`,
/// a job id for `model_ready`. It matters most for a route: if the app was
/// killed while generating, nothing about that route survives in memory, and
/// this id is the only way back to it.
class NotificationTap {
  const NotificationTap(this.type, {this.id});

  final String type;
  final String? id;
}

/// What [NotificationService.enable] managed to do.
enum EnableOutcome {
  /// Fully on, including pushes that arrive with the app closed.
  enabled,

  /// On, but this build has no Firebase configuration (or FCM would not issue
  /// a token), so notifications only fire while the app is running.
  enabledLocalOnly,

  /// The traveller said no at the OS prompt. Nothing was changed.
  permissionDenied,

  /// The preference could not be stored, so it would not survive a restart.
  backendUnreachable,
}
