import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/app/app_bloc.dart';
import '../../blocs/app/app_event.dart';
import '../../theme.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/glass_surface.dart';
import 'widgets/current_stop_card.dart';
import 'widgets/current_task_panel.dart';
import 'widgets/upcoming_stops_row.dart';
import '../settings/settings_screen.dart';

class OverviewScreen extends StatelessWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppBloc>().state;
    final currentStop = state.currentStopIdx < state.accepted.length
        ? state.accepted[state.currentStopIdx]
        : null;

    return Scaffold(
      body: AppBackdrop(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 60, 20, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'YOUR ROUTE',
                                style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: Colors.white70, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                currentStop?.name ?? 'All done!',
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white, fontSize: 26),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(color: Colors.white12, borderRadius: AppTheme.brPill),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.stars, size: 14, color: Colors.white),
                                  const SizedBox(width: 4),
                                  Text('${state.points} pts', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            PressableScale(
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                              child: GlassSurface(
                                tint: GlassTint.dark,
                                borderRadius: AppTheme.brPill,
                                alignment: Alignment.center,
                                child: const SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: Icon(Icons.settings_outlined, color: Colors.white, size: 20),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Stop progress dots
                    if (state.accepted.isNotEmpty) ...[
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: List.generate(state.accepted.length, (i) {
                            final isDone = i < state.currentStopIdx;
                            final isCurrent = i == state.currentStopIdx;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              margin: const EdgeInsets.only(right: 6),
                              width: isCurrent ? 20 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: isDone
                                    ? Colors.white.withOpacity(0.5)
                                    : (isCurrent ? Colors.white : Colors.white30),
                                borderRadius: AppTheme.brPill,
                              ),
                            );
                          }),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Current stop card
                    if (currentStop != null) ...[
                      CurrentStopCard(stop: currentStop),
                      const SizedBox(height: 20),
                      CurrentTaskPanel(stop: currentStop),
                      const UpcomingStopsRow(),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(color: Colors.white12, borderRadius: AppTheme.brLg),
                        child: Column(
                          children: [
                            const Icon(Icons.flag_outlined, color: Colors.white, size: 40),
                            const SizedBox(height: 12),
                            Text('Route complete!', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white, fontSize: 20)),
                            const SizedBox(height: 8),
                            Text(
                              'You have completed all stops on your route. Check your folder for captured artifacts.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.8)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
