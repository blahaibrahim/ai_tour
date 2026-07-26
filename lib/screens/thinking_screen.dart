import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme.dart';

class ThinkingScreen extends StatefulWidget {
  const ThinkingScreen({super.key});

  @override
  State<ThinkingScreen> createState() => _ThinkingScreenState();
}

class _ThinkingScreenState extends State<ThinkingScreen> with TickerProviderStateMixin {
  late final AnimationController _spinController;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      duration: const Duration(milliseconds: 1100),
      vsync: this,
    )..repeat();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _spinController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Spinning geometric square
              SizedBox(
                width: 56,
                height: 56,
                child: Stack(
                  children: [
                    // Rotating square
                    Positioned.fill(
                      child: RotationTransition(
                        turns: Tween(begin: 0.0, end: 1.0).animate(_spinController),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: AppTheme.brLg,
                            border: Border.all(color: AppTheme.accent, width: 2.5),
                          ),
                        ),
                      ),
                    ),
                    // Pulsing icon
                    Positioned.fill(
                      child: FadeTransition(
                        opacity: Tween<double>(begin: 0.35, end: 1.0).animate(_pulseController),
                        child: ScaleTransition(
                          scale: Tween<double>(begin: 0.85, end: 1.05).animate(_pulseController),
                          child: const Center(
                            child: Icon(Icons.send, color: AppTheme.accent, size: 20),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              
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
      ),
    );
  }
}
