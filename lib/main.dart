import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'blocs/app/app_bloc.dart';
import 'blocs/auth/auth_bloc.dart';
import 'blocs/auth/auth_event.dart';
import 'config/app_config.dart';
import 'services/backend_monitor.dart';
import 'services/notification_service.dart';
import 'services/supabase_service.dart';
import 'theme.dart';
import 'app/onboarding_gate.dart';
import 'widgets/backend_startup_toast.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.load();
  await SupabaseService.initialize();

  // Fire-and-forget: the first health check races the rest of startup rather
  // than blocking it, so a dead backend delays nothing — every repository's
  // fallback just starts out on "checking" for a moment.
  unawaited(BackendMonitor.instance.checkNow());

  // Awaited, unlike the health check: this registers the app's background
  // message handler and notification channels, and a push that arrives in the
  // window before it finishes would be dropped. It never throws — a device
  // with no Firebase configuration comes back with local notifications only.
  await NotificationService.instance.initialize();

  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => AppBloc()),
        BlocProvider(
          create: (_) => AuthBloc()..add(const AppStartedEvent()),
        ),
      ],
      child: const AITourApp(),
    ),
  );
}

class AITourApp extends StatefulWidget {
  const AITourApp({super.key});

  @override
  State<AITourApp> createState() => _AITourAppState();
}

class _AITourAppState extends State<AITourApp> {
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  bool _announcedStartupStatus = false;

  @override
  void initState() {
    super.initState();
    BackendMonitor.instance.status.addListener(_onBackendStatusChanged);
    // Covers the case where the very first health check already resolved
    // (or failed instantly, e.g. an unparsable API_BASE_URL) before this
    // widget had a chance to attach its listener.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onBackendStatusChanged();
    });
  }

  /// Announces once, the first time [BackendMonitor] leaves `checking` — this
  /// is purely a startup readout ("is this session live or demo"), not a
  /// running commentary on every later reconnect/drop.
  void _onBackendStatusChanged() {
    if (_announcedStartupStatus) return;
    final status = BackendMonitor.instance.status.value;
    if (status == BackendStatus.checking) return;
    _announcedStartupStatus = true;
    BackendMonitor.instance.status.removeListener(_onBackendStatusChanged);
    _scaffoldMessengerKey.currentState?.showSnackBar(buildBackendStartupToast(status));
  }

  @override
  void dispose() {
    BackendMonitor.instance.status.removeListener(_onBackendStatusChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Tour',
      theme: AppTheme.theme,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      // Not AppShell directly: on a first install the intro and the sign-in
      // screen come first, and the gate is what decides that.
      home: const OnboardingGate(),
      debugShowCheckedModeBanner: false,
    );
  }
}
