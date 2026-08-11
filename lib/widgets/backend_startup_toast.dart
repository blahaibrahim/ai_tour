import 'package:flutter/material.dart';

import '../services/backend_monitor.dart';

/// A native-toast-style [SnackBar]: dark grey pill, centred low on the
/// screen, gone on its own after a few seconds — not something the
/// traveller has to notice or dismiss.
///
/// Shown once, right after [BackendMonitor]'s first health check resolves at
/// launch, so there's a single honest answer to "is this app talking to a
/// server or showing me demo data" without a persistent badge nagging about
/// it on every screen afterward.
SnackBar buildBackendStartupToast(BackendStatus status) {
  final connected = status == BackendStatus.connected;
  return SnackBar(
    behavior: SnackBarBehavior.floating,
    width: 300,
    duration: const Duration(seconds: 3),
    backgroundColor: const Color(0xFF323232),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    elevation: 6,
    content: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          connected ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
          color: Colors.white,
          size: 17,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            connected ? 'Connected to the server' : "Can't reach the server — showing demo data",
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
      ],
    ),
  );
}
