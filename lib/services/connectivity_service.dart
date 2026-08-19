import 'dart:async';

import 'package:flutter/foundation.dart';

import 'backend_monitor.dart';

/// Reactive connectivity wrapper over [BackendMonitor].
///
/// Listens to the existing [BackendMonitor.status] and exposes:
///   * a synchronous [isOnline] / [isOffline] getter,
///   * a [Stream<bool>] that fires on every *transition* (not on every health
///     check), so listeners get one event per edge, not a pulse.
///
/// The bloc subscribes to [onConnectivityChanged] and triggers outbox flushes
/// on the `false → true` (offline → online) transition.
class ConnectivityService {
  ConnectivityService._() {
    _monitor.status.addListener(_onStatusChanged);
    _lastOnline = _monitor.status.value == BackendStatus.connected;
  }

  static final ConnectivityService instance = ConnectivityService._();

  final BackendMonitor _monitor = BackendMonitor.instance;
  final _controller = StreamController<bool>.broadcast();
  bool _lastOnline = false;

  bool get isOnline => _monitor.status.value == BackendStatus.connected;
  bool get isOffline => !isOnline;

  /// Fires `true` when connectivity is restored, `false` when lost.
  /// Only fires on *transitions*, not on every health-check tick.
  Stream<bool> get onConnectivityChanged => _controller.stream;

  void _onStatusChanged() {
    final nowOnline = _monitor.status.value == BackendStatus.connected;
    if (nowOnline == _lastOnline) return;
    _lastOnline = nowOnline;
    _controller.add(nowOnline);
  }

  /// Call once if the app is being torn down. Normal apps leave this running.
  @visibleForTesting
  void dispose() {
    _monitor.status.removeListener(_onStatusChanged);
    _controller.close();
  }
}
