import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../blocs/app/app_bloc.dart';
import '../../../theme.dart';

/// Segmented progress bar showing which card in the queue is currently active.
class SwipeProgressBar extends StatelessWidget {
  const SwipeProgressBar({super.key, required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppBloc>().state;

    return SizedBox(
      width: width,
      child: Row(
        children: List.generate(state.queue.length, (index) {
          final isActive = index == state.currentIndex;
          final isCompleted = index < state.currentIndex;
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: isActive
                    ? AppTheme.accent
                    : (isCompleted
                          ? AppTheme.accent.withValues(alpha: 0.4)
                          : AppTheme.text.withValues(alpha: 0.15)),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }
}
