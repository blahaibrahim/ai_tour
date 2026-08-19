import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// Whether the Node backend is reachable right now.
enum BackendStatus {
  /// No verdict yet — the first health check hasn't landed.
  checking,
  connected,
  offline,
}

/// App-wide verdict on whether the backend is reachable, driving both the
/// one-time startup toast (see `backend_startup_toast.dart`) and every
/// repository's decision to serve real data or a demo fallback.
///
/// Repositories call [reportSuccess] / [reportFailure] from their own
/// request handling as a side effect, so the status reflects real traffic
/// between health checks rather than only the periodic probe. This is a
/// plain [ValueNotifier] rather than a bloc: it has no user-facing events,
/// only a status other widgets read, and every repository — several of which
/// predate any bloc dependency — needs to reach it without a BuildContext.
class BackendMonitor {
  BackendMonitor._();

  static final BackendMonitor instance = BackendMonitor._();

  final ValueNotifier<BackendStatus> status =
      ValueNotifier<BackendStatus>(BackendStatus.checking);

  Timer? _retryTimer;
  bool _checking = false;

  bool get isOffline => status.value == BackendStatus.offline;

  /// How long the *first* probe waits before calling it: short, so a dead
  /// server never leaves the splash/banner stuck on "checking".
  static const Duration _firstProbeTimeout = Duration(seconds: 5);

  /// How long a background retry waits — much longer, because nothing is
  /// blocked on it and because the thing it is most often waiting for is a
  /// free-tier instance waking up, which takes ~45 s from cold. A retry that
  /// gave up at 5 s would never once catch the wake it had itself triggered,
  /// and the app would sit on demo data until somebody restarted it.
  static const Duration _retryProbeTimeout = Duration(seconds: 30);

  /// Pings `/api/health` once.
  Future<void> checkNow() async {
    if (_checking) return;
    _checking = true;
    try {
      final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/health');
      final response = await http.get(uri).timeout(
            status.value == BackendStatus.checking
                ? _firstProbeTimeout
                : _retryProbeTimeout,
          );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        reportSuccess();
      } else {
        reportFailure();
      }
    } catch (_) {
      reportFailure();
    } finally {
      _checking = false;
    }
  }

  /// Called by a repository after a real request to the Node backend or
  /// Supabase succeeded.
  void reportSuccess() {
    _retryTimer?.cancel();
    _retryTimer = null;
    if (status.value != BackendStatus.connected) {
      status.value = BackendStatus.connected;
    }
  }

  /// Called after a request failed for a connectivity reason (timeout,
  /// socket error, unreachable host) — not for an ordinary 4xx/5xx from a
  /// server that did answer.
  void reportFailure() {
    if (status.value != BackendStatus.offline) {
      status.value = BackendStatus.offline;
    }
    _scheduleRetry();
  }

  /// While offline, keeps probing in the background so the app recovers to
  /// live data on its own once the backend comes back — nobody should have
  /// to restart the app to leave demo mode.
  void _scheduleRetry() {
    if (_retryTimer != null) return;
    _retryTimer = Timer.periodic(const Duration(seconds: 20), (_) => checkNow());
  }
}

/// True for an exception that means "could not reach the server at all",
/// as opposed to the server answering with an error. Shared by every
/// repository deciding whether to fall back to demo data.
bool isConnectivityError(Object error) {
  return error is SocketException ||
      error is TimeoutException ||
      error is http.ClientException;
}
