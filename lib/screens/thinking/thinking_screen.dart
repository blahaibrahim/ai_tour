import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/app/app_bloc.dart';
import '../../blocs/app/app_event.dart';
import '../../blocs/app/app_state.dart';
import '../../theme.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/compass_spinner.dart';

class ThinkingScreen extends StatelessWidget {
  const ThinkingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppBloc>().state;

    return Scaffold(
      body: AppBackdrop(child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CompassSpinner(size: 84),
              const SizedBox(height: 26),
              Text(
                'Building your shortlist',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 18),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 34,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Text(
                    AppState.thinkingMessages[state.thinkIdx],
                    key: ValueKey(state.thinkIdx),
                    style: TextStyle(fontSize: 13.5, color: AppTheme.text.withOpacity(0.75)),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      )),
    );
  }
}
