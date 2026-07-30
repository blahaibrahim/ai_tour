import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'blocs/app/app_bloc.dart';
import 'theme.dart';
import 'app/app_shell.dart';

void main() {
  runApp(
    BlocProvider(
      create: (_) => AppBloc(),
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
