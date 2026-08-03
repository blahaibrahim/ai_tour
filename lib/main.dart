import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'blocs/app/app_bloc.dart';
import 'blocs/auth/auth_bloc.dart';
import 'blocs/auth/auth_event.dart';
import 'config/app_config.dart';
import 'services/supabase_service.dart';
import 'theme.dart';
import 'app/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.load();
  await SupabaseService.initialize();

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

class AITourApp extends StatelessWidget {
  const AITourApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Tour',
      theme: AppTheme.theme,
      home: const AppShell(),
      debugShowCheckedModeBanner: false,
    );
  }
}
